# CLAUDE.md

> Operating rules for Claude when working in this repository.
> If you are reading this and you are Claude: this is the first file to load when starting any session in this repo. Do not skip to the requested task; the rules here are non-negotiable and reading them takes 90 seconds.

---

## What this codebase is

`operscale-video-ads` is the working repository name for an AI-powered video ad agency targeting Nigerian SMBs. The customer-facing brand is **`plovera`** (locked 2026-04-27 per ADR 0017) and the customer-facing domain is **`plovera.shop`**. Naming convention: codebase + repo + container names use `operscale-video-ads`; customer-facing strings (marketing site copy, email, WhatsApp templates) use `plovera` / `plovera.shop`.

The platform is **a fork of Vision GridAI**, not a greenfield build. The render core (TTS → image generation → Ken Burns → caption assembly → caption burn) is being inherited untouched from `https://github.com/akinwunmi-akinrimisi/vision-gridai-platform`. We are building only the customer-facing intake/payment/delivery layer on top.

**Primary reference document: `docs/VISION_GRIDAI_FORK_MANUAL.md`.** This 1,764-line manual is the source of truth for what gets cloned, adapted, or built new. Read it before any architecture decision. If something in this `CLAUDE.md` and the fork manual disagree, the fork manual wins.

---

## Tech stack — locked

These decisions have ADRs. Do not propose alternatives without first reading the relevant ADR.

| Layer | Choice | ADR |
|---|---|---|
| Frontend | Next.js 15 + TypeScript + Tailwind | (no ADR — assumed) |
| Agent orchestration | LangGraph (Python 3.11) | ADR 0002 |
| LLM | Claude Opus 4.7 (default), Haiku for evaluators | ADR 0003 |
| Database | Supabase self-hosted (shared with Vision GridAI initially) | ADR 0004 |
| Render core | Vision GridAI fork (n8n + FFmpeg + caption burn host service) | ADR 0008 |
| TTS | Google Cloud Chirp 3 HD across ALL tiers | ADR 0009 |
| Voice cloning | fal.ai PlayHT v3 (Creative Pod only) | ADR 0010 |
| Avatar features | HeyGen API (Creative Pod only) | ADR 0011 |
| Image generation | fal.ai Seedream 4.5 (inherited from VG) | (inherited) |
| Video generation | fal.ai Seedance 2.0 Fast for I2V (Creative Pod), Wan 2.5 for T2V | (inherited) |
| Music | Vertex AI Lyria (Standard+ tiers) | (inherited) |
| Payments | Paystack only (NGN) | ADR 0007 |
| Delivery | Resend (email) + Evolution API (WhatsApp) | ADR 0005 |
| Founder gate review | Notion DB | ADR 0016 |
| Hosting | Hostinger KVM (shared with VG) | ADR 0004 |

---

## Architecture in one paragraph

Customer fills out an intake form on the marketing site → Next.js API route persists the brief and triggers `WF_OPS_INTAKE_RECEIVE` → founder reviews via Notion (Gate 0) → LangGraph agent generates 3 niche-tailored ad angles via Claude Opus 4.7 → quote email + WhatsApp delivered with Paystack link → customer pays → Paystack webhook (signature-verified) transitions order to `paid` → agent generates script (Gate 1: angle, Gate 2: script via Notion) → production triggers Vision GridAI's forked render workflows (`WF_TTS_AUDIO` → `WF_IMAGE_GENERATION` → optionally `WF_SEEDANCE_I2V` → `WF_KEN_BURNS` → `WF_CAPTIONS_ASSEMBLY` → caption burn host service on `:9998`) → Gate 3 founder reviews final render via Notion → `WF_OPS_DELIVERY_FANOUT` sends signed URL via email + WhatsApp → 7-day post-delivery follow-up email.

For the full state machine see `docs/diagrams/order-lifecycle.mmd`. For the render pipeline detail see `docs/VISION_GRIDAI_FORK_MANUAL.md` §7.

---

## Tier matrix — at a glance

| Feature | Pilot (₦75K) | Standard (₦175K) | Creative Pod (₦350K) |
|---|---|---|---|
| Videos | 1 | 1 | 3 |
| Length | 15-30s | 15-45s | 15-60s each |
| TTS | Chirp 3 HD | Chirp 3 HD | Chirp 3 HD |
| Voice cloning | — | — | Optional (fal.ai PlayHT) |
| Production style | Documentary | Documentary | Documentary OR Avatar-led |
| Multi-character dialogue | — | — | Up to 2 speakers |
| Custom avatar from photo | — | — | Optional (HeyGen) |
| Music | Royalty-free | Artlist licensed | Artlist + scene-specific |
| Captions | White kinetic | Niche-styled with red emphasis | Custom typography |
| Output formats | 9:16 only | 9:16 + 1:1 + 16:9 | All + 4K master |
| Revisions | 1 free | 2 free | 2 per video (6 total) |
| Delivery | 48h | 36h | 72h |
| Payment | 100% upfront | 100% upfront | 50/50 |

For the canonical reference see `pricing-and-packages.md` and `tier-spec-v2.html`.

---

## Build methodology — non-negotiable

All Claude Code work in this project uses **Superpowers (obra/superpowers)** as the primary build methodology, NOT GSD. The Anthropic frontend-design skill is used for all React/UI work. gstack is used selectively for `/qa`, `/browse`, `/careful`, `/freeze`, `/review` only — gstack's planning skills are excluded as they conflict with Superpowers.

Never hardcode API keys (Anthropic, Paystack, HeyGen, fal.ai, Google Cloud, etc.) in plain text in n8n workflow nodes — always reference existing n8n credentials or use `$getWorkflowStaticData` pattern. See `security.md`.

---

## The most important rule in this entire codebase

**Inherit Vision GridAI's render core untouched, build everything around it new, and trust that the original team already paid the debugging cost so you don't have to.**

Vision GridAI is a 235-commit production system. Its `WF_TTS_AUDIO`, `WF_IMAGE_GENERATION`, `WF_KEN_BURNS`, `WF_CAPTIONS_ASSEMBLY`, `WF_RETRY_WRAPPER`, and the host-side `caption_burn_service.py` took ~6 months of iteration to dial in. The audio master clock rule, the 3-layer FFmpeg crash prevention, the per-scene resume logic, the JWT 4-sync-points discipline — all paid for in production incidents.

If you find yourself thinking "I could rewrite this in fewer lines / a more modern framework / a cleaner pattern", **stop**. That instinct will cost the project 6 weeks. The right action is to leave the inherited code alone, add your new code around it, and only refactor if a real customer bug demands it.

---

## Inherited gotchas — must remember

These are listed in full in `docs/VISION_GRIDAI_FORK_MANUAL.md` §14. Brief reminders:

1. **`localhost` from inside an n8n container resolves to IPv6 `::1` and silently fails to reach the host.** Use `172.18.0.1` (Docker bridge gateway).
2. **n8n Authorization headers must start with `=` to be evaluated as expressions.** Without the `=`, the literal `{{ $env.DASHBOARD_API_TOKEN }}` is sent. VG had 17 nodes silently failing this way for 30 days. Lint rule `AUTH-01` blocks this; port it.
3. **Mismatched fps between FFmpeg input clips causes silent truncation under `-c copy`.** Lock all clips to `30fps libx264 yuv420p`. The 3-layer crash prevention in `WF_CAPTIONS_ASSEMBLY` handles this; don't bypass it.
4. **`REPLICA IDENTITY FULL` is required on every Realtime-published table** or UPDATE events arrive without the changed columns.
5. **The Supabase JWT chain has 4 sync points** (`/docker/n8n/docker-compose.override.yml`, `_realtime.tenants.jwt_secret` × 2 rows, `kong.yml` + `kong reload`, dashboard `.env`). Skipping any produces a different silent failure.
6. **Music volume is 0.12, not 0.5.** Non-negotiable per VG directive. Music must be barely perceptible under voiceover.
7. **Caption burn service has a 3-hour timeout and lives on the host, not in a container.** Uses `docker exec n8n-n8n-1 ffmpeg ...` to piggyback FFmpeg inside the container while keeping the HTTP listener outside the n8n task runner's memory budget.
8. **fal.ai async queue limits:** 2 image / 10s, 1 T2V / 60s, 2 I2V / 10s. `WF_RETRY_WRAPPER` absorbs 429s.
9. **`NODE_FUNCTION_ALLOW_BUILTIN=child_process`** required in n8n env or Code nodes using `subprocess` fail silently.
10. **Audio is the master clock.** Every visual's duration = its scene's TTS audio duration via FFprobe. Never derive from word count.
11. **Writes to Supabase are scene-by-scene, never batched.** Batching breaks the resume guarantee.
12. **The `caption_highlight_word` column has a CHECK constraint blocking shell metacharacters.** Inherited from VG migration 031. Don't drop it.

---

## Where to look for what

- **Architecture decisions:** `docs/adr/` — read in numerical order for the project's reasoning timeline
- **The fork strategy:** `docs/VISION_GRIDAI_FORK_MANUAL.md`
- **What the render pipeline does:** Fork manual §7
- **What the customer experiences:** `customer-journey.md`
- **What the gates review:** `gates-and-approvals.md`
- **Pricing tiers:** `pricing-and-packages.md` and `tier-spec-v2.html`
- **What the agent computes:** `AGENT.md`
- **How we deploy:** `deployment.md`
- **Security boundaries:** `security.md`
- **What we do per niche:** `niche-briefs/`
- **Build steps day-by-day:** Fork manual §15 + `implementation.md`
- **Cost economics:** `launch-budget.html`

If a question isn't answered by any of those, ask before guessing.

---

## What "done" means

For tier 1 ship, see fork manual §16 — the 26-item Definition of Done checklist. Every box must be checked before the first paying customer order is accepted.

Do not loosen this checklist to ship faster. The cost of a refund obligation on a customer order with a known-broken pipeline far exceeds the cost of one extra day of testing.
