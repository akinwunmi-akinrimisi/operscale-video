-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — operscale schema role grants
--
-- Discovered during Day-6 prep: PostgreSQL requires explicit GRANT USAGE
-- on non-public schemas. Without it, even the omnipotent `service_role`
-- hits PG error 42501 ("permission denied for schema operscale") at the
-- catalog-traversal layer, BEFORE RLS is ever consulted.
--
-- Supabase's `public` schema has these grants pre-configured by the
-- platform's bootstrap. A custom schema like `operscale` must add them
-- explicitly.
--
-- Grant matrix (Foundation phase):
--   service_role  → full access (for agent + test scripts + admin ops)
--   authenticated → no access (no end-user UI in Foundation; revisit Customer-flow)
--   anon          → deliberately denied (RLS + no-grant = defense in depth)
--
-- All statements are idempotent: re-running this migration is a no-op on
-- already-granted privileges.
--
-- The design-spec (line 30) originally reserved 005_creative_pod_columns.sql
-- for Creative-Pod schema additions. That reservation is renumbered to
-- 006_creative_pod_columns.sql for that future migration to avoid clobbering
-- this critical-path role grant.
-- ═══════════════════════════════════════════════════

GRANT USAGE ON SCHEMA operscale TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA operscale TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA operscale TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA operscale TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA operscale GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA operscale GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA operscale GRANT ALL ON FUNCTIONS TO service_role;
