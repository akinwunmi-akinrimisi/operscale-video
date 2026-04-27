# Infrastructure State — Day 3 VPS Recon

> Snapshot date: 2026-04-27
> Source: `infra/scripts/recon-vps.sh` output, run on `srv1297445.hstgr.cloud`.
> Sections 1, 3, 4, 6, 7 of the script's output are reproduced verbatim below. Section 5 (Supabase containers) is enumerated within section 1's docker listing; section 8 (Traefik) is captured in the drift table; section 9 (disk + memory) returned nominal values and is not reproduced.
> Read-only audit. No writes performed.

## Summary verdict

**YELLOW — minor drift documented below; no blockers.**

Reasoning:

- **n8n-n8n-1**: running, FFmpeg 8.0.1 accessible, `NODE_FUNCTION_ALLOW_BUILTIN` set correctly.
- **supabase-db-1**: running and healthy (Up 8 days). 121 tables in public schema; none of our 12 expected migration table names appear in the Realtime publication.
- **Caption burn service**: systemd unit active/running (5 days uptime), HTTP 200 on `/health` at `172.18.0.1:9998`. Fully operational.
- **Traefik**: `n8n-traefik-1` present and running.
- **`/data/n8n-production`** and **`/docker`** both readable with expected VG subdirectory structure.
- **Drift items**: The VPS is a densely shared host — 25 containers in total from multiple unrelated projects (`fitforge90-app`, `sarah-backend`, `cal-web`, `jobops`, `audio-merger`, `cloudboosta-voice-agent`, etc.). This is not a blocker but Day 4 bind-mount paths and port selections must be chosen to avoid collision with those extra services (see Drift section). `supabase-db-1` is named with the Supabase project prefix rather than the `n8n-supabase-db-1` pattern some VG docs reference — this is normal for a standalone Supabase compose deployment.
- **No collision on our 12 table names** detected in the Realtime publication list. (Full table enumeration not available from this recon — see note in Postgres section.)
- This state is safe to proceed to Day 4 with the drift items recorded and accounted for.

---

## Docker containers running

```text
NAMES                           STATUS                   PORTS
n8n-n8n-1                       Up 42 hours              127.0.0.1:5678->5678/tcp
fitforge90-app                  Up 4 days (healthy)      3000/tcp
supabase-kong-1                 Up 5 days (healthy)      8000-8001/tcp, 8443-8444/tcp
supabase-storage-1              Up 5 days                5000/tcp
supabase-studio-1               Up 5 days (healthy)      3000/tcp
supabase-realtime-1             Up 5 days
supabase-auth-1                 Up 5 days
supabase-rest-1                 Up 5 days                3000/tcp
sarah-backend-sarah-backend-1   Up 2 weeks               8000/tcp
evolution-api                   Up 2 weeks
evolution-db                    Up 2 weeks               5432/tcp
cal-web                         Up 2 weeks (healthy)     3000/tcp
cal-db                          Up 2 weeks               5432/tcp
dashboard                       Up 2 weeks               80/tcp
cloudboosta-voice-agent         Up 5 weeks               8080/tcp
jobops                          Up 3 weeks (healthy)     127.0.0.1:3005->3001/tcp
supabase-meta-1                 Up 3 weeks (healthy)     8080/tcp
supabase-oauth2-proxy-1         Up 6 weeks
supabase-db-1                   Up 8 days (healthy)      5432/tcp
supabase-functions-1            Up 6 weeks
audio-merger                    Up 2 weeks               0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
n8n-traefik-1                   Up 2 weeks               0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp
ffmpeg-api                      Up 2 weeks (healthy)     0.0.0.0:3002->3002/tcp, [::]:3002->3002/tcp
code-executor                   Up 2 weeks (unhealthy)   0.0.0.0:3003->3003/tcp, [::]:3003->3003/tcp
gcp-token-service               Up 2 weeks               0.0.0.0:3001->3001/tcp, [::]:3001->3001/tcp
```

**n8n container health (section 2):**

```text
ffmpeg version 8.0.1 Copyright (c) 2000-2025 the FFmpeg developers
cred_5JokeQ.json
cred_KtMyWD_pre_fix_2026_04_26.json
cred_Qs.json
cred_export.json
cred_fixed.json
cred_verify.json
gcloud-env.sh
merged
n8nDataTableUploads
production
NODE_FUNCTION_ALLOW_BUILTIN=child_process,https,http,url
```

---

## Caption burn service

```text
● caption-burn.service - Caption Burn Service (FFmpeg outside n8n)
     Loaded: loaded (/etc/systemd/system/caption-burn.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-04-21 21:26:26 UTC; 5 days ago
   Main PID: 1447525 (python3)
      Tasks: 1 (limit: 19144)
     Memory: 10.7M (peak: 11.0M)
        CPU: 1min 20.761s
     CGroup: /system.slice/caption-burn.service
             └─1447525 /usr/bin/python3 /opt/caption-burn/caption_burn_service.py

  health-check HTTP: 200
```

Decision input for Day 9 (★5 caption-burn integration choice):
- [x] Symlink path is viable (no conflict at `/data/n8n-production/operscale`)
- [ ] Env-var path is needed because [reason]

The service is active, healthy, and listening on `172.18.0.1:9998`. The systemd unit is enabled (will survive reboots). `/data/n8n-production` exists and is writable (`drwxrwxrwx`). The symlink approach (`/data/n8n-production/operscale` → our job output directory) is viable with no detected conflict.

Specifically: `/data/n8n-production` is world-writable, so creating a sibling directory `/data/n8n-production/operscale/` (or a symlink there) is non-destructive to VG's existing job output tree, and the active caption-burn service can reach files placed there without configuration changes.

Caveat: this recon listed `/data/` (parent) but did not enumerate `/data/n8n-production/`'s contents. The "no conflict at `/data/n8n-production/operscale`" conclusion is inferred from the writable parent — Day 9 ★5 should verify `ls /data/n8n-production/` before creating the path or symlink, in case a same-named entry already exists.

---

## Filesystem layout

```text
/data/ listing:
total 20
drwxr-xr-x  5 root root 4096 Apr 18 15:46 .
drwxr-xr-x 25 root root 4096 Apr 27 13:38 ..
drwxr-xr-x  2 root root 4096 Apr 18 15:38 fonts
drwxr-xr-x  2 root root 4096 Apr 18 15:46 luts
drwxrwxrwx  5 root root 4096 Apr 18 16:46 n8n-production

/docker/ listing:
total 52
drwxr-xr-x 13 root root 4096 Apr 27 14:00 .
drwxr-xr-x 25 root root 4096 Apr 27 13:38 ..
drwxr-xr-x  2 root root 4096 Feb 18 16:00 audio-merger
lrwxrwxrwx  1 root root   21 Apr 11 13:09 backend -> /docker/sarah-backend
drwxr-xr-x  2 root root 4096 Apr 10 23:25 cal-com
drwxr-xr-x  2 root root 4096 Feb  4 15:19 code-executor
lrwxrwxrwx  1 root root   31 Apr 11 13:09 dashboard -> /docker/sarah-backend/dashboard
drwxr-xr-x  2 root root 4096 Apr 10 13:12 evolution-api
drwxr-xr-x  2 root root 4096 Apr 21 21:39 ffmpeg-api
drwxr-xr-x 15 root root 4096 Mar 16 09:52 jobops
drwxr-xr-x  3 root root 4096 Apr 25 20:37 n8n
drwxr-xr-x 13 root root 4096 Apr 27 14:17 operscale-video-ads
drwxr-xr-x  9 root root 4096 Apr 11 13:08 sarah-backend
drwxr-xr-x  6 root root 4096 Apr 10 09:58 sarah-backend-old
drwxr-xr-x  3 root root 4096 Apr 21 20:01 supabase
```

`/data` shows the expected VG subdirectory structure: `n8n-production` (world-writable, VG job output root), `fonts` and `luts` directories (VG render assets). No unexpected top-level entries.

`/docker` shows the expected VG service directories (`n8n`, `supabase`) plus numerous other application directories for other projects sharing the VPS. Our `operscale-video-ads` directory is present at `/docker/operscale-video-ads` as expected. Day 4 compose files should bind-mount under `/docker/operscale-video-ads/` for isolation.

---

## Postgres / Supabase

Table count: 121

Realtime publication tables: ab_test_variants, ab_tests, analysis_groups, audience_insights, channel_analyses, coach_messages, coach_sessions, comments, competitor_alerts, competitor_channels, competitor_videos, cost_calculator_snapshots, daily_ideas, discovered_channels, keywords, niche_health_history, niche_viability_reports, pps_config, production_log, production_logs, projects, research_categories, research_runs, revenue_attribution, scenes, scheduled_posts, shorts, style_profiles, system_prompts, topic_keywords, topics, yt_discovery_runs, yt_video_analyses

No collision detected in the Realtime publication: none of our 12 expected table names (`customer_orders`, `videos`, `assets`, `events`, `agent_runs`, `gates`, `outbox`, `paystack_events`, `delivery_log`, `niches`, `tier_specs`, and the storage-policy targets from migration 004) appear in the publication list. The 33 published tables are all VG/shared-VPS application tables with clearly distinct naming conventions.

**Limitation**: the recon script captures only the table count (121) for the full public schema, not an enumeration of all names. A complete collision check would require `SELECT tablename FROM information_schema.tables WHERE table_schema='public'`. Given the naming evidence from the Realtime publication and the VG codebase context, the collision risk is low, but Day 5 ★3 migration should include a pre-flight `SELECT` asserting none of our 12 names exist before applying the DDL.

---

## Drift from VG docs (if any)

| VG expected component | Status |
|---|---|
| `n8n-n8n-1` container running | ✅ present — Up 42 hours |
| `supabase-db-1` container running and healthy | ✅ present — Up 8 days (healthy) |
| `/data/n8n-production` directory | ✅ present — world-writable |
| Traefik proxy container | ✅ present — `n8n-traefik-1`, Up 2 weeks, ports 80/443 |
| Host-side caption-burn service on `:9998` | ✅ present — systemd active/running since 2026-04-21, HTTP 200 |
| `NODE_FUNCTION_ALLOW_BUILTIN=child_process` env in n8n | ✅ present — value is `child_process,https,http,url` |
| FFmpeg accessible inside n8n container | ✅ present — v8.0.1 |

**Extra / unexpected containers (not in VG base docs):**

The VPS is a shared host with multiple unrelated projects. The following containers exist beyond the VG baseline and must be considered when choosing ports and bind-mount paths for Day 4:

| Container | Uptime | Exposed ports | Day 4 relevance |
|---|---|---|---|
| `fitforge90-app` | 4 days | 3000/tcp (internal) | No conflict |
| `sarah-backend-sarah-backend-1` | 2 weeks | 8000/tcp (internal) | No conflict |
| `evolution-api` | 2 weeks | (none mapped) | Evolution API used by our delivery layer — confirm this is the shared instance |
| `evolution-db` | 2 weeks | 5432/tcp (internal) | Separate Postgres for Evolution API |
| `cal-web` | 2 weeks | 3000/tcp (internal) | No conflict |
| `cal-db` | 2 weeks | 5432/tcp (internal) | No conflict |
| `dashboard` | 2 weeks | 80/tcp (internal) | No conflict (Traefik routes; not host-bound) |
| `cloudboosta-voice-agent` | 5 weeks | 8080/tcp (internal) | No conflict |
| `jobops` | 3 weeks | 127.0.0.1:3005->3001/tcp | No conflict (loopback only) |
| `audio-merger` | 2 weeks | **0.0.0.0:8080** | ⚠️ Occupies host port 8080 — Day 4 must not bind any operscale service to 8080 |
| `ffmpeg-api` | 2 weeks | **0.0.0.0:3002** | ⚠️ Occupies host port 3002 |
| `code-executor` | 2 weeks | **0.0.0.0:3003** (unhealthy) | ⚠️ Occupies host port 3003 |
| `gcp-token-service` | 2 weeks | **0.0.0.0:3001** | ⚠️ Occupies host port 3001 |

**Host ports occupied on Day 4 (hard conflicts — must NOT bind any operscale service to these on `0.0.0.0`):**

- `80`, `443` — `n8n-traefik-1` (HTTP/HTTPS reverse proxy)
- `3001` — `gcp-token-service`
- `3002` — `ffmpeg-api`
- `3003` — `code-executor`
- `8080` — `audio-merger` (host-bound). Note: `supabase-meta-1` also exposes 8080/tcp internally; not a host conflict but multiply occupied at the container-network level.

**Loopback-only bindings (NOT hard conflicts; binding `0.0.0.0:<port>` would shadow the loopback service in proxy routing — be deliberate if doing so):**

- `127.0.0.1:5678` — `n8n-n8n-1`
- `127.0.0.1:3005` — `jobops` (mapped to container's 3001)

**Note on `evolution-api`:** Our delivery layer (ADR 0005) uses Evolution API for WhatsApp. The container `evolution-api` is already running on this VPS. Day 4 / delivery configuration should confirm whether this is the shared instance we should integrate with or whether a separate instance is needed.

---

## Decisions deferred to later Days

- **Day 4**: Operscale containers compose file — bind mount paths confirmed against this recon. Avoid host ports 80, 443, 3001, 3002, 3003, 8080. Mount application data under `/docker/operscale-video-ads/` for isolation.
- **Day 5**: ★3 migration apply —
  1. **Pre-flight collision check**: Add a `DO $$ BEGIN IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name = ANY(ARRAY['customer_orders','videos','assets','events','agent_runs','gates','outbox','paystack_events','delivery_log','niches','tier_specs'])) > 0 THEN RAISE EXCEPTION 'Collision detected'; END IF; END $$;` block before the DDL to guard against a surprise collision in the 121-table public schema not visible from the Realtime publication alone.
  2. **RLS DO-block isolation**: Confirm the RLS-policy DO blocks in migrations 001 and 004 reference only our newly-created tables — they must NOT touch RLS on any existing VG table. Verify by reading each `ALTER TABLE … ENABLE ROW LEVEL SECURITY` and `CREATE POLICY` statement against the table-collision check above.
- **Day 9**: ★5 caption-burn path strategy — symlink is the recommended default. `/data/n8n-production` is world-writable, caption-burn service is healthy at `:9998`. Create `/data/n8n-production/operscale/` as the job output root and symlink as needed.
- **Evolution API**: Confirm with project owner whether `evolution-api` container on this VPS is the intended integration target for WhatsApp delivery, or whether a separate instance is required.
