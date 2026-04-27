#!/usr/bin/env python3
"""
Kinetic ASS Caption Generator — Hormozi/MrBeast style word-by-word captions.

Takes word-level timestamps (from Whisper) and scene data,
generates an ASS subtitle file with:
  - Word-by-word pop-in with scale bounce (100% → 115% → 100%)
  - 3-5 words visible at a time
  - Emphasis words: larger, yellow (#FFD700) or red (#FF4444)
  - Center-bottom positioning with strong drop shadow
  - Smooth fade transitions between word groups

Usage:
  python3 generate_kinetic_ass.py <word_timings.json> <scenes.json> <output.ass>
  python3 generate_kinetic_ass.py /data/n8n-production/<id>/word_timings.json /data/n8n-production/<id>/scenes.json /data/n8n-production/<id>/captions/kinetic.ass
"""

import sys
import json
import re

# ASS color format: &HAABBGGRR (alpha, blue, green, red) — note BGR not RGB
WHITE = "&H00FFFFFF"
YELLOW = "&H0000D7FF"    # #FFD700 in BGR
RED = "&H004444FF"       # #FF4444 in BGR
OUTLINE = "&H00000000"   # black
SHADOW = "&H96000000"    # 60% transparent black

MAX_WORDS_PER_GROUP = 4
FONT_NAME = "Inter"
FONT_SIZE_NORMAL = 68
FONT_SIZE_EMPHASIS = 88
OUTLINE_SIZE = 5
SHADOW_DEPTH = 4
MARGIN_BOTTOM = 140      # px from bottom

# Animation timing (ms)
POP_IN_DURATION = 120     # scale bounce up
POP_SETTLE_DURATION = 80  # scale settle back
FADE_IN = 80
FADE_OUT = 150
WORD_GAP_MS = 30          # small gap between word appearances


def ms_to_ass(ms):
    """Convert milliseconds to ASS timestamp format H:MM:SS.cc"""
    h = int(ms // 3600000)
    m = int((ms % 3600000) // 60000)
    s = int((ms % 60000) // 1000)
    cs = int((ms % 1000) // 10)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def is_emphasis_word(word, index, all_words):
    """Detect words that should be emphasized (larger, colored)."""
    clean = re.sub(r"[^a-zA-Z0-9$%]", "", word)
    if not clean:
        return False
    # Numbers and money
    if re.match(r"^\$?\d", clean):
        return True
    # ALL CAPS (3+ chars)
    if len(clean) >= 3 and clean == clean.upper() and re.search(r"[A-Z]", clean):
        return True
    # Word after negation
    if index > 0:
        prev = re.sub(r"[^a-zA-Z']", "", all_words[index - 1])
        if prev.lower() in ("not", "never", "no", "dont", "don't", "can't", "cant",
                            "won't", "wont", "isn't", "isnt", "aren't", "arent",
                            "couldn't", "couldnt", "shouldn't", "shouldnt", "without"):
            return True
    # Emotional/power words
    power_words = {
        "secret", "hidden", "exposed", "shocking", "billion", "million", "trillion",
        "illegal", "scam", "fraud", "truth", "lie", "lies", "corrupt", "broken",
        "massive", "enormous", "incredible", "impossible", "dangerous", "deadly",
        "critical", "urgent", "emergency", "crisis", "collapse", "destroy",
        "exactly", "precisely", "specifically", "literally", "absolutely",
        "everything", "nothing", "everyone", "nobody", "always", "never",
        "free", "zero", "double", "triple", "guaranteed", "proven", "exposed",
    }
    if clean.lower() in power_words:
        return True
    return False


def group_words(words, max_per_group=MAX_WORDS_PER_GROUP):
    """Group words into display chunks of 3-5 words."""
    groups = []
    current = []

    for i, w in enumerate(words):
        # Start new group conditions
        start_new = False
        if len(current) >= max_per_group:
            start_new = True
        elif w.get("emphasis") and len(current) > 0:
            start_new = True
        elif len(current) > 0 and re.search(r"[.!?]$", current[-1]["word"]):
            start_new = True
        elif len(current) > 1 and re.search(r"[,;:—]$", current[-1]["word"]):
            start_new = True

        if start_new and current:
            groups.append(current)
            current = []

        current.append(w)

    if current:
        groups.append(current)

    return groups


def generate_ass(word_timings, scenes_data):
    """Generate ASS subtitle content with kinetic typography."""

    header = f"""[Script Info]
Title: Kinetic Captions - VisionGridAI
ScriptType: v4.00+
WrapStyle: 0
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,{FONT_NAME},{FONT_SIZE_NORMAL},{WHITE},&H000000FF,{OUTLINE},{SHADOW},-1,0,0,0,100,100,2,0,1,{OUTLINE_SIZE},{SHADOW_DEPTH},2,80,80,{MARGIN_BOTTOM},1
Style: Emphasis,{FONT_NAME},{FONT_SIZE_EMPHASIS},{YELLOW},&H000000FF,{OUTLINE},{SHADOW},-1,0,0,0,100,100,2,0,1,{OUTLINE_SIZE + 1},{SHADOW_DEPTH},2,80,80,{MARGIN_BOTTOM},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    dialogue_lines = []

    # Process each scene
    for scene_num_str, scene_data in sorted(word_timings.items(), key=lambda x: int(x[0])):
        scene_num = int(scene_num_str)
        words = scene_data.get("words", [])
        if not words:
            continue

        # Find scene offset from scenes_data
        scene_info = None
        for s in scenes_data:
            if s.get("scene_number") == scene_num:
                scene_info = s
                break

        scene_offset_ms = scene_info.get("start_time_ms", 0) if scene_info else 0

        # Mark emphasis words
        # Priority: scene's caption_highlight_word > auto-detection
        highlight_word = scene_info.get("caption_highlight_word", "").strip().lower() if scene_info else ""
        all_word_texts = [w["word"] for w in words]
        for i, w in enumerate(words):
            clean_word = re.sub(r"[^a-zA-Z0-9$%]", "", w["word"]).lower()
            if highlight_word and clean_word == highlight_word:
                w["emphasis"] = True
            else:
                w["emphasis"] = is_emphasis_word(w["word"], i, all_word_texts)
            # Adjust timestamps to global video time
            w["global_start_ms"] = scene_offset_ms + w["start_ms"]
            w["global_end_ms"] = scene_offset_ms + w["end_ms"]

        # Group words
        groups = group_words(words)

        for group in groups:
            if not group:
                continue

            # Group timing: from first word start to last word end + small buffer
            group_start_ms = group[0]["global_start_ms"]
            group_end_ms = group[-1]["global_end_ms"] + FADE_OUT

            start_ts = ms_to_ass(group_start_ms)
            end_ts = ms_to_ass(group_end_ms)

            # Build text with per-word animation overrides
            text_parts = []
            for w in group:
                word_delay = w["global_start_ms"] - group_start_ms
                clean_word = w["word"].replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}")

                if w["emphasis"]:
                    # Emphasis: yellow, larger, stronger bounce
                    text_parts.append(
                        f"{{\\c{YELLOW}\\fscx130\\fscy130"
                        f"\\t({word_delay},{word_delay + POP_IN_DURATION},\\fscx145\\fscy145)"
                        f"\\t({word_delay + POP_IN_DURATION},{word_delay + POP_IN_DURATION + POP_SETTLE_DURATION},\\fscx130\\fscy130)"
                        f"}}{clean_word} "
                    )
                else:
                    # Normal: white, scale bounce entrance
                    text_parts.append(
                        f"{{\\c{WHITE}\\fscx100\\fscy100"
                        f"\\t({word_delay},{word_delay + POP_IN_DURATION},\\fscx115\\fscy115)"
                        f"\\t({word_delay + POP_IN_DURATION},{word_delay + POP_IN_DURATION + POP_SETTLE_DURATION},\\fscx100\\fscy100)"
                        f"}}{clean_word} "
                    )

            text = "".join(text_parts).rstrip()
            # Add fade in/out to the whole group
            line = f"Dialogue: 0,{start_ts},{end_ts},Default,,0,0,0,,{{\\fad({FADE_IN},{FADE_OUT})}}{text}"
            dialogue_lines.append(line)

    return header + "\n".join(dialogue_lines) + "\n"


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <word_timings.json> <scenes.json> <output.ass>")
        sys.exit(1)

    word_timings_path = sys.argv[1]
    scenes_path = sys.argv[2]
    output_path = sys.argv[3]

    with open(word_timings_path) as f:
        word_timings = json.load(f)

    with open(scenes_path) as f:
        scenes_data = json.load(f)

    ass_content = generate_ass(word_timings, scenes_data)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(ass_content)

    total_groups = ass_content.count("Dialogue:")
    print(f"Generated {total_groups} caption groups -> {output_path}")


if __name__ == "__main__":
    main()
