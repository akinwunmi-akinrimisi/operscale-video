-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Storage Buckets
-- Creates 4 buckets for customer-uploaded assets and final deliverables.
-- RLS-locked: anon role denied; service_role full access.
-- See docs/superpowers/specs/2026-04-27-foundation-design.md §4.2.
-- ═══════════════════════════════════════════════════

-- ─── Bucket creation ────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('order-deliverables', 'order-deliverables', false, 524288000,
    ARRAY['video/mp4','image/jpeg','image/png']),
  ('customer-photos', 'customer-photos', false, 20971520,
    ARRAY['image/jpeg','image/png','image/webp']),
  ('customer-voice-samples', 'customer-voice-samples', false, 52428800,
    ARRAY['audio/mpeg','audio/wav','audio/x-wav']),
  ('customer-logos', 'customer-logos', false, 5242880,
    ARRAY['image/png','image/svg+xml','image/jpeg'])
ON CONFLICT (id) DO NOTHING;

-- ─── RLS policies ────────────────────────────────────
-- anon: deny all
CREATE POLICY "operscale_anon_deny_select" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id NOT IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));

CREATE POLICY "operscale_anon_deny_insert" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id NOT IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));

-- service_role: full access on operscale buckets
CREATE POLICY "operscale_service_role_all" ON storage.objects
  FOR ALL TO service_role
  USING (bucket_id IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'))
  WITH CHECK (bucket_id IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));
