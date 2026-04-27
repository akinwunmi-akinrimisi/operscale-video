-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Production Register Seeds
-- Two registers: documentary (default) and avatar-led (Creative Pod only).
-- See pricing-and-packages.md and ADR 0013 for the cinema-lane positioning.
-- ═══════════════════════════════════════════════════

INSERT INTO production_registers (register_id, name, short_description, accent_color_hex, config) VALUES
('OPERSCALE_01_DOCUMENTARY',
 'Documentary',
 'Default cinematic style for Pilot, Standard, and most Creative Pod orders',
 '#B4532A',
 '{
    "image_anchors": "muted color with controlled warmth, subtle film grain, 35mm look, rule of thirds, generous negative space, shallow depth of field",
    "negative_additions": "no text overlays, no watermarks, no logos in image",
    "tts_voice": "en-NG-Standard-A",
    "tts_speaking_rate": 0.95,
    "music_bpm_min": 80,
    "music_bpm_max": 100,
    "music_mood_keywords": ["uplifting", "cinematic", "moderate energy"],
    "ken_burns_default_preset": "slow_push",
    "typical_scene_length_sec": 4,
    "transition_duration_ms": 400,
    "font_family": "Inter"
  }'::jsonb),
('OPERSCALE_02_AVATAR_LED',
 'Avatar-Led',
 'Creative Pod only — talking-head avatar via HeyGen',
 '#C9994A',
 '{
    "image_anchors": "studio-lit talking head, high-contrast subject, clean professional background",
    "negative_additions": "no scene cuts within shot, no environmental distractions",
    "tts_voice": "en-NG-Standard-A",
    "tts_speaking_rate": 1.00,
    "music_bpm_min": 90,
    "music_bpm_max": 110,
    "music_mood_keywords": ["energetic", "modern", "confident"],
    "ken_burns_default_preset": "static",
    "typical_scene_length_sec": 6,
    "transition_duration_ms": 250,
    "font_family": "Inter"
  }'::jsonb)
ON CONFLICT (register_id) DO NOTHING;
