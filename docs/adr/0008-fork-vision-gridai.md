# 0008. Fork Vision GridAI's render core; do not build greenfield

Date: 2026-04-26
Status: Accepted

## Context

We need a video render pipeline for Operscale Video Ads: TTS → image generation → motion → caption assembly → caption burn. Three options:

1. **Build from scratch.** Pure greenfield, write our own n8n workflows, our own caption burn service, our own assembly logic.
2. **Use Vision GridAI as a service.** Call VG's API for renders; share infra; vendor-relationship between two products.
3. **Fork Vision GridAI's render core.** Take a snapshot, prune the YouTube/social/long-form layers, build customer-flow on top.

Vision GridAI (`github.com/akinwunmi-akinrimisi/vision-gridai-platform`) is a 235-commit production system. Its render pipeline took ~6 months and 30+ debugging-disaster-recovery sessions to dial in. The audio master clock rule, the 3-layer FFmpeg crash prevention, the per-scene resume logic, the JWT 4-sync-points discipline — all paid for in production incidents.

## Decision

**Fork the render core, prune ~60%, build customer-flow on top.**

Concretely:
- Vendored snapshot at a known SHA (not a git fork — we want clean attribution and license clarity)
- Day 1 Prune Commit removes YouTube/social workflows, niche research, 3-pass scripting, analytics, intelligence layer, Australia overlay
- Keep render-core workflows untouched: WF_TTS_AUDIO, WF_IMAGE_GENERATION, WF_KEN_BURNS, WF_CAPTIONS_ASSEMBLY, WF_RETRY_WRAPPER, WF_ASSEMBLY_WATCHDOG, WF_SHORTS_PRODUCE, WF_ENDCARD, WF_MUSIC_GENERATE
- Keep host-side caption_burn_service.py untouched (just env-var-configurable for our path)
- Build new: customer-facing intake, payment, agent orchestration, delivery
- Schema fresh-write: don't inherit VG's 32 migrations; write our own clean migration history at 001
- Workflow namespace: `OPS_*` prefix in n8n, `/webhook/operscale/*` paths

## Consequences

**Saved:** approximately 6-10 weeks of trial-and-error rebuild time. The 12 inherited gotchas alone (the missing-`=` trap, REPLICA IDENTITY FULL, audio-as-master-clock, etc.) would each cost days when discovered fresh.

**Costs:**
- Tighter coupling to VG's design choices (e.g., we inherit n8n as our orchestration layer for renders)
- We must coordinate any divergent changes with VG's roadmap (when both products share a workflow)
- Our learning curve has a "VG knowledge" prerequisite — onboarding new engineers requires reading the fork manual

**Mitigations:**
- The `OPS_*` prefix and `/webhook/operscale/*` paths give us namespace isolation
- We share the n8n instance only for the render core; new customer-flow workflows are wholly ours
- The fork manual (`docs/VISION_GRIDAI_FORK_MANUAL.md`) captures all VG context for new engineers

**Why we rejected alternative 1 (greenfield):** the 6-month rebuild gap kills our launch timeline. We'd be re-discovering bugs that VG paid the cost to discover.

**Why we rejected alternative 2 (use as a service):** creates a vendor relationship between two products of the same founder. Version skew, deployment coupling, and shared-fate are all worse than fork-and-diverge.

## Reference

`docs/VISION_GRIDAI_FORK_MANUAL.md` — comprehensive fork strategy.
