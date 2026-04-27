# Deployment Quickstart (VPS-side)

> The local Windows scaffold creates the repository structure, ADRs, migrations, and
> per-skill assets. The actual platform runs on the **shared Hostinger KVM VPS** alongside
> Vision GridAI. This file is the bootstrap procedure on the VPS.
>
> **Read alongside:** `deployment.md` (full topology), `VISION_GRIDAI_FORK_MANUAL.md` §15,
> `implementation.md` (the 35-day day-by-day plan).

---

## Prerequisites on the VPS

- Vision GridAI's stack is already running and healthy
  (`docker ps | grep -E 'n8n|supabase|caption-burn'`)
- SSH access as root: `ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud`
- DNS for `plovera.shop` and `www.plovera.shop` pointed at the VPS IP (Hostinger DNS)
- Traefik on the VPS already terminates TLS and is running
- A working `git` and `bash` on the host

---

## Bootstrap (one-time)

```bash
ssh root@srv1297445.hstgr.cloud

# 1. Clone the repo
cd /docker
git clone https://github.com/akinwunmi-akinrimisi/operscale-video.git operscale-video-ads
cd operscale-video-ads

# 2. Drop in the real .env files (NOT in git — chmod 600)
#    Use the templates from skills.sh as starting point.
#    Required keys: ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
#    SUPABASE_ANON_KEY, DASHBOARD_API_TOKEN (reuse VG's), FAL_KEY, HEYGEN_API_KEY,
#    PAYSTACK_SECRET_KEY, RESEND_API_KEY, EVOLUTION_API_KEY, NOTION_API_KEY,
#    BRAND_NAME=plovera, BRAND_DOMAIN=plovera.shop
nano .env.agent       # chmod 600
nano .env.web         # chmod 600

# 3. Run the installer (idempotent)
bash skills.sh

# 4. Apply DB migrations to the SHARED Supabase
docker exec -i supabase-db-1 psql -U postgres < supabase/migrations/001_initial.sql
docker exec -i supabase-db-1 psql -U postgres < supabase/migrations/002_seed_registers.sql
docker exec -i supabase-db-1 psql -U postgres < supabase/migrations/003_seed_prompt_configs.sql

# 5. Verify Operscale tables coexist with VG's
docker exec -i supabase-db-1 psql -U postgres -c \
  "SELECT count(*) FROM information_schema.tables WHERE table_name IN ('orders','videos','scenes','briefs','customers','payments','gate_decisions','order_consent','llm_calls','production_log','production_registers','prompt_configs');"
# expect: 12

# 6. Verify Realtime publication includes our tables
docker exec -i supabase-db-1 psql -U postgres -c \
  "SELECT tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY tablename;"

# 7. Verify REPLICA IDENTITY FULL is set
docker exec -i supabase-db-1 psql -U postgres -c \
  "SELECT relname, CASE relreplident WHEN 'f' THEN 'FULL' ELSE 'other' END FROM pg_class WHERE relname IN ('orders','videos','scenes','production_log','gate_decisions');"
# expect: all 'FULL'

# 8. Build + run the operscale containers
cd /docker/operscale-video-ads
docker compose build
docker compose up -d

# 9. Verify Traefik routes plovera.shop to operscale-web
curl -I https://plovera.shop
# expect: 200 (or 404 if no landing page yet, which is fine pre-Day-15)

# 10. Day 1+ continues per implementation.md
```

---

## What runs where after deploy

| Component | Container / Process | Port |
|-----------|---------------------|------|
| Marketing site (Next.js 15) | `operscale-web` | 3000 (internal) |
| LangGraph agent | `operscale-agent` | n/a (worker) |
| Postgres | `supabase-db-1` (shared) | 5432 (internal) |
| Supabase Kong | `supabase-kong-1` (shared) | 8000 (internal) |
| n8n | `n8n-n8n-1` (shared) | 5678 (internal) |
| Caption burn service | systemd `caption-burn.service` (host) | 9998 |
| Traefik | shared | 80, 443 |

External-facing entry points (via Traefik TLS):
- `https://plovera.shop` → marketing site
- `https://supabase.operscale.cloud` → Supabase API (shared, do not expose new auth surface)
- `https://n8n.srv1297445.hstgr.cloud` → n8n UI (founder-only)

---

## Day-1 Prune Commit (before any feature work)

The Day-1 Prune Commit removes ~60% of Vision GridAI's surface area in **one commit**.
Do **not** trickle-delete. See `VISION_GRIDAI_FORK_MANUAL.md` §3.1 for the exact rm
list, and the `prune-commit` skill in `skills.md` for the discipline.

---

## When something is broken

Order of investigation:

1. `production_log` table — most operational events land here.
2. `orders.pipeline_stage` for the affected order — the resume point is here.
3. Per-scene status (`scenes.audio_status`, `image_status`, `clip_status`) — the
   render core is resume-aware.
4. n8n execution log for the workflow that owns the failing stage.
5. Caption burn service log: `journalctl -u caption-burn.service -f`.
6. The 12 inherited gotchas in `CLAUDE.md` — most "weird silent failure" symptoms map
   to one of them.

---

## Rotation procedures

Any JWT or shared-secret rotation follows the **5-sync-point** procedure documented in
the `jwt-chain-rotation` skill (`skills.md`). Skipping any one sync point produces a
different silent failure. Read `security.md` §JWT-chain before touching keys.
