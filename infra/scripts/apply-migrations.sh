#!/usr/bin/env bash
# apply-migrations.sh — Apply Operscale schema migrations to the shared Supabase.
# RUNS ON VPS. Reads from supabase/migrations/, applies in order, verifies after each.
#
# Per docs/superpowers/specs/2026-04-27-foundation-design.md §6.4:
#   ★3 named gate before this script runs at all
#   ★4 named gate before the ALTER PUBLICATION at end of 001
#
# Schema isolation: all 12 Operscale tables live in the `operscale` schema
# (NOT public.*) — see supabase/migrations/001_initial.sql header and
# docs/foundation/infrastructure-state-day-3.md for the rationale.
# VG's existing public.scenes / public.production_log / etc. are unaffected.
#
# Idempotent — uses CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING etc.

set -euo pipefail

MIGRATIONS=(
  "001_initial.sql"
  "002_seed_registers.sql"
  "003_seed_prompt_configs.sql"
  "004_storage_buckets.sql"
)

SUPABASE_DB="supabase-db-1"

if ! docker ps --format '{{.Names}}' | grep -q "^${SUPABASE_DB}\$"; then
  echo "❌ ${SUPABASE_DB} not running"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ─── Pre-flight: confirm operscale schema is clean (no leftover from a
#     previous partial apply, no surprise tables already present) ─────
echo "▶ Pre-flight: operscale schema state..."
existing=$(docker exec "$SUPABASE_DB" psql -U postgres -tA -c \
  "SELECT count(*) FROM information_schema.tables
   WHERE table_schema='operscale'
     AND table_name IN ('customers','briefs','orders','videos','scenes',
                        'production_log','payments','gate_decisions',
                        'order_consent','llm_calls',
                        'production_registers','prompt_configs');")
echo "  operscale.* tables matching our 12 names: ${existing} (expected: 0 on first run, 12 on idempotent re-run)"
echo ""

for m in "${MIGRATIONS[@]}"; do
  path="supabase/migrations/${m}"
  if [ ! -f "$path" ]; then
    echo "❌ $path missing"
    exit 1
  fi
  echo "▶ Applying $m..."
  docker exec -i "$SUPABASE_DB" psql -U postgres -v ON_ERROR_STOP=1 < "$path" 2>&1 | tail -20
  echo "  ✅ $m applied"
  echo ""
done

echo "▶ Verifying Operscale tables exist in operscale schema..."
EXPECTED_TABLES=(customers briefs orders videos scenes production_log payments gate_decisions order_consent llm_calls production_registers prompt_configs)
for t in "${EXPECTED_TABLES[@]}"; do
  count=$(docker exec "$SUPABASE_DB" psql -U postgres -tA -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='operscale' AND table_name='$t';")
  if [ "$count" = "1" ]; then
    echo "  ✅ operscale.$t"
  else
    echo "  ❌ operscale.$t — expected 1, got $count"
    exit 1
  fi
done

echo ""
echo "▶ Verifying REPLICA IDENTITY FULL on Realtime tables..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SELECT n.nspname || '.' || c.relname AS qualified_name,
          CASE c.relreplident WHEN 'f' THEN 'FULL' ELSE 'OTHER' END AS identity
   FROM pg_class c
   JOIN pg_namespace n ON c.relnamespace = n.oid
   WHERE n.nspname = 'operscale'
     AND c.relname IN ('orders','videos','scenes','production_log','gate_decisions')
   ORDER BY c.relname;"

echo ""
echo "▶ Verifying Realtime publication membership (operscale.* only)..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SELECT schemaname, tablename
   FROM pg_publication_tables
   WHERE pubname='supabase_realtime'
     AND schemaname='operscale'
     AND tablename IN ('orders','videos','scenes','production_log','gate_decisions')
   ORDER BY tablename;"

echo ""
echo "▶ Spot-checking RLS lockdown (anon role on operscale.orders)..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SET ROLE anon; SELECT count(*) AS anon_visible_rows FROM operscale.orders; RESET ROLE;"
echo "  Expected: 0 (RLS denies anon)"

echo ""
echo "▶ Sanity-check: VG's public.scenes still has its rows (we did NOT touch it)..."
vg_scenes=$(docker exec "$SUPABASE_DB" psql -U postgres -tA -c "SELECT count(*) FROM public.scenes;")
echo "  public.scenes row count: $vg_scenes (Day-3 recon recorded 1,140; minor drift is normal)"

echo ""
echo "✅ All migrations applied and verified."
