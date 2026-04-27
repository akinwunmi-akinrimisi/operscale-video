
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
