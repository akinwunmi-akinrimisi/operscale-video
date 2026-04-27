# 0004. Share the Vision GridAI VPS at launch

Date: 2026-04-21
Status: Accepted (supplemented by [0008](0008-fork-vision-gridai.md))

## Context

We need hosting for:
- The Next.js marketing site (`apps/web`, container `operscale-web`)
- The LangGraph agent (`apps/agent`, container `operscale-agent`)
- Postgres + Supabase (REST + Realtime + Storage + Kong)
- n8n + the rendering chain
- A host-side caption-burn service on port `:9998`
- Traefik for TLS termination

Three options:

1. **Dedicated VPS.** Spin up a second Hostinger KVM (or equivalent) for Operscale Video Ads. Full isolation; ~$30-60/month plus second-instance overhead (separate JWT chain, separate caption-burn service, separate FFmpeg).
2. **Share the existing Vision GridAI VPS.** Same Postgres, same n8n, same caption-burn service. Operscale-specific containers (`operscale-web`, `operscale-agent`) bind-mount their own scratch dir at `/data/operscale-production/`. Workflow names prefixed `OPS_*`; webhook paths under `/webhook/operscale/...`.
3. **Managed PaaS (Vercel/Render/Fly).** Hosted Next.js, hosted Postgres (Supabase Cloud or Neon). Lower operational burden but higher per-month cost at our scale and fragmenting the render pipeline that lives on the VPS.

Vision GridAI runs on a Hostinger KVM with sufficient headroom. The caption-burn service is operationally complex (host-side, port `:9998`, 3-hour timeouts, `docker exec n8n-n8n-1 ffmpeg ...`). Duplicating it on a second VPS would require careful port discipline and extra maintenance.

## Decision

**Share the Vision GridAI VPS at launch.** Operscale containers run alongside VG containers. Both products use the same Postgres, the same n8n, the same caption-burn service.

Concretely:
- New compose file at `/docker/operscale-video-ads/docker-compose.yml` with `operscale-web` and `operscale-agent`
- New scratch dir at `/data/operscale-production/`, bind-mounted into the n8n container as `/tmp/operscale-production`
- Operscale Supabase tables (12 of them) coexist with VG's ~50 tables in the same Postgres
- Operscale n8n workflows live alongside VG's, with `OPS_*` naming and `/webhook/operscale/...` paths
- Traefik adds new routes for `plovera.shop` (and `www.plovera.shop`) without touching VG routes

Supplemented by [0008](0008-fork-vision-gridai.md) which made the strategic decision to fork VG's render core into our repo (rather than calling it as a service across the wire). The compute lives on the same VPS; the source is forked once.

## Consequences

**Cost saving:** ~$30-60/month avoided. Material at pre-revenue stage.

**Operational simplicity:** one VPS, one Postgres, one n8n, one caption-burn service to monitor.

**Failure-mode coupling.** If the VPS goes down, both products go down. If Postgres OOMs, both products stall. Mitigation: alerts go to founder; both products have defined SLAs that recover gracefully on transient outages.

**JWT chain widening.** VG's 4-sync-point JWT rotation now becomes our 5-sync-point rotation (the 5th being our `operscale-video-ads/docker-compose.override.yml`). Skip rule: never rotate without backups. See `security.md` §JWT-chain.

**Resource contention risk.** If VG's renders consume all FFmpeg / fal.ai capacity at the same moment ours do, we slow down. Trigger: sustained 80% CPU or 80% queue saturation → upgrade KVM tier.

## Revisit conditions

We split the VPS when **any** of:
- Sustained 3+ Operscale orders/day for 2 weeks (forecast at Day 90 milestone)
- Operscale revenue > ₦5M/month (signals capacity for own infra)
- Either product's deploys cause regressions in the other for >2 weeks running
- Postgres needs > 16 GB sustained

Splitting means: separate VPS, separate Supabase, separate n8n, our own caption-burn service. Notion can stay shared.

## Reference

- [0008](0008-fork-vision-gridai.md): the fork decision (compute coupling at the runtime layer).
- [deployment.md](../../deployment.md): the runtime topology in detail.
- [security.md](../../security.md) §JWT-chain.
