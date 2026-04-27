-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Prompt Config Seeds
-- 5 niches × 4 prompt types = 20 placeholder rows.
-- Bodies are intentionally TODO so the schema is exercisable but the
-- copywriting work happens in a separate prompt-engineering pass.
--
-- Niches: real-estate, education, fashion-ecom, fintech, health
-- Prompt types: angle_generator, script_generator, gate_summary, niche_detector
-- ═══════════════════════════════════════════════════

DO $$
DECLARE
  niches TEXT[] := ARRAY['real-estate', 'education', 'fashion-ecom', 'fintech', 'health'];
  prompt_types TEXT[] := ARRAY['angle_generator', 'script_generator', 'gate_summary', 'niche_detector'];
  n TEXT;
  pt TEXT;
BEGIN
  FOREACH n IN ARRAY niches LOOP
    FOREACH pt IN ARRAY prompt_types LOOP
      INSERT INTO operscale.prompt_configs (niche, prompt_type, prompt_text, version, is_active)
      VALUES (
        n,
        pt,
        format(
          '-- TODO: write %s prompt for %s niche.%s' ||
          'Should reference niche-briefs/%s.md for tone and operational knowledge.%s' ||
          'See skills.md §niche-aware-prompting for the construction pattern.',
          pt, n, E'\n', n, E'\n'
        ),
        1,
        true
      )
      ON CONFLICT (niche, prompt_type, version) DO NOTHING;
    END LOOP;
  END LOOP;
END $$;
