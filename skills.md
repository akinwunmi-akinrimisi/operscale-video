# Operscale Video Ads — Skills Reference Map

> The index. `skills.sh` is the installer. `CLAUDE.md` is the methodology. `docs/VISION_GRIDAI_FORK_MANUAL.md` is the architectural reference.

This codebase is a fork of Vision GridAI. The render core is inherited untouched; everything else is built fresh. The skill landscape reflects that: render-core skills are kept, customer-facing skills are new, and the long-form / publishing / research skills VG used are explicitly absent.

---

## Public Skills

### Anthropic Public Skills (auto-activate from `/mnt/skills/public/`)

| Skill | Purpose |
|-------|---------|
| `frontend-design` | Production-grade UI tokens, components, styling. **Read SKILL.md first** before any React work in `apps/web/`. |
| `file-reading` | Routes uploaded files to the right reader (PDFs, docx, xlsx, etc.) |
| `pdf-reading` | Customer-uploaded brand decks, regulatory PDFs |
| `docx`, `xlsx`, `pptx` | Customer brand asset packages, finance reports |

### LobeHub Marketplace (relevant subset — install on demand)

8 skills that map onto the render core we inherited and the customer flow we build new. The rest of LobeHub's 50+ skills are not relevant to Operscale.

| Skill | Purpose |
|-------|---------|
| FFmpeg Core | Codecs, formats, container basics. Reference for inherited Ken Burns + assembly chain. |
| FFmpeg Video Toolkit | Concat, filter graphs, advanced video processing |
| FFmpeg Reference | Command reference for the 7 colour-mood profiles + 6 zoom directions |
| Supabase Integration | REST patterns, Realtime subscriptions, RLS policies (we use lockdown via service-role) |
| n8n Expression Syntax | The missing-`=` expression trap and JS expressions in nodes |
| API Credentials Manager | Secure credential handling — Paystack secret in agent env (NOT n8n), all others in n8n credential store |
| react-dashboard | Component patterns for `apps/web/` marketing site + founder console |
| google-gemini-media | TTS audio patterns (we use Chirp 3 HD per ADR 0009) |

### LobeHub skills explicitly NOT installed

These are Vision GridAI publishing/research skills. We don't post for customers and we don't research niches.

- `youtube-uploader`, `youtube-data-api-v3` — we deliver, customer posts
- `n8n-workflow-design`, `n8n-custom-node-builder` — we adapt VG's workflows, we don't write from scratch
- `google-sheets-cli`, `google-workspace-cli-gog` — Vision GridAI's data migration concerns
- Reddit (PRAW), Apify, pytrends, SerpAPI — niche research; we have 5 fixed niches with static markdown briefs
- YouTube/TikTok/Instagram comment APIs, AI Sentiment Analysis — post-publish engagement; out of scope

---

## Project Skills (local, installed by `skills.sh`)

12 skills in `~/.claude/skills/operscale-video-ads/`. Each is a markdown file with YAML frontmatter that Claude can autoload by name or description.

### Fork-related (most important)

#### `vg-fork-aware`
**When to use:** Any task that touches Vision GridAI inherited code (workflows, schema, render pipeline, caption burn service).
**What it teaches:** The single rule — inherit unchanged, build around. The 12 inherited gotchas. When to refactor (almost never) vs when to wrap (default).

#### `vg-workflow-rebind`
**When to use:** Importing or modifying a Vision GridAI workflow JSON.
**What it teaches:** Webhook path namespacing (`/webhook/operscale/...`), `OPS_` prefix convention, FK rebinding (`topic_id` → `video_id`, `topics` → `videos`), the missing-`=` expression trap, lint rule AUTH-01.

#### `prune-commit`
**When to use:** Day 1 deletion of unused VG surface area.
**What it teaches:** The single-commit discipline — don't trickle-delete. The list of files to remove is in fork manual §3.1; this skill ensures the agent doesn't accidentally re-import a deleted dependency.

#### `jwt-chain-rotation`
**When to use:** Rotating any JWT or shared secret.
**What it teaches:** The 5 sync points (4 from VG + our 5th container env). The order matters. Skipping any one produces a different silent failure.

### Customer-flow

#### `niche-aware-prompting`
**When to use:** Generating angles, scripts, or quote messages.
**What it teaches:** Load the relevant `niche-briefs/<niche>.md` first; the prompts in `prompt_configs` are context-skinny by design and the niche brief carries the operational knowledge.

#### `paystack-integration`
**When to use:** Any code touching payment.
**What it teaches:** HMAC-SHA512 webhook signature verification (non-negotiable, raw body before JSON parse), idempotency via `paystack_tx_ref` UNIQUE constraint, refund flow, NGN/kobo conversion.

#### `notion-gate-review`
**When to use:** Building or modifying gate workflows.
**What it teaches:** The Notion DB schema for gate cards, the automation that POSTs decisions back, why we chose Notion over a custom dashboard (ADR 0016).

#### `langgraph-node`
**When to use:** Adding or modifying agent state machine nodes.
**What it teaches:** Each state must (a) write `orders.pipeline_stage` before any side effect, (b) be idempotent on restart, (c) log via `production_log` and `llm_calls` where applicable. The state contract.

#### `gate-reviewer`
**When to use:** Any gate-related workflow or agent state.
**What it teaches:** The 5 gates (0, 1, 2, 3-bis, 3), what each one reviews, the SLA expectations, the approve/regenerate/reject decision tree, Pilot-tier bundling.

### Cross-cutting

#### `cost-monitor`
**When to use:** Adding any LLM call or external API call.
**What it teaches:** Always log to `llm_calls`. The 15% margin guard. Per-tier COGS targets ($3/$6/$25). The supervisor cron threshold.

#### `voice-cloning`
**When to use:** Implementing the optional Creative Pod voice cloning feature.
**What it teaches:** fal.ai PlayHT v3 integration (per ADR 0010), voice sample requirements (60s clean audio, no background music), consent paperwork.

#### `heygen-integration`
**When to use:** Implementing Creative Pod avatar features.
**What it teaches:** HeyGen API patterns, custom avatar from photo, multi-character segment rendering (cap at 2 speakers per ADR 0012), the Gate 3-bis quality check, per-segment FFmpeg assembly.

---

## Skills we explicitly do NOT have

These would be in a greenfield build but are deliberately absent because the work is either inherited from VG (don't write it) or out of scope (don't do it).

- `n8n-workflow-from-scratch` — we adapt VG's workflows, we don't write render workflows from scratch
- `ffmpeg-pipeline-design` — same; the pipeline is inherited
- `whisper-alignment` — `whisper_align.py` is inherited
- `kinetic-typography-engine` — `generate_kinetic_ass.py` is inherited
- `youtube-upload` — out of scope (we deliver to customer; they post)
- `tiktok-instagram-publisher` — out of scope
- `niche-research-orchestrator` — we have 5 fixed niches with static markdown briefs
- `topic-discovery-pipeline` — we don't generate topics; customers bring briefs in their order
- `social-analytics-cron` — we don't track post-publish performance
- `comment-engagement-loop` — same

If a Claude Code session is asking "how do I build X?" and X is in this list, the answer is in `docs/VISION_GRIDAI_FORK_MANUAL.md` — read that, don't write new code.

---

## Agency Agents (61 specialists in `~/.claude/agents/`)

All 61 agents from [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) install globally via `skills.sh`. They auto-activate based on context.

### Most relevant agents per Operscale pipeline area

| Area | Agent | Why |
|------|-------|-----|
| Marketing site (`apps/web/`) | Frontend Developer | React/Next.js component architecture, Tailwind |
| LangGraph agent (`apps/agent/`) | Backend Architect | State-machine design, idempotency, side-effect ordering |
| Brand naming + lock-in | Brand Guardian | Brand is `plovera` (locked per ADR 0017); use this agent for asset/voice/visual identity work |
| 9:16 ad image generation | Image Prompt Engineer | Operscale's images are vertical ads, not YouTube thumbnails |
| Paystack signature verification | Security Engineer | HMAC-SHA512, constant-time comparison, raw-body discipline |
| JWT chain + Supabase RLS | Security Engineer | The 5 sync points, RLS lockdown patterns |
| Traefik / Docker on shared VPS | DevOps Automator | Coexistence with Vision GridAI's stack |
| Webhook integration tests | API Tester | Paystack, Notion, Evolution API endpoints |
| Pipeline efficiency | Workflow Optimizer | Gate SLA monitoring, founder-time-per-order |
| Render performance | Performance Benchmarker | Caption-burn timeout, FFmpeg memory ceiling |
| Multi-state agent coordination | Agents Orchestrator | LangGraph waits + Realtime subscriptions |
| Ad script quality | Content Creator | Niche-tailored hooks, conversion-focused narrative |
| 35-day plan execution | Sprint Prioritizer | Daily deliverables, catch-up days |
| Gate 3 reject diagnosis | Feedback Synthesizer | Customer rejection reasons → script feedback |

### Agents NOT relevant for Operscale (skip even if auto-activated)

- **TikTok Strategist, Instagram Curator, Twitter Engager** — we don't post for customers
- **Trend Researcher** — niches are static, not researched
- **Reddit Community Builder, Xiaohongshu Specialist, WeChat / Zhihu Strategist** — wrong channels
- **App Store Optimizer** — we're not an app
- **Analytics Reporter** — we don't track post-publish metrics for customers
- **Senior Project Manager, Studio Producer** — agency-style overhead we don't carry as a single-founder operation

### Full roster (9 divisions, 61 agents)

**Engineering (8):** Frontend Developer, Backend Architect, Mobile App Builder, AI Engineer, DevOps Automator, Rapid Prototyper, Senior Developer, Security Engineer

**Design (7):** UI Designer, UX Researcher, UX Architect, Brand Guardian, Visual Storyteller, Whimsy Injector, Image Prompt Engineer

**Marketing (11):** Growth Hacker, Content Creator, Twitter Engager, TikTok Strategist, Instagram Curator, Reddit Community Builder, App Store Optimizer, Social Media Strategist, Xiaohongshu Specialist, WeChat Official Account Manager, Zhihu Strategist

**Product (3):** Sprint Prioritizer, Trend Researcher, Feedback Synthesizer

**Project Management (5):** Studio Producer, Project Shepherd, Studio Operations, Experiment Tracker, Senior Project Manager

**Testing (8):** Evidence Collector, Reality Checker, Test Results Analyzer, Performance Benchmarker, API Tester, Tool Evaluator, Workflow Optimizer, Accessibility Auditor

**Support (6):** Support Responder, Analytics Reporter, Finance Tracker, Infrastructure Maintainer, Legal Compliance Checker, Executive Summary Generator

**Spatial Computing (6):** XR Interface Architect, macOS Spatial/Metal Engineer, XR Immersive Developer, XR Cockpit Interaction Specialist, visionOS Spatial Engineer, Terminal Integration Specialist

**Specialized (7):** Agents Orchestrator, Data Analytics Reporter, LSP/Index Engineer, Sales Data Extraction Agent, Data Consolidation Agent, Report Distribution Agent, Agentic Identity & Trust Architect

---

## Skills × Pipeline Stage Matrix

The Operscale customer order moves through 8 stages. Each stage maps to specific skills (project-specific), agents (auto-activate), and inherited render-core workflows (untouched).

| Pipeline Stage | Project Skills | Agents | Inherited from VG |
|----------------|----------------|--------|-------------------|
| **A:** Intake (form → brief sanity) → **Gate 0** | `niche-aware-prompting` | Frontend Developer (form), Sprint Prioritizer | — |
| **B:** Angle generation (3 candidates) → **Gate 1** | `niche-aware-prompting`, `gate-reviewer`, `langgraph-node`, `cost-monitor` | Content Creator, AI Engineer | — |
| **C:** Quote delivery + Paystack payment | `paystack-integration` | Security Engineer, API Tester | — |
| **D:** Script generation → **Gate 2** | `niche-aware-prompting`, `gate-reviewer`, `langgraph-node`, `cost-monitor` | Content Creator, Feedback Synthesizer | — |
| **D-bis:** Avatar consent + photo upload (Creative Pod only) → **Gate 3-bis** | `heygen-integration`, `voice-cloning`, `gate-reviewer` | Security Engineer, Legal Compliance Checker | — |
| **E1:** TTS audio (master clock) | `vg-fork-aware`, `cost-monitor` | — | `WF_TTS_AUDIO` (Chirp 3 HD) |
| **E2:** Image generation (9:16) | `vg-fork-aware`, `vg-workflow-rebind` | Image Prompt Engineer | `WF_IMAGE_GENERATION` (Seedream 4.5) |
| **E3:** I2V clips (Standard ~20%, Creative Pod mixed) | `vg-fork-aware` | — | `WF_SCENE_I2V_PROCESSOR` (Seedance 2.0 Fast) |
| **E4:** Ken Burns + colour grade | `vg-fork-aware` | — | `WF_KEN_BURNS` (zoompan + colorbalance) |
| **E5:** Captions + transitions + assembly | `vg-fork-aware` | — | `WF_CAPTIONS_ASSEMBLY` (47 nodes, 3-layer crash prevention) |
| **E6:** Caption burn (kinetic ASS) | `vg-fork-aware` | — | `caption_burn_service.py` on host port 9998 |
| **F:** QA + render review → **Gate 3** | `gate-reviewer`, `notion-gate-review` | Performance Benchmarker, API Tester | `WF_QA_CHECK` (13 automated checks) |
| **G:** Delivery (email + WhatsApp) | `langgraph-node` | Support Responder | — |
| **Cross-cutting:** secret rotation | `jwt-chain-rotation` | Security Engineer, DevOps Automator | — |
| **Cross-cutting:** cost reconciliation | `cost-monitor` | Finance Tracker | — |
| **One-time:** Day 1 prune | `prune-commit` | Senior Developer | — |
| **Founder review surface** | `notion-gate-review` | — | — |
| **Build process** | — | **Superpowers** plugin, **Agency Agents** (61), **gstack** (selective: `/qa`, `/browse`, `/careful`, `/freeze`, `/review`), **frontend-design** | — |

---

## When to Use Which Skill

**Starting a new feature?** → Superpowers spec + plan at `docs/superpowers/`. Execute via subagent-driven-development.

**Building a marketing site page (`apps/web/`)?** → Read `frontend-design` SKILL.md first. Then use Frontend Developer agent. Run `/qa` after.

**Touching a Vision GridAI workflow JSON?** → Load `vg-fork-aware` + `vg-workflow-rebind`. Use the `/operscale:workflow-rebind` slash command. Don't refactor; rebind FKs and namespace webhook paths.

**Adding a new agent state in `apps/agent/`?** → Load `langgraph-node`. Write `orders.pipeline_stage` BEFORE any side effect. Listen for waits via Supabase Realtime, never busy-poll.

**Implementing payment?** → Load `paystack-integration`. Verify HMAC-SHA512 BEFORE JSON-parsing the body. Use the `/operscale:paystack-verify` slash command.

**Building Gate review?** → Load `notion-gate-review` + `gate-reviewer`. Notion DB → automation POST → `/webhook/operscale/gate/resume`. Don't build a custom dashboard for v1 (ADR 0016).

**Building Creative Pod custom avatar?** → Load `heygen-integration` + `voice-cloning`. Run Gate 3-bis quality check before HeyGen render. 3 failed photos → founder escalation.

**Adding a new niche?** → Load `niche-aware-prompting`. Create `niche-briefs/<niche>.md` with the same shape as the existing 5. Update `prompt_configs` table with the per-niche prompts. Test angle generation end-to-end.

**Rotating any credential?** → Load `jwt-chain-rotation`. The 5 sync points (in order). Backup first.

**Adding any LLM call?** → Load `cost-monitor`. Log to `llm_calls` with model + tokens + cost + duration. Respect tier COGS targets.

**Day 1 of the project?** → Load `prune-commit`. Read fork manual §3 in full. Single commit. Don't trickle-delete.

**Writing FFmpeg Ken Burns commands?** → Don't. The expressions are inherited and live in `WF_KEN_BURNS`. If you find yourself writing zoompan, you've taken a wrong turn — go back to `vg-fork-aware`.

**Writing FFmpeg colour grade?** → Same. The 7 colour-mood profiles are inherited; you don't tune them per order.

**Debugging a pipeline crash?** → Check `production_log` table first. Then `orders.pipeline_stage` for resume point. Then scene-level `audio_status / image_status / clip_status / video_status` fields. The render core is resume-aware.

**Credential issues?** → Never hardcode. All keys in n8n credential store EXCEPT `PAYSTACK_SECRET_KEY` (lives in agent env for HMAC verification).

**Before merging into main?** → `/freeze` (gstack), then `/review` (gstack). Both allowed; planning commands are not.

---

## Cost Reference

### Per-order COGS by tier

| Tier | Price (NGN) | Per-order COGS (USD) | Founder time |
|------|-------------|----------------------|--------------|
| Pilot | ₦75,000 (~$50) | ~$2.50 (Claude $2 + TTS $0.10 + images $0.24 + render $0) | 30 min |
| Standard | ₦175,000 (~$117) | ~$5 (Claude $4 + TTS $0.10 + images $0.36 + i2v ~$0.50 + music $0.02) | 60 min |
| Creative Pod | ₦350,000 (~$233) | ~$15-25 (3 videos × Standard cost + optional HeyGen $0-15 + optional voice clone $0-2) | 90 min |

**Margin guard:** supervisor cron flags any order where `total_cost_usd > 0.15 × (amount_paid_kobo / 100 / 1650)`. Order pauses for founder review.

**Founder time is not COGS but is the binding capacity constraint** — at 8 hours/day available for founder review, the ceiling is roughly 8 Pilot orders/day OR 5 Standard orders/day OR 3 Creative Pod orders/day, single-founder. Hire the first reviewer when sustained 5+ orders/day for 2 weeks.

### Per-call breakdown (reference)

| API call | Cost | Where |
|----------|------|-------|
| Claude Opus 4.7 — angle gen | ~$0.50 / order | Stage B |
| Claude Opus 4.7 — script gen | ~$1.50 / video | Stage D |
| Claude Haiku 4.5 — gate eval | ~$0.05 / gate | Stages A, B, D, F |
| Google Cloud Chirp 3 HD TTS | ~$0.012 / scene | Stage E1 |
| fal.ai Seedream 4.5 image | $0.030-0.040 / image | Stage E2 |
| fal.ai Seedance 2.0 Fast I2V | ~$0.05 / clip | Stage E3 |
| HeyGen avatar render | $5-15 / video | Stage D-bis (Creative Pod only) |
| fal.ai PlayHT v3 voice clone | ~$2 / video | Stage D-bis (Creative Pod only) |
| Paystack transaction fee | 1.5% + ₦100 (capped at ₦2000) | Stage C |
| Resend transactional email | $0 (free tier sufficient) | Stage C, G |
| Evolution API WhatsApp | $0 (self-hosted on shared VPS) | Stage C, G |

---

## Skill priority for new sessions

Order to load when starting a fresh Claude Code session in this repo:

1. `CLAUDE.md` (always first — build methodology + the 12 gotchas)
2. `docs/VISION_GRIDAI_FORK_MANUAL.md` (architectural context, especially §1-3 and §14)
3. `vg-fork-aware` skill
4. The skill matching the current task

Do not skip ahead. The first three give the mental model that makes the fourth land correctly.

---

## Adding a new skill

When you discover a pattern or pitfall worth capturing as a reusable skill:

1. Create `~/.claude/skills/operscale-video-ads/<skill-name>.md` with YAML frontmatter:
   ```yaml
   ---
   name: skill-name
   description: One-line summary of when to use this skill
   ---
   ```
2. Body: short prose explanation, code snippets where helpful, links to deeper docs.
3. Add a heredoc to `skills.sh` so future installs include it.
4. Update this `skills.md` index — add an entry with When-to-use / What-it-teaches.
5. Test: remove the skill, ask Claude Code to do the related task, see if it discovers the pitfall on its own. If yes, the skill is redundant. If no, the skill is earning its keep.

A skill is well-scoped if its body is under 200 lines and addresses one concern. A skill longer than that is probably two skills.

---

## What "skill" means in this codebase

A **skill** is a context-loadable markdown that teaches the agent (Claude Code) one specific operational pattern. Skills are NOT documentation for humans (those are the `.md` files in the repo root). Skills are NOT prompts (those live in `prompt_configs`). Skills are reusable instructional snippets that prevent the agent from re-discovering the same lesson in every session.

The 12 project skills above represent ~6 weeks of Vision GridAI's hard-won lessons (the inherited gotchas) plus the new operational knowledge our customer-facing layer requires (Paystack, Notion, HeyGen, etc.). Treat them as load-bearing — when one fires, it's saving the agent from a mistake the original team already paid for.
