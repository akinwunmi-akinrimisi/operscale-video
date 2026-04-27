#!/opt/whisper-env/bin/python3
"""
Whisper forced alignment — extracts word-level timestamps from TTS audio files.
Uses Whisper's word_timestamps feature for perfect sync with narration.

Usage:
  python3 whisper_align.py <audio_dir> <output_json>
  python3 whisper_align.py /data/n8n-production/<topic_id>/audio /data/n8n-production/<topic_id>/word_timings.json

Input:  Directory of scene_NNN.mp3 files (132 scenes)
Output: JSON file with word-level timestamps per scene
"""

import sys
import os
import json
import glob
import re
import whisper


def process_audio_dir(audio_dir, output_path, model_name="base"):
    """Process all scene audio files and extract word-level timestamps."""

    model = whisper.load_model(model_name)
    audio_files = sorted(glob.glob(os.path.join(audio_dir, "scene_*.mp3")))

    if not audio_files:
        print(f"No scene_*.mp3 files found in {audio_dir}")
        sys.exit(1)

    print(f"Processing {len(audio_files)} audio files with Whisper {model_name}...")
    results = {}

    for i, audio_path in enumerate(audio_files):
        filename = os.path.basename(audio_path)
        scene_num = int(re.search(r"scene_(\d+)", filename).group(1))

        result = model.transcribe(
            audio_path,
            word_timestamps=True,
            language="en",
            fp16=False,
        )

        words = []
        for segment in result.get("segments", []):
            for word_info in segment.get("words", []):
                words.append({
                    "word": word_info["word"].strip(),
                    "start_ms": int(word_info["start"] * 1000),
                    "end_ms": int(word_info["end"] * 1000),
                })

        results[scene_num] = {
            "file": filename,
            "text": result.get("text", "").strip(),
            "words": words,
        }

        if (i + 1) % 10 == 0 or i == 0:
            print(f"  [{i+1}/{len(audio_files)}] {filename}: {len(words)} words")

    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)

    total_words = sum(len(s["words"]) for s in results.values())
    print(f"Done. {len(results)} scenes, {total_words} words -> {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <audio_dir> <output_json> [model]")
        sys.exit(1)

    audio_dir = sys.argv[1]
    output_path = sys.argv[2]
    model_name = sys.argv[3] if len(sys.argv) > 3 else "base"

    process_audio_dir(audio_dir, output_path, model_name)
