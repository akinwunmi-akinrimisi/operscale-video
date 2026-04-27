# Deployment

> The runtime topology of Operscale Video Ads on the shared Hostinger VPS.

**Read alongside:** `docs/VISION_GRIDAI_FORK_MANUAL.md` §4 (VPS layout), §10 (auth + secrets), `architecture.md`, `security.md`.

---

## What deploys where

We run on a single shared Hostinger KVM VPS (currently KVM 4: 4 vCPU, 16 GB RAM, 200 GB NVMe). The VPS hosts both Vision GridAI and Operscale Video Ads. We do NOT operate in isolation — we share Postgres, n8n, the caption burn service, and the JWT chain. We have separate Docker containers for our new code.

### Server identity

| Item | Value |
|---|---|
| SSH endpoint | `root@srv1297445.hstgr.cloud` |
| Key file | `~/.ssh/id_ed25519_antigravity` |
| Login | `ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud` |
| OS | Ubuntu 22.04 LTS |

### Public hostnames

We add these to Hostinger DNS, all pointing at the same VPS IP as VG's hostnames:

| Hostname | Routes to | Status |
|---|---|---|
| `plovera.shop` | Marketing site (Next.js) | New |
| `app.plovera.shop` | Reserved for future founder console | Reserved |

VG's hostnames stay untouched: `n8n.srv1297445.hstgr.cloud`, `supabase.operscale.cloud`, `dashboard.operscale.cloud`. We use VG's `n8n.srv1297445.hstgr.cloud` for our `WF_OPS_*` webhook endpoints — same n8n instance, namespaced webhook paths.

---

## Filesystem layout

We coexist with VG. Their paths stay untouched; we add our own:

```
/docker/
├── n8n/                              # VG's n8n stack — DO NOT TOUCH
├── supabase/                         # Shared Supabase — JWT chain shared
└── operscale-video-ads/              # ← OURS, NEW
    ├── docker-compose.yml
    └── docker-compose.override.yml   # chmod 600, NOT in git

/data/
├── n8n-production/                   # VG scratch — DO NOT TOUCH
└── operscale-production/             # ← OURS, NEW
    └── <order_id>/
        ├── audio/
        ├── images/
        ├── video_clips/
        ├── captions/
        └── final/

/opt/
├── dashboard/                        # VG's React dashboard
├── caption-burn/                     # SHARED — reads from both /data dirs
└── operscale/                        # ← OURS, NEW (static assets only)

/root/
├── keys_new.env                      # VG's live keys (DO NOT TOUCH, chmod 600)
├── operscale_keys.env                # ← OURS, NEW (chmod 600)
└── backups/
    ├── jwt-fix-YYYYMMDDTHHMMSSZ/     # VG rotation backups
    └── operscale-deploy-YYYYMMDDTHHMMSSZ/  # ← OURS
```

---

## Docker containers we run

Two new containers on top of VG's existing stack:

### `operscale-web` — Next.js marketing site

```yaml
# /docker/operscale-video-ads/docker-compose.yml (excerpt)
services:
  web:
    image: ghcr.io/operscale/operscale-video-ads-web:latest
    container_name: operscale-web
    restart: unless-stopped
    networks:
      - traefik
      - operscale
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.operscale-web.rule=Host(`plovera.shop`)"
      - "traefik.http.routers.operscale-web.tls=true"
      - "traefik.http.routers.operscale-web.tls.certresolver=letsencrypt"
    environment:
      - NODE_ENV=production
      - SUPABASE_URL=https://supabase.operscale.cloud
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
      - PAYSTACK_PUBLIC_KEY=${PAYSTACK_PUBLIC_KEY}
      - N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook/operscale
      - DASHBOARD_API_TOKEN=${DASHBOARD_API_TOKEN}
```

### `operscale-agent` — LangGraph Python agent

```yaml
  agent:
    image: ghcr.io/operscale/operscale-video-ads-agent:latest
    container_name: operscale-agent
    restart: unless-stopped
    networks:
      - traefik
      - operscale
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - SUPABASE_URL=https://supabase.operscale.cloud
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
      - N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook/operscale
      - DASHBOARD_API_TOKEN=${DASHBOARD_API_TOKEN}
      - PAYSTACK_SECRET_KEY=${PAYSTACK_SECRET_KEY}
      - HEYGEN_API_KEY=${HEYGEN_API_KEY}    # Phase 3+
      - FAL_KEY=${FAL_KEY}                  # for PlayHT v3 voice cloning
      - NOTION_API_KEY=${NOTION_API_KEY}
      - NOTION_GATE_DB_ID=${NOTION_GATE_DB_ID}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  traefik:
    external: true                      # Pre-existing, set up by VG
  operscale:
    driver: bridge
```

The `traefik` network is already created on the VPS (set up during VG's deployment). We connect to it without re-creating it.

### Bring up

```bash
cd /docker/operscale-video-ads
docker compose up -d
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep operscale
```

---

## n8n bind mount addition

We also need to update VG's n8n stack to mount our scratch directory inside the n8n container, so the inherited workflows can write files there.

**Edit `/docker/n8n/docker-compose.override.yml`** (this is VG's file, but adding a volume mount is non-destructive):

```yaml
services:
  n8n:
    volumes:
      - /data/n8n-production:/tmp/production    # VG's existing mount
      - /data/operscale-production:/tmp/operscale-production   # ← ADD THIS LINE
```

Then:

```bash
cd /docker/n8n && docker compose up -d
```

This restarts only the n8n container with the new mount. VG's data is untouched.

Verify:
```bash
docker exec n8n-n8n-1 ls /tmp/operscale-production
# Should return without error (empty dir is fine)
```

---

## Caption burn service — shared

The host-side caption burn service at `/opt/caption-burn/caption_burn_service.py` (port 9998) is shared between VG and Operscale. We do NOT spin up a second copy.

Per fork manual §8.3, the service has hardcoded paths `HOST_BASE = "/data/n8n-production"` and `CONTAINER_BASE = "/tmp/production"`. We need to make these env-var-configurable so the same service can serve both products.

### One-time edit to the service

```python
# /opt/caption-burn/caption_burn_service.py
# Change two lines:
HOST_BASE = os.environ.get("CB_HOST_BASE", "/data/n8n-production")
CONTAINER_BASE = os.environ.get("CB_CONTAINER_BASE", "/tmp/production")
```

Then for Operscale calls, the request payload from `WF_OPS_CAPTIONS_ASSEMBLY` includes the topic_id formatted as `operscale-<order_id>-v<video_number>`, and the service constructs paths:

```
host_video_path      = $HOST_BASE/operscale-<order_id>-v<vid>/final/<filename>.mp4
container_video_path = $CONTAINER_BASE/operscale-<order_id>-v<vid>/final/<filename>.mp4
```

Combined with the `/tmp/operscale-production` mount above, this works.

**Alternative (simpler):** symlink approach.

```bash
ln -sf /data/operscale-production /data/n8n-production/operscale-renders
```

Then Operscale "topic_ids" become `operscale-renders/<order_id>-v<vid>` within VG's tree. No changes to the caption burn service needed.

**Pick one and document it in your decision log.** The symlink is simpler; the env var is more correct.

### Restart the service after edit

```bash
systemctl restart caption-burn.service
journalctl -u caption-burn.service -n 50
```

Health check:
```bash
curl http://172.18.0.1:9998/health
# {"status":"ok","service":"caption-burn","port":9998}
```

---

## JWT chain — inherited from VG

This is the most operationally sensitive part of deployment. Per fork manual §10, the Supabase JWT secret has 4 sync points. Operscale adds a 5th.

When a JWT rotation happens, ALL FIVE locations must be updated:

| # | Location | What it holds | Action after rotation |
|---|---|---|---|
| 1 | `/docker/supabase/.env` | `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY` | Replace, restart Supabase stack |
| 2 | `/docker/n8n/docker-compose.override.yml` | `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` env vars | Replace, restart n8n |
| 3 | `_realtime.tenants.jwt_secret` (DB rows × 2) | Per-tenant secret | `UPDATE _realtime.tenants SET jwt_secret = '<NEW>' WHERE name IN ('realtime', 'realtime-dev')` |
| 4 | `/docker/supabase/supabase/kong.yml` | Kong consumer credentials | Replace + `docker exec supabase-kong-1 kong reload` |
| 5 | **`/docker/operscale-video-ads/docker-compose.override.yml`** | `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` env vars for our containers | Replace + `cd /docker/operscale-video-ads && docker compose up -d` |
| 6 | VG's dashboard `/opt/dashboard/.env` (if rebuilt) | `VITE_SUPABASE_ANON_KEY` | Replace + rebuild + redeploy |

Skipping any one produces a different silent failure mode. See `security.md` for the full rotation procedure.

---

## Environment variables — full list

### Container `operscale-web`

```
NODE_ENV=production
SUPABASE_URL=https://supabase.operscale.cloud
SUPABASE_ANON_KEY=eyJ…  (from /docker/supabase/.env)
PAYSTACK_PUBLIC_KEY=pk_live_…
N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook/operscale
DASHBOARD_API_TOKEN=…  (same value as VG's, see fork manual §10.2)
NEXT_PUBLIC_BRAND_NAME=plovera
NEXT_PUBLIC_BRAND_DOMAIN=plovera.shop
```

### Container `operscale-agent`

```
ANTHROPIC_API_KEY=sk-ant-…
SUPABASE_URL=https://supabase.operscale.cloud
SUPABASE_SERVICE_ROLE_KEY=eyJ…
N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook/operscale
DASHBOARD_API_TOKEN=…
PAYSTACK_SECRET_KEY=sk_live_…
HEYGEN_API_KEY=…           # Phase 3+ only
FAL_KEY=…                  # for PlayHT v3 voice cloning
NOTION_API_KEY=secret_…
NOTION_GATE_DB_ID=…
GCP_TTS_CREDENTIALS_JSON=…  # service account JSON, base64-encoded
```

### Inherited (VG's existing env, used by our workflows)

```
# In /docker/n8n/docker-compose.override.yml — already set by VG, do not duplicate:
DASHBOARD_API_TOKEN=…       # shared with us
NODE_FUNCTION_ALLOW_BUILTIN=child_process  # required for TTS + assembly Code nodes
N8N_ENCRYPTION_KEY=…        # encrypts ~/.n8n/database.sqlite
```

---

## Secrets management

### File locations

```
/root/operscale_keys.env           # chmod 600, root-only, source of truth for our keys
/docker/operscale-video-ads/docker-compose.override.yml  # references via ${VAR} syntax
```

Both files are NOT in git. Add to `.gitignore`:

```
docker-compose.override.yml
*.env
!*.env.example
```

### Reading a secret

```bash
grep ANTHROPIC_API_KEY /root/operscale_keys.env
```

### Adding a new secret

1. Add to `/root/operscale_keys.env`
2. Reference in `/docker/operscale-video-ads/docker-compose.override.yml` as `${VAR_NAME}`
3. `cd /docker/operscale-video-ads && docker compose up -d`

### Rotating a secret

1. Update `/root/operscale_keys.env`
2. Backup current state: `mkdir -p /root/backups/operscale-deploy-$(date -u +%Y%m%dT%H%M%SZ) && cp /docker/operscale-video-ads/docker-compose.override.yml $_/`
3. Update referencing tooling (e.g., if it's an Anthropic key, rotate in n8n credentials too)
4. `cd /docker/operscale-video-ads && docker compose up -d`
5. Verify: `docker logs operscale-agent --tail 20`

For Supabase JWT rotation specifically, see the 5-point sync above.

---

## Disk capacity planning

Per VG's session 35 cleanup notes, the VPS was at 39% used (~78 GB) before our additions. Our footprint:

| Item | Size estimate |
|---|---|
| `operscale-web` Docker image | ~250 MB |
| `operscale-agent` Docker image | ~600 MB |
| `/data/operscale-production/` per order | ~150-300 MB during render, deleted after delivery |
| Postgres growth | ~2-5 MB per order (briefs, scenes, llm_calls) |
| Backblaze B2 backup outbound bandwidth | nightly backups of new data |

**Cleanup script** (run nightly via cron):

```bash
#!/bin/bash
# /usr/local/bin/operscale-cleanup.sh
# Delete /data/operscale-production/<order_id> for orders delivered > 7 days ago

DELIVERED_ORDERS=$(docker exec supabase-db-1 psql -U postgres -t -c \
  "SELECT id FROM orders WHERE delivery_email_sent_at < NOW() - INTERVAL '7 days' AND pipeline_stage = 'delivered'")

for order_id in $DELIVERED_ORDERS; do
  rm -rf "/data/operscale-production/$order_id"
done
```

**Disk monitoring trigger:** when VPS sustained ≥ 70% disk for 7 days, plan KVM 8 upgrade (per `architecture.md`).

---

## Health checks

A quick "is everything alive" command:

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'n8n|supabase|operscale'
systemctl status caption-burn
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $DASHBOARD_API_TOKEN" \
  -X POST https://n8n.srv1297445.hstgr.cloud/webhook/operscale/status
curl -s -o /dev/null -w "%{http_code}\n" \
  https://plovera.shop/api/healthz
```

Expected outputs:
- All containers `Up X hours/days`
- caption-burn `active (running)`
- `200` from both webhooks

---

## Deployment workflow

### Web (Next.js)

```bash
# Build locally:
cd apps/web
npm ci
npm run build

# Build Docker image:
docker build -t ghcr.io/operscale/operscale-video-ads-web:$(git rev-parse --short HEAD) .
docker tag ghcr.io/operscale/operscale-video-ads-web:$(git rev-parse --short HEAD) ghcr.io/operscale/operscale-video-ads-web:latest
docker push ghcr.io/operscale/operscale-video-ads-web:latest

# Deploy on VPS:
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
docker compose pull web
docker compose up -d web
```

### Agent (Python)

Same pattern as web, with `apps/agent/` as the source dir.

### Workflows (n8n)

n8n workflows live in two places: the JSON files in our repo (source of truth) and the running n8n instance (live state). Updates flow source → live:

```bash
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
docker exec -i n8n-n8n-1 n8n import:workflow --input=/repo/workflows/operscale/WF_OPS_INTAKE_RECEIVE.json --separate
# Then in the n8n UI, activate the imported workflow.
```

### Database migrations

Migrations live in `supabase/migrations/`. Apply via:

```bash
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
docker exec -i supabase-db-1 psql -U postgres < /repo/supabase/migrations/00X_<name>.sql
```

Always test on a staging schema first. Production migrations are committed to repo; rollback by writing a `00X_rollback.sql` and applying it.

---

## CI/CD setup

GitHub Actions on push to `main`:

1. Run lint (ESLint for web, mypy + ruff for agent)
2. Run tests
3. Run `tools/lint_n8n_workflows.py` against `workflows/operscale/*.json`
4. Build Docker images, push to ghcr.io
5. SSH to VPS and run `docker compose up -d` for web + agent

Secrets in GitHub Actions:
- `VPS_SSH_KEY` (the same `id_ed25519_antigravity` key, base64 encoded)
- `GHCR_TOKEN` for image push

For the lint rules `AUTH-01` and `CRED-01` see `security.md`.

---

## Backup strategy

### Postgres (shared with VG)

VG already has Postgres backups configured. Our tables coexist in the same database, so they're covered automatically. Verify nightly backup is running:

```bash
ls -lh /docker/supabase/backups/ | tail -5
```

### Supabase Storage (our customer renders)

Customer's delivered renders are stored in Supabase Storage with 30-day retention. Backblaze B2 nightly snapshot:

```bash
# /usr/local/bin/operscale-storage-backup.sh
b2 sync /docker/supabase/storage/operscale-renders b2://operscale-backups/storage/$(date +%Y-%m-%d)/
```

### Configuration

`/root/operscale_keys.env`, `/docker/operscale-video-ads/docker-compose.override.yml`, and the n8n SQLite (`/var/lib/docker/volumes/n8n_n8n_data/_data/database.sqlite`) all back up nightly to Backblaze.

### Restore plan

Documented separately. For dev: spin up a clean Hostinger VPS, pull our images from ghcr.io, restore Postgres from latest dump, restore n8n SQLite, point DNS at new VPS. Estimated restore time: 4 hours from cold-start.

---

## Rollback procedure

For a bad deploy of `operscale-web` or `operscale-agent`:

```bash
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads

# Find the previous SHA from history:
docker images | grep operscale-video-ads | head -5

# Pin docker-compose.yml to the previous SHA:
sed -i 's|operscale-video-ads-web:latest|operscale-video-ads-web:abc1234|' docker-compose.yml
docker compose up -d web
```

For a bad migration: write and apply `00X_rollback.sql`. Migrations are designed to be idempotent and reversible.

---

## When this deployment shape changes

Per architecture.md, we re-baseline at:
- Day 30 (foundation behaviours)
- Day 60 (first paying customer)
- Day 90 (sustained traffic)
- Day 180 (own VPS spin-out probable)
