#!/bin/bash
# =============================================================================
# Burn Kinetic Captions onto assembled video
#
# Pipeline:
#   1. Whisper forced alignment → word_timings.json (perfect sync)
#   2. Generate kinetic ASS subtitles from word timings
#   3. FFmpeg burns ASS onto video + loudnorm audio normalize
#
# Usage:
#   bash burn_captions.sh <topic_id> <supabase_url> <supabase_key> <supabase_srk>
#
# Prerequisites:
#   - Python 3 with whisper installed (pip install openai-whisper)
#   - FFmpeg with libass enabled
#   - Inter font at /data/fonts/ (or /usr/share/fonts/custom/ in container)
#   - Assembled video at /data/n8n-production/<topic_id>/final/<title>.mp4
#   - Audio files at /data/n8n-production/<topic_id>/audio/scene_*.mp3
# =============================================================================

set -e

TOPIC_ID="$1"
SUPABASE_URL="${2:-https://supabase.operscale.cloud}"
SUPABASE_KEY="$3"
SUPABASE_SRK="$4"

if [ -z "$TOPIC_ID" ]; then
  echo "Usage: $0 <topic_id> [supabase_url] [supabase_key] [supabase_srk]"
  exit 1
fi

PROD_DIR="/data/n8n-production/${TOPIC_ID}"
AUDIO_DIR="${PROD_DIR}/audio"
CAPTIONS_DIR="${PROD_DIR}/captions"
FINAL_DIR="${PROD_DIR}/final"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find the final video
VIDEO_FILE=$(ls -1 "${FINAL_DIR}"/*.mp4 2>/dev/null | head -1)
if [ -z "$VIDEO_FILE" ]; then
  echo "ERROR: No video found in ${FINAL_DIR}"
  exit 1
fi
VIDEO_NAME=$(basename "$VIDEO_FILE" .mp4)
echo "Video: ${VIDEO_FILE}"

mkdir -p "${CAPTIONS_DIR}"

# ─── Step 1: Whisper Forced Alignment ─────────────────────────────────
TIMINGS_FILE="${PROD_DIR}/word_timings.json"

if [ -f "$TIMINGS_FILE" ] && [ -s "$TIMINGS_FILE" ]; then
  echo "[1/3] Word timings already exist, skipping Whisper..."
else
  echo "[1/3] Running Whisper forced alignment on ${AUDIO_DIR}..."
  WHISPER_PYTHON="${WHISPER_PYTHON:-/opt/whisper-env/bin/python3}"
  ${WHISPER_PYTHON} "${SCRIPT_DIR}/whisper_align.py" "${AUDIO_DIR}" "${TIMINGS_FILE}" base
  echo "  Word timings: $(python3 -c "import json; d=json.load(open('${TIMINGS_FILE}')); print(sum(len(s['words']) for s in d.values()), 'words in', len(d), 'scenes')")"
fi

# ─── Step 2: Fetch scenes data from Supabase ─────────────────────────
SCENES_FILE="${PROD_DIR}/scenes.json"

if [ -n "$SUPABASE_KEY" ]; then
  echo "[2a/3] Fetching scene timestamps from Supabase..."
  curl -s "${SUPABASE_URL}/rest/v1/scenes?topic_id=eq.${TOPIC_ID}&select=scene_number,start_time_ms,end_time_ms,narration_text&order=scene_number.asc" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SRK}" \
    -o "${SCENES_FILE}"
  echo "  Scenes: $(python3 -c "import json; print(len(json.load(open('${SCENES_FILE}'))))" 2>/dev/null) loaded"
else
  echo "[2a/3] No Supabase keys provided, using existing scenes.json..."
fi

# ─── Step 2b: Generate Kinetic ASS ───────────────────────────────────
ASS_FILE="${CAPTIONS_DIR}/${VIDEO_NAME}.ass"

echo "[2b/3] Generating kinetic ASS captions..."
python3 "${SCRIPT_DIR}/generate_kinetic_ass.py" "${TIMINGS_FILE}" "${SCENES_FILE}" "${ASS_FILE}"

# ─── Step 3: Burn captions onto video ────────────────────────────────
OUTPUT_FILE="${FINAL_DIR}/${VIDEO_NAME}_captioned.mp4"

echo "[3/3] Burning captions + normalizing audio..."
echo "  Input: ${VIDEO_FILE}"
echo "  ASS:   ${ASS_FILE}"
echo "  Output: ${OUTPUT_FILE}"

FONT_DIR="/data/fonts"
[ -d "/usr/share/fonts/custom" ] && FONT_DIR="/usr/share/fonts/custom"

ffmpeg -y -i "${VIDEO_FILE}" \
  -vf "ass=${ASS_FILE}:fontsdir=${FONT_DIR}" \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
  -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
  -c:a aac -ar 48000 -ac 1 -b:a 128k \
  -r 30 -movflags +faststart \
  "${OUTPUT_FILE}" 2>&1 | tail -5

echo ""
echo "=== DONE ==="
echo "Captioned video: ${OUTPUT_FILE}"
echo "Size: $(du -h "${OUTPUT_FILE}" | cut -f1)"
ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${OUTPUT_FILE}" 2>/dev/null | \
  awk '{printf "Duration: %d:%02d:%02d\n", $1/3600, ($1%3600)/60, $1%60}'
