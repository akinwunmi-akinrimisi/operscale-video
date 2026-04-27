# Foundation Sub-Project — Design Spec

> **Status:** Approved (brainstorm complete; awaiting user review of this written spec)
> **Date:** 2026-04-27
> **Sub-project of:** Operscale Video Ads — A-Z build (Phase 0 of 3)
> **Methodology:** Superpowers (primary) + frontend-design (later phases) + selective gstack
> **Next step:** `superpowers:writing-plans` skill, after user review of this spec

---

## 1. Strategic context (locks from brainstorm Q1-Q7)

The full Operscale Video Ads build is decomposed into **three sub-projects** (horizontal layer slice, per Q3=B):

1. **Foundation** *(this spec; Days 1-14)* — render core wired to fresh schema, end-to-end against synthetic test data
2. **Customer-flow** *(future spec; Days 15-32)* — marketing site, intake, Paystack, agent state machine, Notion gates, all 3 tiers' agent paths, customer comms
3. **Creative-features-and-polish** *(future spec; Days 33-50)* — HeyGen avatar, fal.ai PlayHT cloning, multi-character render, brand colours, logo overlay, thumbnail gen, performance check-in, revision tracking, monitoring, refunds, lint CI, live Paystack, DoD

This document specs **Foundation only.** Customer-flow and Creative-features-and-polish get their own specs after Foundation closes.

### Decisions locked during brainstorm

| # | Question | Locked answer | Implication for Foundation |
|---|---|---|---|
| Q1 | TTS engine | **A** — Chirp 3 HD across all tiers (per ADR 0009) | `tier-spec-v2.html` will be edited in Customer-flow phase to remove ElevenLabs claims; Foundation tests Chirp only |
| Q2 | V1 launch scope | **D** — all 3 tiers fully per tier-spec at launch (~50-60 day total timeline) | Schema must accommodate Creative Pod fields by end of build, even if not exercised in Foundation |
| Q3 | Decomposition | **B** — horizontal layer slice (3 sub-projects) | Foundation is sub-project #1 of 3 |
| Q4 | Foundation gate | **B** — robust (render + Realtime + resume + 5 niches + caption-burn edges) | The Day-14 verification doc must show all five evidenced |
| Q5 | Cadence | **D** — hybrid; named gates for risky ops; **no key rotations period** | Seven named gates marked ★1-★7 in Section 7 |
| Q6 | Schema strategy | **C** — extend `001_initial.sql` with universal-to-all-tiers fields; defer Creative-Pod-only fields | Day 1 edits 001 with `brand_colors_hex`, `logo_storage_url`, `revisions_used`, `revisions_max`, `performance_checkin_*`, `strategy_call_*`. Creative-Pod columns (`heygen_avatar_id`, `voice_clone_id`, `speaker_tag`, `voice_variant_count`) land in `005_creative_pod_columns.sql` during Creative-features phase |
| Q7 | VG vendoring | **C** — cherry-pick + keep-list snapshot in `_vendored_for_reference/keep-list-original/` | Day 1 vendoring script clones VG, copies only the keep-list, leaves a SHA stamp; the vendored VG application itself is **read-only / untouched** |

### User clarifications absorbed

- **Vision GridAI is a live application** sharing the VPS, n8n, Postgres, caption-burn service, JWT chain, Traefik, and Docker network. We do not modify or risk it. We coexist via additive tables, `OPS_*` workflow prefix, `/webhook/operscale/*` path namespace, separate scratch dir at `/data/operscale-production/`.
- **No JWT chain rotation, no `keys_new.env` rotation, no shared-secret rotation** — these would break VG and the other apps that share keys.
- **All keys in the existing `.env` are valid and reusable** — no need to provision new ones.
- **Tier-spec-v2.html (2026-04-22)** is the customer-facing source of truth for what we promise per tier, with conflicts vs. ADRs 0008-0017 resolved per Q1=A (TTS) and Q2=D (full tier roster).

---

## 2. Goal of Foundation

> The render core works end-to-end against the new Operscale schema, on the shared VPS, without modifying VG, with all five robustness criteria evidenced.

The five criteria (from Q4=B):

1. **Render** — A synthetic Pilot-tier real-estate test order produces a watchable 9:16 MP4, audio synced, captions burned, OPS_QA_CHECK 13/13 passing.
2. **Realtime** — A Python test client subscribes to `videos` and `gate_decisions`, receives UPDATE events with payload columns within 2s, JWT chain validates without errors.
3. **Resume** — A mid-render `docker kill n8n-n8n-1` followed by restart and re-trigger does not re-render completed scenes (mtime check), only resumes from the interrupted scene onwards.
4. **5 niches** — Each of `real-estate`, `education`, `fashion-ecom`, `fintech`, `health` renders successfully with niche-correct register colours and TTS speaking rates per ADR 0009; OPS_QA_CHECK 13/13 each.
5. **Caption-burn edges** — Three failure-induction scenarios from fork manual §9.4 (kill-n8n-mid-render, induce-caption-burn-timeout, simulate-fal-outage) all produce expected behaviour: clean failure markers in DB, no zombie processes, no half-written `final.mp4`.

**Out of scope:** the LangGraph agent, the marketing site, Paystack, Notion gates, Anthropic LLM calls, HeyGen, fal.ai PlayHT, multi-character, brand-colour rendering, logo overlay, thumbnail generation, customer file uploads, real customer data of any kind. Each is enumerated explicitly in Section 7 of this spec.

---

## 3. Architecture

Foundation is **a render pipeline wired to a fresh schema, sharing infra with Vision GridAI without modifying it.**

```
                    ┌────────────────────────────────────────────────────┐
                    │           Hostinger KVM (shared with VG)           │
                    └────────────────────────────────────────────────────┘
                                            │
       ┌─────────────────┬──────────────────┴──────────────────┬─────────────────┐
       │                 │                                     │                 │
       ▼                 ▼                                     ▼                 ▼
  Postgres /         n8n container                    caption_burn         Operscale
  Supabase          (n8n-n8n-1)                       service              containers
  (shared)                                            (host port 9998,    (NEW: web,
       │            VG workflows                      shared with VG)      agent — placeholders
       │            (untouched, running)                                   in Foundation;
       ▼                                              docker exec into     populated in
  VG tables (~50)   OPS_* workflows (NEW,             n8n-n8n-1 ffmpeg     later phases)
  + Operscale       cherry-picked + rebound)
  tables (12,                                           ▲
  additive,         ▲                                   │
  RLS-locked)       │                                   │
       │            │  HTTP webhooks at                 │  /data/operscale-
       │            │  /webhook/operscale/*             │  production/
       │            │                                   │  bind-mounted
       └─Realtime───┘                                   │  into n8n
         publication                                    │
         (REPLICA IDENTITY FULL                         │
          on 5 tables)                                  │
                                                        │
       Test driver (curl from any host)─────────────────┘
```

### Invariants Foundation enforces

1. **VG's running deployment is read-only from our perspective.** Our prune is on our own clone copy, not on VG's running config. Workflows are imported alongside under `OPS_*` names; tables are added alongside without touching VG's; caption-burn service is called via its existing HTTP API.
2. **Two namespace conventions are non-negotiable:** workflow-name prefix `OPS_*` and webhook path prefix `/webhook/operscale/*`. Without these, our test render firing the `/webhook/production/tts` path would land on VG's running TTS workflow and corrupt VG's state.
3. **The shared key surface is untouched.** No JWT rotation. No `keys_new.env` edit. We consume what's there.
4. **`/data/operscale-production/` on the VPS is our scratch dir,** bind-mounted into the n8n container at `/tmp/operscale-production`. VG's `/data/n8n-production/` is its scratch dir. The two never overlap.
5. **Realtime is plumbed end-to-end.** Our 5 tables (`orders`, `videos`, `scenes`, `production_log`, `gate_decisions`) are added to the `supabase_realtime` publication and have `REPLICA IDENTITY FULL` set.

---

## 4. Components

Three groups: cherry-picked from VG (with rebind), newly authored, already in scaffold.

### 4.1 Cherry-picked from VG (with rebind transform)

**12 n8n workflow JSONs** — go into `apps/n8n-workflows/operscale/` after rebind; un-rebound originals also saved into `_vendored_for_reference/keep-list-original/`:

| Source | Operscale name | Purpose | Used in Foundation? |
|---|---|---|---|
| `WF_TTS_AUDIO` | `OPS_TTS_AUDIO` | Per-scene Chirp 3 HD TTS, master clock | ✅ Day 6 |
| `WF_IMAGE_GENERATION` | `OPS_IMAGE_GENERATION` | fal.ai Seedream 4.5 portrait_9_16 | ✅ Day 6 |
| `WF_SCENE_IMAGE_PROCESSOR` | `OPS_SCENE_IMAGE_PROCESSOR` | Single-scene image worker (retries) | ✅ Day 8 |
| `WF_SCENE_I2V_PROCESSOR` | `OPS_SCENE_I2V_PROCESSOR` | fal.ai Seedance 2.0 Fast (Creative Pod) | ⚠️ imported, unused |
| `WF_KEN_BURNS` | `OPS_KEN_BURNS` | FFmpeg zoompan + 7 colour-mood profiles | ✅ Day 8 |
| `WF_CAPTIONS_ASSEMBLY` | `OPS_CAPTIONS_ASSEMBLY` | 47-node concat with 3-layer crash prevention | ✅ Day 8 |
| `WF_RETRY_WRAPPER` | `OPS_RETRY_WRAPPER` | Exponential backoff sub-workflow | ✅ Day 6 (referenced by all) |
| `WF_ASSEMBLY_WATCHDOG` | `OPS_ASSEMBLY_WATCHDOG` | Cron monitoring stuck FFmpeg renders | ✅ Day 8 |
| `WF_ENDCARD` | `OPS_ENDCARD` | Standard+ end-card | ⚠️ imported, unused |
| `WF_MUSIC_GENERATE` | `OPS_MUSIC_GENERATE` | Vertex AI Lyria (Standard+ tier) | ⚠️ imported, unused |
| `WF_MASTER` | `OPS_RENDER_PIPELINE` | Top-level orchestrator (curl entry point) | ✅ Day 10 |
| `WF_QA_CHECK` | `OPS_QA_CHECK` | 13 automated render-quality checks | ✅ Day 11 |

**4 host-side scripts** — go into `infra/host-scripts/`; originals saved to `_vendored_for_reference/keep-list-original/host-scripts/`:

| Source | Modified in Foundation? |
|---|---|
| `caption_burn_service.py` | ⚠️ Day 9 named gate — symlink (preferred) or env-var path |
| `generate_kinetic_ass.py` | ✅ extended Day 11 (per fork manual §8.7) for niche colour mapping |
| `whisper_align.py` | ❌ untouched |
| `burn_captions.sh` | ❌ untouched |

### 4.2 Newly authored

**Bash / scripts:**
- `infra/scripts/vendor-vg.sh` — clones VG, populates `_vendored_for_reference/keep-list-original/`, writes `SOURCE_SHA.txt`, removes the clone
- `infra/scripts/rebind-workflow.py` — applies the rebind transform (webhook-path namespacing, `OPS_*` rename, FK rebind `topic_id→video_id`, `topics→videos`, `project_id→order_id`, `projects→orders`, scratch path remap, AUTH-01 expression-prefix verification, CRED-01 inline-credential rejection)
- `infra/scripts/apply-migrations.sh` — VPS-side runbook for applying `001`-`004` against shared Supabase
- `tools/lint_n8n_workflows.py` — port of VG's lint tool (AUTH-01 + CRED-01 rules); CI wiring lands in Creative-features phase, but the tool itself is written in Foundation

**Schema migrations:**
- `supabase/migrations/001_initial.sql` — **EXTENDED** with universal fields (`briefs.brand_colors_hex JSONB`, `briefs.logo_storage_url TEXT`, `videos.revisions_used INT DEFAULT 0`, `videos.revisions_max INT`, `orders.performance_checkin_email_sent_at TIMESTAMPTZ`, `orders.performance_checkin_response JSONB`, `orders.strategy_call_scheduled_for TIMESTAMPTZ`, `orders.strategy_call_completed_at TIMESTAMPTZ`)
- `supabase/migrations/002_seed_registers.sql` — already in scaffold, no edits
- `supabase/migrations/003_seed_prompt_configs.sql` — already in scaffold, no edits
- `supabase/migrations/004_storage_buckets.sql` — **NEW** — creates Supabase Storage buckets (`order-deliverables`, `customer-photos`, `customer-voice-samples`, `customer-logos`); RLS policies on each

**Docker compose:**
- `infra/docker/operscale-compose.yml` — `operscale-web` and `operscale-agent` services with bind mounts to `/data/operscale-production:/tmp/operscale-production`, Traefik labels for `plovera.shop`, env-file references. Both containers' images are placeholders in Foundation (real Dockerfiles arrive in Customer-flow).

**Test fixtures + harness:**
- `apps/agent/tests/seed_test_order.py` — Python CLI: `--niche`, `--tier`, `--all-niches`, `--output-format ids`. Inserts `customers + briefs + orders + videos + scenes` rows via service-role Supabase client; prints UUIDs.
- `apps/agent/tests/fixtures/scripts/{real-estate,education,fashion-ecom,fintech,health}.json` — 5 hand-crafted 5-scene synthetic scripts, niche-correct `color_mood`, `caption_highlight_word`, register binding.
- `apps/agent/tests/realtime_smoke_test.py` — subscribes to `videos` and `gate_decisions`, asserts UPDATE events arrive with payload columns within 2s, asserts JWT validates.
- `apps/agent/tests/induce_failure.py` — implements three failure modes from fork manual §9.4: `kill-n8n-mid-render`, `induce-caption-burn-timeout`, `simulate-fal-outage`.

**Documentation deliverables:**
- `docs/foundation/infrastructure-state-day-3.md` — produced Day 3 from VPS reconnaissance
- `docs/foundation/day-9-caption-burn-decision.md` — produced Day 9 documenting symlink vs env-var
- `docs/foundation/foundation-verification.md` — produced Day 14, the gate artefact

### 4.3 Already in scaffold (no Foundation work needed)

Initial scaffold commit `488f089` + slash-commands commit `bd2ecea` together cover: `.gitignore`, `.gitattributes`, `CLAUDE.md`, `AGENT.md`, `architecture.md`, `README.md`, `DEPLOY.md`, `docs/adr/0001-0017`, the four `docs/specs/*.md` files, `docs/diagrams/{order-lifecycle,render-pipeline}.mmd`, `docs/VISION_GRIDAI_FORK_MANUAL.md`, the 6 niche-brief stubs, `_vendored_for_reference/VENDORING.md`, `apps/web/package.json`, `infra/traefik/operscale-labels.yml`, `skills.sh`, `skills.md`, the 12 globally-installed project skills at `~/.claude/skills/operscale-video-ads/`, the 3 slash commands at `.claude/commands/operscale/`, and 181 Agency Agents at `~/.claude/agents/`.

---

## 5. Data flow (canonical Foundation render)

The canonical render is a **synthetic Pilot-tier real-estate test order, 5 scenes, no logo / no brand colours / no thumbnail / no avatar**, traveling end-to-end from a curl invocation to a watchable MP4 on disk.

### Trajectory

```
1. SEED  →  apps/agent/tests/seed_test_order.py --niche real-estate
   INSERT customers / briefs / orders / videos / scenes×5
   STDOUT: order_id, video_id

2. TRIGGER  →  curl POST /webhook/operscale/production/render
   Auth: Bearer ${DASHBOARD_API_TOKEN}  (reused from VG, never rotated)

3. OPS_RENDER_PIPELINE  →  fires children sequentially:
       OPS_TTS_AUDIO → OPS_IMAGE_GENERATION → OPS_KEN_BURNS
                                                  │
                                                  ▼
       caption_burn_service:9998 ◄ OPS_CAPTIONS_ASSEMBLY

4. OPS_TTS_AUDIO       →  Chirp 3 HD per scene; writes audio_file_url, audio_duration_ms
                          (audio is the master clock; gotcha #10)
5. OPS_IMAGE_GENERATION → Seedream 4.5 per scene; portrait_9_16 forced
6. OPS_KEN_BURNS       →  FFmpeg zoompan + colour-mood; clip duration = audio_duration_ms
                          all clips locked to 30fps libx264 yuv420p (gotcha #3)
7. OPS_CAPTIONS_ASSEMBLY → concat with music at volume=0.12 (gotcha #6),
                           generate_kinetic_ass.py produces niche-colour ASS
8. caption_burn_service:9998 → docker exec into n8n-n8n-1, ffmpeg burn,
                                3-hour timeout, atomic swap with _no_captions.mp4 backup

9. REALTIME ECHO  (continuous)  →  every UPDATE on videos/scenes/production_log fires
                                   a Realtime broadcast with payload columns
                                   (REPLICA IDENTITY FULL — gotcha #4)
```

### Per-day verification triggers

| Day | Trigger | Asserts |
|---|---|---|
| 6 | curl OPS_TTS_AUDIO | 5 mp3 files, audio_duration_ms set, audio_status='uploaded' |
| 8 | curl OPS_IMAGE_GENERATION → KEN_BURNS → CAPTIONS_ASSEMBLY | 5 clips, motion + colour grade, single assembled.mp4 |
| 9 | curl caption_burn (after Day 9 gate) | final.mp4 exists, captions visible, audio synced |
| 10 | curl OPS_RENDER_PIPELINE | All 8 stages fire from one call |
| 10 | kill n8n mid-render, restart | Resume from last completed scene |
| 11 | run all 5 niches | Niche-correct colours + speaking rates; OPS_QA_CHECK 13/13 each |
| 12 | induce_failure.py simulate-fal-outage | Retry wrapper absorbs 429s |
| 12 | induce_failure.py induce-caption-burn-timeout | Clean failure, no zombie process, no half-final.mp4 |
| 13 | realtime_smoke_test.py | UPDATE events arrive with changed columns; JWT validates |
| 14 | All previous + re-render of all 5 niches | Foundation-verification.md complete |

---

## 6. Error handling

Foundation **inherits VG's resume + retry discipline**; it does not reinvent it. The error-handling story is enforcement of inherited invariants plus stops at named gates.

### 6.1 Resume guarantees

Every workflow checks `*_status` columns before doing work; if `complete`, the scene is skipped. Re-firing any workflow is idempotent.

| Column | States | Set by |
|---|---|---|
| `scenes.audio_status` | `pending → uploading → uploaded → failed` | `OPS_TTS_AUDIO` |
| `scenes.image_status` | `pending → generating → complete → failed` | `OPS_IMAGE_GENERATION` |
| `scenes.video_status` | `pending → processing → complete → failed` | `OPS_SCENE_I2V_PROCESSOR` (unused in Foundation) |
| `scenes.clip_status` | `pending → rendering → complete → failed` | `OPS_KEN_BURNS` |
| `videos.assembly_status` | `pending → assembling → assembled → complete → failed` | `OPS_CAPTIONS_ASSEMBLY` + caption_burn_service |
| `videos.caption_burn_status` | `pending → burning → complete → failed` | caption_burn_service |

**Day 12 verification:** kill n8n mid-`OPS_KEN_BURNS` at scene 3; restart; re-fire `OPS_RENDER_PIPELINE`; assert scenes 1+2 unmodified (mtime), scene 3+ rendered fresh, final.mp4 produced.

### 6.2 Retry semantics

`OPS_RETRY_WRAPPER` (inherited) wraps external API calls:
- fal.ai Seedream / Seedance: 429 → exponential backoff 1s/2s/4s/8s/16s, max 5 attempts; respects fork-manual gotcha #8 limits
- Google Cloud Chirp 3 HD: 429 / 500 → backoff, max 3 attempts; outages > 5 min mark scene as `failed`
- Anthropic: not used in Foundation

Exhausted retries → `*_status='failed'` + `production_log` entry. In Foundation there's no agent to read these, so failed scene = manual debugging. Expected.

### 6.3 Foundation-specific failure modes (Day 12)

Three scenarios from fork manual §9.4, no others:
1. Mid-render n8n crash
2. Caption-burn 3-hour timeout (induced via 30s mock)
3. fal.ai 503 outage simulation

### 6.4 Named gates (Q5=D)

Seven gates where I stop and confirm before executing:

| ★ | Gate | Reason |
|---|---|---|
| 1 | Day 1 vendor-vg.sh on VPS | First-time VG clone to live VPS |
| 2 | Day 2 cherry-pick + rebind transform | Rebind errors propagate everywhere |
| 3 | Day 5 first migration apply | First write to Postgres VG depends on |
| 4 | Day 5 ALTER PUBLICATION supabase_realtime | Modifies VG-shared publication |
| 5 | Day 9 caption-burn integration choice | Touches host service shared with VG |
| 6 | Day 14 pre-merge `/freeze` | Locks state before phase boundary |
| 7 | Day 14 final go/no-go | Decides whether Customer-flow may begin |

Plus standing rule: any edit to `/docker/n8n/docker-compose.override.yml` or `/docker/supabase/*` is gated.

### 6.5 Operations explicitly forbidden in Foundation

- No JWT rotation under any circumstance (would break VG and other apps sharing keys)
- No `keys_new.env` / `operscale_keys.env` rotation
- No `supabase-db-1` or `n8n-n8n-1` restart without explicit consent
- No `--no-verify` git commits or `git push --force` on shared branches
- No `rm -rf` outside `/tmp/vg-clone` and `_vendored_for_reference/keep-list-original/`
- No edits to VG's running n8n workflows (`WF_*` names)
- No bypass of the `caption_highlight_word` shell-injection CHECK constraint (gotcha #12)

---

## 7. Out-of-scope (explicit boundary)

Below is **definitively NOT in Foundation**. Items are deferred to the named follow-on phases.

### Customer-flow phase concerns (Days 15-32)
- LangGraph agent — only `apps/agent/tests/` exists; `src/states/`, `src/heygen/`, `src/voice/`, `src/consent/` stay empty (`.gitkeep` only)
- Marketing site — `apps/web/package.json` from scaffold only; no Next.js code
- Intake form, save-token resume, anonymous case-study pages
- Paystack — webhook signature verification, refund flow, transaction handling
- Resend / Evolution API — no transactional sends from Foundation
- Notion gate-review database — no card creation or automation
- LLM calls (Anthropic Opus 4.7 + Haiku 4.5) — `llm_calls` table sits empty
- The 8 new `WF_OPS_*` workflows (INTAKE_RECEIVE, PAYSTACK_WEBHOOK, QUOTE_DELIVER, GATE_NOTIFY, GATE_RESUME, DELIVERY_FANOUT, REFUND, AVATAR_QUALITY)
- Customer-photo / voice-sample / logo upload UI — Storage buckets exist but no upload code

### Creative-features-and-polish phase concerns (Days 33-50)
- HeyGen API integration (avatar pipeline, custom avatar from photo, multi-character segment renders, Gate 3-bis quality check)
- fal.ai PlayHT v3 voice cloning
- Multi-character dialogue (`scenes.speaker_tag`, per-segment HeyGen orchestration, FFmpeg multi-character assembly)
- Brand-color rendering integration (live customer brand colours flowing into image prompts and caption ASS)
- Logo placement workflow (`WF_OPS_LOGO_OVERLAY`)
- Thumbnail generation workflow (`WF_OPS_THUMBNAIL_GEN`)
- Strategy-call coordination (Calendly integration or manual flow)
- Performance check-in cron (`WF_OPS_PERFORMANCE_CHECKIN`)
- Revision charge flow (`WF_OPS_REVISION_CHARGE`)
- The `production_avatar` agent state path
- Migration `005_creative_pod_columns.sql` (`heygen_avatar_id`, `voice_clone_id`, `speaker_tag`, `voice_variant_count`)
- Cost monitoring and supervisor cron (`WF_OPS_SUPERVISOR`)
- CI wiring of `tools/lint_n8n_workflows.py`
- Production-grade error pages, rate limiting, status page

### Even-if-convenient deferrals
- **No agent stubs** — empty `apps/agent/src/` directories. Any stub creates the temptation to "just connect Realtime to it for the test" — that's the agent's job in Customer-flow.
- **No marketing-site stubs** — empty `apps/web/src/`.
- **No real customer data anywhere** — all test orders synthetic with `test-` email prefix.
- **No edits to `keep-list-original/` after the cherry-pick is done** — that snapshot is a frozen reference.
- **No new ADRs unless genuinely required.** Decisions land in `docs/foundation/day-N-<topic>-decision.md`, not new ADRs.

### Touched but not modified
- VG's running n8n container (we add workflows alongside)
- Shared Postgres (we add tables alongside)
- Shared caption-burn service (we call its HTTP API)
- Shared Traefik (we add a route)
- Shared `/data/` mount (we use `/data/operscale-production/`)
- Shared `keys_new.env` and JWT chain (read-only)

---

## 8. Day-by-day deliverable map + tool/skill mapping

### Overview

```
   Day  Title                                  Where     Named gate?   Skills/agents
   ───  ──────────────────────────────────     ───────   ───────────   ─────────────────────────────────
    1   Vendor VG + extend 001 schema          Win+VPS   ★1            vg-fork-aware, DevOps Automator,
                                                                       /operscale:workflow-rebind
    2   Cherry-pick + rebind workflows         Win       ★2            vg-workflow-rebind, /operscale:workflow-rebind,
                                                                       Workflow Optimizer
    3   VPS reconnaissance                     VPS                     Infrastructure Maintainer, /careful
    4   Operscale Docker compose deploy        Win+VPS                 DevOps Automator, /careful
    5   Apply migrations to shared Supabase    VPS       ★3, ★4        Database Optimizer, Backend Architect, /careful
    6   Import OPS_TTS + IMG + RETRY           VPS                     vg-fork-aware, API Tester
    7   Slack / catch-up                       —                       —
    8   Import OPS_KEN_BURNS + ASSEMBLY        VPS                     vg-fork-aware, Performance Benchmarker, API Tester
    9   Caption-burn integration               VPS       ★5            vg-fork-aware, /careful, Infrastructure Maintainer
   10   End-to-end dry-run + resume test       VPS                     superpowers:test-driven-development, Test Results Analyzer
   11   5-niche test matrix                    VPS                     niche-aware-prompting, Test Results Analyzer, /qa
   12   Failure induction (3 scenarios)        VPS                     superpowers:systematic-debugging, Performance Benchmarker
   13   Realtime smoke test                    Win+VPS                 superpowers:verification-before-completion, API Tester
   14   Foundation verification + go/no-go     Win+VPS   ★6, ★7        Reality Checker, Evidence Collector, /qa, /review, /freeze
```

### Per-day expansion

#### Day 1 — Vendor VG + extend 001 schema  *(★1)*

**Tasks:** edit `001_initial.sql` to add Q6=C universal fields; write `infra/scripts/vendor-vg.sh`; add `004_storage_buckets.sql`. Push. **Gate ★1:** user runs `vendor-vg.sh` on VPS, pastes output, I confirm `_vendored_for_reference/keep-list-original/` populated and `SOURCE_SHA.txt` written.

**Driver agents/skills:** DevOps Automator, `vg-fork-aware`, `/operscale:workflow-rebind`.

**Deliverable:** Repo at SHA-X with extended 001 + vendoring scripts; VPS has keep-list snapshot.

#### Day 2 — Cherry-pick + rebind workflows  *(★2)*

**Tasks:** author `infra/scripts/rebind-workflow.py`; rebind all 12 keep-list workflows; copy host-scripts un-rebound; port `tools/lint_n8n_workflows.py`. **Gate ★2:** run linter on all 12 OPS workflows; if any fail, stop. Single commit with rebound JSONs + host scripts + lint tool.

**Driver agents/skills:** Backend Architect, Workflow Optimizer, `vg-workflow-rebind`, `/operscale:workflow-rebind`.

**Deliverable:** Lint-clean OPS workflow set on `main`. No imports yet.

#### Day 3 — VPS reconnaissance

**Tasks:** read-only audit via my script (`docker ps`, `systemctl status caption-burn.service`, `ls /data/n8n-production`, etc.); synthesize into `docs/foundation/infrastructure-state-day-3.md`.

**Driver agents/skills:** Infrastructure Maintainer, `/careful`.

**Deliverable:** Drift-aware picture of shared infra.

#### Day 4 — Operscale Docker compose

**Tasks:** write `infra/docker/operscale-compose.yml`; commit; user pulls + `docker compose up -d`; verify bind mount + Traefik routes `plovera.shop` (placeholder response acceptable).

**Driver agents/skills:** DevOps Automator, `/careful`.

**Deliverable:** Operscale containers running on VPS as placeholders; TLS green.

#### Day 5 — Apply migrations to shared Supabase  *(★3, ★4)*

**Tasks:** ★3 produce `apply-migrations.sh` runbook; user reviews RLS DO-block; user runs apply for 001/002/003/004 sequentially; ★4 the `ALTER PUBLICATION` is confirmed before apply; verify 12 tables exist, RLS locked anon, REPLICA IDENTITY FULL on the five tables, publication includes them.

**Driver agents/skills:** Database Optimizer, Backend Architect, `/careful`.

**Deliverable:** Schema live in shared Supabase; RLS intact; Realtime publication includes our tables.

#### Day 6 — Import OPS_TTS + IMG + RETRY into n8n

**Tasks:** import 3 workflows into n8n via UI, verify reuse of existing VG credentials; seed real-estate test order; curl OPS_TTS_AUDIO; verify 5 mp3 files + audio_status='uploaded' + audio_duration_ms populated.

**Driver agents/skills:** API Tester, `vg-fork-aware`, Test Results Analyzer.

**Deliverable:** Real Chirp 3 HD TTS files generated against new schema.

#### Day 7 — Slack / catch-up

Implementation.md mandates this slack day. Possible uses: fix Days 1-6 issues, eyeball audio, tighten test fixtures. If healthy, slack itself is the deliverable.

#### Day 8 — Import OPS_KEN_BURNS + ASSEMBLY + IMG_PROCESSOR + WATCHDOG

**Tasks:** import 4 more workflows; continue test against fake-order-1 through curl chain `images → ken-burns → assembly`; verify 5 png + 5 mp4 clips + assembled.mp4 with music + transitions; intentionally mismatch one clip's fps to test WF_ASSEMBLY_WATCHDOG, restore.

**Driver agents/skills:** API Tester, Performance Benchmarker, `vg-fork-aware`.

**Deliverable:** assembled.mp4 produced; no captions burned yet.

#### Day 9 — Caption-burn integration  *(★5)*

**Tasks:** ★5 produce `docs/foundation/day-9-caption-burn-decision.md` with symlink-vs-env-var options + Day-3 reconnaissance evidence + recommendation; user picks; if symlink → `ln -sf /data/operscale-production /data/n8n-production/operscale`; trigger caption_burn for fake-order-1; verify final.mp4 + niche-colour ASS + audio sync intact.

**Driver agents/skills:** Infrastructure Maintainer, `/careful`, `vg-fork-aware`.

**Deliverable:** First fully captioned MP4. Render core proven for one niche.

#### Day 10 — End-to-end dry-run + resume test

**Tasks:** single-call curl through OPS_RENDER_PIPELINE (all 8 stages); OPS_QA_CHECK 13/13; run `induce_failure.py kill-n8n-mid-render --interrupt-at-stage ken_burns_scene_3`; verify scenes 1+2 unmodified (mtime), scene 3+ fresh, final.mp4 produced.

**Driver agents/skills:** Test Results Analyzer, `superpowers:test-driven-development`.

**Deliverable:** End-to-end pipeline from one curl; resume invariant verified.

#### Day 11 — 5-niche test matrix

**Tasks:** seed all 5 niches; fire OPS_RENDER_PIPELINE for each; verify niche-correct caption colours (terra/warm-amber for real-estate, sage for education, gold for fashion-ecom, indigo for fintech, cool-trust for health), TTS speaking rates per ADR 0009, OPS_QA_CHECK 13/13 each; `/qa` on the 5 final.mp4s with screenshots.

**Driver agents/skills:** Test Results Analyzer, `niche-aware-prompting`, `/qa`.

**Deliverable:** 5 niche renders all passing; niche styling proven.

#### Day 12 — Failure induction (3 scenarios)

**Tasks:** re-run kill-n8n; induce-caption-burn-timeout (`--timeout-after-sec 30` on a fixture designed to take >30s) — verify clean failure, no zombie ffmpeg, no half-final.mp4; simulate-fal-outage (`--fail-first-n-requests 3`) — verify retries absorbed.

**Driver agents/skills:** Performance Benchmarker, `superpowers:systematic-debugging`.

**Deliverable:** All 3 scenarios verified.

#### Day 13 — Realtime smoke test

**Tasks:** if not done earlier, author `realtime_smoke_test.py`; run client; UPDATE `videos.assembly_status='complete'` from another terminal; verify event arrives within 2s with the changed-column payload (gotcha #4); INSERT into gate_decisions; verify; check no `JWSInvalidSignature` errors (diagnostic only — Q5 forbids rotation).

**Driver agents/skills:** API Tester, `superpowers:verification-before-completion`.

**Deliverable:** Realtime plumbed end-to-end.

#### Day 14 — Foundation verification + go/no-go  *(★6, ★7)*

**Tasks:** re-run all 5 niches end-to-end; finalize `foundation-verification.md` with all artefacts (curl outputs, MP4 URLs, screenshots, Realtime logs); `/qa` on 5 final.mp4s; `/review` against the entire Foundation diff vs `488f089`; ★6 `/freeze` to lock state pre-merge; ★7 final go/no-go decision.

**Driver agents/skills:** Reality Checker, Evidence Collector, `/qa`, `/review`, `/freeze`.

**Deliverable:** Either signed `foundation-verification.md` + green-light to begin Customer-flow brainstorm, or documented gap list + extension plan.

---

## 9. Test fixtures (canonical shape)

`apps/agent/tests/fixtures/scripts/real-estate.json`:

```jsonc
{
  "tier": "pilot",
  "niche": "real-estate",
  "production_register": "OPERSCALE_01_DOCUMENTARY",
  "duration_target_sec": 22,
  "scenes": [
    {
      "scene_number": 1,
      "scene_id": "test-re-001-s1",
      "narration_text": "Three bedrooms. Two views. One decision.",
      "image_prompt": "modern Lagos apartment balcony at golden hour, two leather armchairs, ocean view, cinematic depth",
      "composition_prefix": "wide establishing shot",
      "color_mood": "warm-amber",
      "zoom_direction": "slow_push",
      "transition_to_next": "fade",
      "caption_highlight_word": "decision"
    }
    /* …4 more scenes… */
  ]
}
```

The other 4 niche fixtures differ in `niche`, `color_mood` (sage/gold/indigo/cool-trust), `caption_highlight_word` palette, and `tts_speaking_rate` (which is read off the register config, not a fixture field). All have 5 scenes for constant render time / cost across the niche test matrix.

---

## 10. Foundation success criteria

Foundation **closes on Day 14 if and only if all of:**

1. ✅ All 5 niche renders produce watchable MP4s passing `OPS_QA_CHECK` 13/13 each
2. ✅ All 3 induced failure scenarios produce expected behaviour (no zombies, clean failure markers)
3. ✅ Realtime test client receives events with payload columns within 2s
4. ✅ Caption burn service responds within timeout for happy path
5. ✅ No edits to VG's running workflows or shared infra beyond the named-gate operations
6. ✅ `docs/foundation/foundation-verification.md` is signed and committed
7. ✅ `git diff 488f089..HEAD` shows only intended additions (verified via `/review`)

If any verification fails after Day 14 catch-up: **STOP**. Do not begin Customer-flow brainstorm. Diagnose, fix, re-verify. The cost of building agent + UI + payments on top of a broken render is much higher than another week on Foundation.

---

## 11. Tools, skills, agents — explicit map for Foundation

### Used in Foundation

| Resource | Type | Days |
|---|---|---|
| `superpowers:brainstorming` | skill (primary methodology) | This brainstorm session |
| `superpowers:writing-plans` | skill | After this spec is approved |
| `superpowers:test-driven-development` | skill | 10, 12, 13 |
| `superpowers:systematic-debugging` | skill | 12 |
| `superpowers:verification-before-completion` | skill | 10, 13, 14 |
| `superpowers:requesting-code-review` | skill | At each commit batch |
| `vg-fork-aware` | project skill | 1, 2, 6, 8, 9 |
| `vg-workflow-rebind` | project skill | 2 |
| `prune-commit` | project skill | 1 |
| `niche-aware-prompting` | project skill | 11 |
| `/operscale:workflow-rebind` | slash command | 2 |
| `/careful` | gstack | 3, 4, 5, 9 |
| `/qa` | gstack | 11, 14 |
| `/review` | gstack | 14 |
| `/freeze` | gstack | 14 |
| DevOps Automator agent | agency | 1, 4 |
| Backend Architect agent | agency | 2, 5 |
| Database Optimizer agent | agency | 5 |
| Infrastructure Maintainer agent | agency | 3, 9 |
| Workflow Optimizer agent | agency | 2 |
| API Tester agent | agency | 6, 8, 13 |
| Performance Benchmarker agent | agency | 8, 12 |
| Test Results Analyzer agent | agency | 6, 8, 10, 11 |
| Reality Checker agent | agency | 14 |
| Evidence Collector agent | agency | 14 |

### Forbidden in Foundation (per Q5)

| Resource | Reason |
|---|---|
| `jwt-chain-rotation` skill | No rotations period — would break VG and other apps sharing keys |
| `frontend-design` skill | No UI work in Foundation |
| Any GSD `/gsd-*` command | GSD is deprecated for this project (CLAUDE.md) |
| `git push --force` on shared branches | Forbidden across all phases |
| `--no-verify` on commits | Forbidden across all phases |

### Will activate in later phases (NOT Foundation)

`paystack-integration`, `notion-gate-review`, `langgraph-node`, `gate-reviewer`, `cost-monitor`, `voice-cloning`, `heygen-integration` skills · `/operscale:gate-card`, `/operscale:paystack-verify` slash commands · Frontend Developer, UI Designer, Image Prompt Engineer, Brand Guardian, Content Creator, Security Engineer, Sprint Prioritizer, Feedback Synthesizer, Senior Project Manager, Studio Producer agents.

---

## 12. References

- `CLAUDE.md` — operating rules, the 12 inherited gotchas, build methodology
- `docs/VISION_GRIDAI_FORK_MANUAL.md` — fork strategy, keep-list, pruning, cherry-pick mechanics
- `architecture.md` — system shape, trust boundaries, failure isolation
- `AGENT.md` — state machine the agent will implement in Customer-flow phase (referenced for schema validation only)
- `implementation.md` — original 35-day plan; this spec adapts Days 1-14 for Q1-Q7 outcomes
- `docs/adr/0001-0017` — ADR set; ADRs 0008-0017 govern Foundation's mechanics
- `tier-spec-v2.html` — customer-facing tier promises; will be edited in Customer-flow to align with Q1=A (Chirp 3 HD)
- `skills.md` — index of project skills + agency agents
- `niche-briefs/{real-estate,education,fashion-ecom,fintech,health,restricted}.md` — niche operational stubs
- `_vendored_for_reference/VENDORING.md` — cherry-pick procedure for vendor-vg.sh

---

## 13. What happens after this spec is approved

1. User reviews this written spec; requests changes if needed
2. Once approved, I invoke the `superpowers:writing-plans` skill to convert this design into an executable implementation plan in `docs/superpowers/plans/2026-04-27-foundation-plan.md`
3. The plan will break each Day into atomic tasks with concrete file paths, exact commands, and verification snippets
4. Execution then runs per the cadence locked in Q5=D (hybrid; named gates ★1-★7)
5. Foundation closes Day 14, then we brainstorm Customer-flow from this same spec lineage

---

*Brainstorm session: 2026-04-27. Approved sections 1-7 inline. Self-review pending.*
