
## Day 4 — Operscale Docker compose

> Verification run: 2026-04-27 (UTC time at deploy)

- operscale-web: Up (nginx:1.27-alpine, started cleanly, 4 worker processes)
- operscale-agent: Up (python:3.11-slim, started cleanly)
- /data/operscale-production bind in n8n-n8n-1: Missing — needs n8n override edit (★ standing-rule gate)
- https://plovera.shop response: HTTP/2 200 — but from Hostinger CDN edge (2.57.91.91), NOT from VPS (72.61.201.148). DNS not pointed at VPS yet.
- Local Host-header probe `curl -k -H 'Host: plovera.shop' https://127.0.0.1/`: Timeout (000). Traefik receives TLS, establishes session, but ACME cert for plovera.shop failed (Let's Encrypt TLS-ALPN-01 challenge to 2.57.91.91 returned "no application protocol"); Traefik serves default self-signed cert and holds the request — no upstream response delivered. Router config and network membership are correct; block is DNS-only.
- Compose corrections applied (vs plan): network name `n8n_n8n_network`, certresolver `mytlschallenge`, removed `env_file` (Foundation-phase placeholder).
- Pre-flight network confirmation: `docker network ls | grep n8n_n8n_network` returned present (ID 894062a9f54a).

### Additional observations

- `operscale-web` joined `n8n_n8n_network` (172.18.0.19) and `docker_operscale-net` (172.21.0.3). Traefik correctly discovered the container via Docker provider.
- `operscale-agent` joined `docker_operscale-net` (172.21.0.2).
- Traefik labels on operscale-web are correct: `Host(\`plovera.shop\`) || Host(\`www.plovera.shop\`)`, entrypoint `websecure`, certresolver `mytlschallenge`.
- ACME attempt was triggered (logged at 2026-04-27T15:16:46Z) and failed cleanly — no partial state to clean up. Will succeed automatically once DNS A record for plovera.shop is updated from 2.57.91.91 to 72.61.201.148.
- The ★ standing-rule gate for `/docker/n8n/docker-compose.override.yml` was hit. No edit was made. Pending user confirmation to add `/data/operscale-production:/tmp/operscale-production` volume mount to n8n container.

## Day 5 — Schema applied to shared Supabase  *(★3, ★4)*

> Apply run: 2026-04-27 (UTC)
> HEAD applied: f623b62 docs(foundation): correct Day-3 collision check — actual table names + operscale fix

- 001_initial.sql: ✅
- 002_seed_registers.sql: ✅ (2 production_registers seeded)
- 003_seed_prompt_configs.sql: ✅ (20 prompt_configs seeded — 5 niches × 4 prompt types)
- 004_storage_buckets.sql: ✅ (4 buckets created: order-deliverables, customer-photos, customer-voice-samples, customer-logos; RLS policies applied)
- 12 Operscale tables exist in `operscale.*` schema: ✅
- REPLICA IDENTITY FULL on `operscale.{orders, videos, scenes, production_log, gate_decisions}`: ✅
- Realtime publication membership (5 tables, all `schemaname=operscale`): ✅
- `anon_visible_rows` on `operscale.orders` = 0 (RLS lockdown working): ✅ — anon has no USAGE on the `operscale` schema (`permission denied for schema operscale`), which is stricter than RLS alone; confirmed via `information_schema.usage_privileges` returning empty for grantee=anon on operscale schema
- `public.scenes` row count post-apply: 1140 (Day-3 baseline 1,140 — VG untouched ✅)
- Pre-flight count of `operscale.*` matching our 12 names BEFORE apply: 0

### ★3 + ★4 gate sign-off

- ★3 (first migration apply on shared Supabase): cleared via apply-migrations.sh exit 0
- ★4 (ALTER PUBLICATION supabase_realtime ADD TABLE for the 5 Realtime tables): cleared, all 5 visible in publication query

## Day 6 — TTS standalone render (real Google Cloud TTS, fake-order-1)

> Verification run: 2026-04-27 (UTC)
> HEAD applied: 1f3b7d1 fix(infra): rebind-workflow.py — sub-workflow Fire URL pass

### Pre-Day-6 fixes that landed during the run

The Day-6 attempt surfaced and corrected several deviations from plan-verbatim that the rebind/scaffolding work had missed. All resolved before the verification proof point:

| Fix | Why it was needed |
| --- | --- |
| ★ standing-rule gate: `/docker/supabase/docker-compose.yml` adds `operscale` to `PGRST_DB_SCHEMAS` | Without this, every PostgREST call from the workflows (39 nodes across 8 workflows) would 404 — `operscale` schema wasn't exposed |
| ★ standing-rule gate: `/docker/n8n/docker-compose.override.yml` adds `/data/operscale-production:/tmp/operscale-production` | TTS files write to `/tmp/operscale-production/` inside n8n; without the bind mount, files would land in container ephemeral storage |
| `/docker/operscale-video-ads/.env.agent` (mode 600) | seed_test_order.py + future agent code need SUPABASE_URL + SERVICE_ROLE_KEY + SCHEMA env; uses VG's existing service-role JWT per resume-prompt rule |
| `005_grant_operscale_roles.sql` | Service-role hit `42501 permission denied for schema operscale` because USAGE wasn't granted; Supabase's `public` schema gets this from platform bootstrap, custom schemas need it explicit |
| `006_mirror_vg_render_columns.sql` | TTS errored at "Load Topic Drive Info" — `videos.drive_subfolder_ids does not exist`; 001 had 21 cols on `operscale.videos`, but VG's render workflows reference 107 more cols from `public.topics`. Agreed Option A: bulk-mirror minus YouTube fields. |
| 001 idempotency fixes | `ALTER PUBLICATION ADD TABLE` and `CREATE POLICY` had no `IF NOT EXISTS`; re-runs failed at 001 before reaching 005/006 |
| rebind-workflow.py — webhook node `parameters.path` rebind | Original regex matched `/webhook/X` literal text but n8n stores paths bare; without this, `production/tts` collided with VG's WF_TTS_AUDIO at activation (HTTP 400 "There is a conflict with one of the webhooks") |
| rebind-workflow.py — `Accept-Profile + Content-Profile = operscale` headers | 39 PostgREST calls would have defaulted to `public` schema and silently corrupted VG's tables |
| rebind-workflow.py — sub-workflow Fire URLs | First TTS run accidentally fired VG's WF_IMAGE_GENERATION (errored 44ms, no fal.ai cost); URLs like `={{ $env.N8N_WEBHOOK_BASE }}/production/images` weren't rebound because `/webhook/` only appears in the resolved URL, not the JSON template |
| rebind-workflow.py — emoji → ASCII | Windows cp1252 codec crashed on `✅`/`❌` print statements before any json.dump ran |

### TTS render proof point

- Workflows imported into live n8n (3): OPS_TTS_AUDIO (active), OPS_IMAGE_GENERATION (active), OPS_RETRY_WRAPPER (sub-workflow, no activation needed)
- Webhook URL: `POST https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/tts`
- Test order seeded: `customer_id`, `brief_id`, `order_id=74a69222-6c9a-4cd9-90c4-d38a018e69f6`, `video_id=e6dc52f7-7d2a-4e50-a751-80cffe60ee41`, 5 scenes
- n8n execution `85768`: `status=success`, `mode=webhook`, `started=16:45:52.425Z`, `stopped=16:45:57.347Z`, **wall-clock 4.92s** for 5 Chirp 3 HD calls + decode + ffprobe + DB updates
- 29 nodes ran end-to-end through Compile Summary + Set Topic Status Images + Log TTS Completed

### Acceptance criteria (per plan Task 6.3)

- 5 mp3 files at `/data/operscale-production/<video_id>/audio/`: ✅
  - `scene_001.mp3` 12,864 bytes
  - `scene_002.mp3` 14,016 bytes
  - `scene_003.mp3` 12,192 bytes
  - `scene_004.mp3` 14,496 bytes
  - `scene_005.mp3`  8,256 bytes
- `operscale.scenes.audio_status='uploaded'` on all 5: ✅
- `operscale.scenes.audio_duration_ms` populated: ✅ (3216, 3504, 3048, 3624, 2064 ms; FFprobe-measured)
- `operscale.videos.audio_progress='complete'`: ✅
- Master clock established (audio duration is source of truth, NOT word count): ✅ (per inherited gotcha #10)
- VG `public.scenes` row count: 1140 (zero drift, VG untouched): ✅

### Caveats and follow-ups (non-blocking for Foundation)

- `audio_file_url` and `audio_file_drive_id` are NULL — the workflow's "Upload to Drive" step erred because the test order has no `videos.drive_folder_id` configured. Render-pipeline integrity is unaffected (downstream workflows pick up files via the host filesystem path); Drive upload becomes load-bearing in Customer-flow when end-customers receive Drive-hosted previews.
- VG's WF_IMAGE_GENERATION received a stray fire on the first attempt and errored in 44ms. Zero fal.ai cost. Rebind-workflow.py fix in commit `1f3b7d1` prevents recurrence; downstream Day-8 image-gen will fire OPS_IMAGE_GENERATION as intended.
