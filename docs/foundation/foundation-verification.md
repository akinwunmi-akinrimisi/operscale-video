
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
