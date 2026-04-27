#!/usr/bin/env python3
"""
Caption Burn Service — Runs on VPS host (NOT inside n8n container).
Burns SRT captions into assembled videos via docker exec FFmpeg.
Triggered by WF_CAPTIONS_ASSEMBLY after Drive upload completes.

Port: 9998
Why: n8n task runner OOMs when re-encoding video + uploading large files.
     Running FFmpeg via docker exec from the host avoids task runner memory limits.

Usage:
  python3 caption_burn_service.py &
  # Or install as systemd service (see caption-burn.service)

Endpoints:
  POST /burn — Burns captions into video, re-uploads to Drive
  GET  /health — Health check
"""

import json
import subprocess
import threading
import traceback
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.parse import quote


def log(msg):
    sys.stdout.write(str(msg) + "\n")
    sys.stdout.flush()

PORT = 9998
N8N_CONTAINER = "n8n-n8n-1"
HOST_BASE = "/data/n8n-production"
CONTAINER_BASE = "/tmp/production"
N8N_WEBHOOK_BASE = os.environ.get("N8N_WEBHOOK_BASE", "https://n8n.srv1297445.hstgr.cloud/webhook")
DASHBOARD_API_TOKEN = os.environ.get("DASHBOARD_API_TOKEN", "")

# Caption style matching the original workflow
CAPTION_STYLE = (
    "FontName=Arial,FontSize=26,Bold=1,"
    "PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
    "BackColour=&H80000000,Outline=3,Shadow=2,"
    "MarginV=35,Alignment=2"
)


def burn_captions(topic_id, srt_filename, video_filename, drive_folder_id):
    """Run caption burn via docker exec, then trigger Drive re-upload."""
    container_video = f"{CONTAINER_BASE}/{topic_id}/final/{video_filename}"
    container_srt = f"{CONTAINER_BASE}/{topic_id}/captions/{srt_filename}"
    base_name = os.path.splitext(video_filename)[0]
    container_output = f"{CONTAINER_BASE}/{topic_id}/final/{base_name}_captioned.mp4"
    host_output = f"{HOST_BASE}/{topic_id}/final/{base_name}_captioned.mp4"

    log(f"[BURN] Starting caption burn for topic {topic_id}")
    log(f"  Video: {container_video}")
    log(f"  SRT:   {container_srt}")
    log(f"  Out:   {container_output}")

    # Build FFmpeg command
    ffmpeg_cmd = (
        f'ffmpeg -y -i "{container_video}" '
        f"-vf \"subtitles='{container_srt}':force_style='{CAPTION_STYLE}'\" "
        f'-af "loudnorm=I=-16:TP=-1.5:LRA=11" '
        f'-c:v libx264 -preset medium -crf 18 '
        f'-c:a aac -ar 48000 -ac 1 -b:a 128k '
        f'-movflags +faststart '
        f'"{container_output}"'
    )

    # Run via docker exec (outside n8n task runner)
    cmd = ["docker", "exec", N8N_CONTAINER, "sh", "-c", ffmpeg_cmd]
    log(f"[BURN] Running FFmpeg via docker exec...")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10800  # 3 hours max for 2.5hr+ videos with subtitle overlay
        )
        if result.returncode != 0:
            log(f"[BURN] FFmpeg FAILED: {result.stderr[-500:]}")
            return {"success": False, "error": f"FFmpeg exit code {result.returncode}", "stderr": result.stderr[-500:]}

        # Verify output exists
        if not os.path.exists(host_output):
            return {"success": False, "error": f"Output file not found at {host_output}"}

        size_mb = os.path.getsize(host_output) / (1024 * 1024)
        log(f"[BURN] Caption burn complete: {size_mb:.1f} MB")

        # Replace original with captioned version
        host_original = f"{HOST_BASE}/{topic_id}/final/{video_filename}"
        backup_path = f"{HOST_BASE}/{topic_id}/final/{base_name}_no_captions.mp4"
        os.replace(host_original, backup_path)
        os.replace(host_output, host_original)
        log(f"[BURN] Swapped: original → _no_captions.mp4, captioned → original name")

        # Trigger Drive re-upload via WF_DRIVE_UPLOAD webhook
        if drive_folder_id:
            upload_url = f"{N8N_WEBHOOK_BASE}/drive-upload"
            file_url = f"http://172.18.0.1:9999/{topic_id}/final/{quote(video_filename)}"
            payload = json.dumps({
                "topic_id": topic_id,
                "file_url": file_url,
                "file_name": video_filename,
                "folder_id": drive_folder_id,
                "mime_type": "video/mp4"
            }).encode()

            log(f"[BURN] Triggering Drive re-upload: {upload_url}")
            req = Request(upload_url, data=payload, headers={"Content-Type": "application/json"})
            try:
                resp = urlopen(req, timeout=120)
                upload_result = resp.read().decode()
                log(f"[BURN] Drive upload triggered: {upload_result[:200]}")
                return {"success": True, "size_mb": round(size_mb, 1), "upload_triggered": True}
            except Exception as e:
                log(f"[BURN] Drive upload trigger failed: {e}")
                return {"success": True, "size_mb": round(size_mb, 1), "upload_triggered": False, "upload_error": str(e)}
        else:
            log(f"[BURN] No drive_folder_id — skipping upload")
            return {"success": True, "size_mb": round(size_mb, 1), "upload_triggered": False}

    except subprocess.TimeoutExpired:
        log("[BURN] FFmpeg timed out after 60 minutes")
        return {"success": False, "error": "FFmpeg timed out after 60 minutes"}
    except Exception as e:
        log(f"[BURN] EXCEPTION: {traceback.format_exc()}")
        return {"success": False, "error": str(e)}


class CaptionBurnHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "service": "caption-burn", "port": PORT}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == "/burn":
            content_length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_length)) if content_length > 0 else {}

            topic_id = body.get("topic_id")
            srt_filename = body.get("srt_filename")
            video_filename = body.get("video_filename")
            drive_folder_id = body.get("drive_folder_id")

            if not all([topic_id, srt_filename, video_filename]):
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Missing required fields: topic_id, srt_filename, video_filename"}).encode())
                return

            # Respond immediately, process in background
            self.send_response(202)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "accepted", "topic_id": topic_id}).encode())

            # Run burn in background thread
            thread = threading.Thread(
                target=burn_captions,
                args=(topic_id, srt_filename, video_filename, drive_folder_id),
                daemon=True
            )
            thread.start()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        log(f"[HTTP] {args[0]}")


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), CaptionBurnHandler)
    log(f"Caption Burn Service running on port {PORT}")
    log(f"  POST /burn  — Burn captions + re-upload to Drive")
    log(f"  GET  /health — Health check")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("\nShutting down...")
        server.server_close()
