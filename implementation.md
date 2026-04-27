# Implementation Plan

> The 35-day day-by-day execution plan to ship tier-1 of Operscale Video Ads.
> Aligned with the fork manual §15 and the launch budget's 90-day cashflow timeline.

**Read alongside:** `docs/VISION_GRIDAI_FORK_MANUAL.md` §15 and §16, `launch-budget.html`, `AGENT.md`.

---

## Mental model — three phases

```
Phase 0 (Days 1–14): Foundation
  - Repo setup, prune commit, infrastructure inheritance
  - Apply migrations to a NEW Supabase database
  - Import + verify all kept VG workflows
  - End-to-end render test: fake order → real video

Phase 1 (Days 15–28): Customer flow
  - Marketing site + intake form
  - Paystack integration (test mode)
  - LangGraph agent skeleton
  - Notion gate review
  - First end-to-end real-payment test order

Phase 2 (Days 29–35): Production polish
  - Cost monitoring, rate limits, lint rules
  - Internal QA round
  - Switch Paystack to live
  - Smoke test, then ship
```

After Day 35, soft launch begins per the launch budget's Phase 1 timeline.

---

## Daily plan

### Day 1 — Foundation: repo

**Tasks:**
- Create new GitHub repo `akinwunmi-akinrimisi/operscale-video` (private, see ADR 0014)
- Vendored snapshot of Vision GridAI per fork manual §2
- Initial scaffolding commit
- Imported snapshot commit (with SHA noted)
- Push to GitHub

**Deliverable:** Empty-but-vendored repo with two commits on main.

### Day 2 — Foundation: Day 1 Prune Commit

**Tasks:**
- Execute the prune commit per fork manual §3.1 (delete YouTube/social/long-form/intelligence-layer files)
- Move VG migrations to `_vendored_for_reference/`
- Commit and push

**Deliverable:** Repo at expected post-prune state. ~60% file reduction visible in `git diff`.

### Day 3 — Foundation: VPS reconnaissance

**Tasks:**
- SSH to the Hostinger VPS
- Map every existing VG file path: `/docker/n8n/`, `/docker/supabase/`, `/data/n8n-production/`, `/opt/dashboard/`, `/opt/caption-burn/`
- Verify VG containers are healthy: `docker ps | grep -E 'n8n|supabase'`
- Verify caption burn service is running: `systemctl status caption-burn.service`
- Document any unexpected drift from VG's docs

**Deliverable:** A short `infrastructure-state-day-3.md` notes file with what's actually on the VPS vs what the VG docs say.

### Day 4 — Foundation: Operscale containers

**Tasks:**
- Create `/docker/operscale-video-ads/docker-compose.yml` per architecture.md
- Create `/docker/operscale-video-ads/docker-compose.override.yml` with secrets (chmod 600, NOT in git)
- Set up `/data/operscale-production/` directory
- Add Operscale-specific bind mount to `/docker/n8n/docker-compose.override.yml` (`/data/operscale-production:/tmp/operscale-production`)
- Restart n8n stack: `cd /docker/n8n && docker compose up -d`
- Verify: `docker exec n8n-n8n-1 ls /tmp/operscale-production`

**Deliverable:** Docker compose ready for Operscale containers; n8n can write to our scratch dir.

### Day 5 — Foundation: Supabase migration

**Tasks:**
- Write `supabase/migrations/001_initial.sql` per fork manual §5.2
- Write `supabase/migrations/002_seed_registers.sql` (the 2 seeded registers)
- Write `supabase/migrations/003_seed_prompt_configs.sql` (5 niches × 4 prompt types = 20 rows)
- Apply migrations: `docker exec -i supabase-db-1 psql -U postgres -f /tmp/001_initial.sql` and so on
- Verify all RLS policies: anon role queries return 0 rows on every table
- Verify service_role queries succeed
- Verify `REPLICA IDENTITY FULL` set on `orders`, `videos`, `scenes`, `production_log`

**Deliverable:** Production Supabase instance has our schema, RLS-locked.

### Day 6 — Foundation: import workflows, part 1 (TTS + images)

**Tasks:**
- Import `WF_TTS_AUDIO.json` from `/repo/workflows/`
- Rename to `OPS_TTS_AUDIO` in n8n UI
- Update webhook path: `/webhook/operscale/production/tts`
- Update SQL queries inside the workflow: `topic_id` → `video_id`, `topics` → `videos` for FK references
- Import `WF_IMAGE_GENERATION.json`, rename `OPS_IMAGE_GENERATION`, force `aspect_ratio = portrait_9_16` always
- Import `WF_RETRY_WRAPPER.json` exactly as-is (rename only); this is shared between both products

**Test plan:**
- Insert a fake `videos` row + 3 fake `scenes` rows in the new Supabase
- POST to `/webhook/operscale/production/tts` with the video ID
- Verify 3 MP3 files appear in `/data/operscale-production/<order_id>/audio/`
- Verify `scenes.audio_status` flips to `uploaded`
- Verify `scenes.audio_duration_ms` is populated

**Deliverable:** Real TTS audio generation against our new schema works end-to-end.

### Day 7 — Foundation: catch-up day

Fix anything broken in Days 1–6. Don't rush ahead.

### Day 8 — Foundation: import workflows, part 2 (Ken Burns + assembly)

**Tasks:**
- Import `WF_SCENE_IMAGE_PROCESSOR`, `WF_KEN_BURNS`, `WF_CAPTIONS_ASSEMBLY`, `WF_ASSEMBLY_WATCHDOG`
- Rename all with `OPS_` prefix
- Update webhook paths to `/webhook/operscale/...`
- Update SQL: `topic_id` → `video_id`, `topics` → `videos`

**Test plan:**
- Continue the fake order from Day 6
- POST to `/webhook/operscale/production/images` — verify all images appear
- POST to `/webhook/operscale/production/ken-burns` — verify per-scene clips appear with motion + colour grade
- POST to `/webhook/operscale/production/assembly` — verify final concatenated video appears
- Verify the post-concat duration drift check works (intentionally break a clip's fps to test)

**Deliverable:** Real video file produced end-to-end from a fake order.

### Day 9 — Foundation: caption burn integration

**Tasks:**
- Decide path-collision strategy per fork manual §8.3 (env vars OR symlink)
- If env-var path: edit `caption_burn_service.py` to read `CB_HOST_BASE` and `CB_CONTAINER_BASE` from env
- If symlink path: `ln -sf /data/operscale-production /data/n8n-production/operscale`
- Test: trigger `OPS_CAPTIONS_ASSEMBLY` for the fake order, verify caption burn fires and produces captioned MP4

**Deliverable:** Captioned final video for fake order, atomically swapped with `_no_captions.mp4` backup preserved.

### Day 10 — Foundation: end-to-end render dry run

**Tasks:**
- Compose all the workflows into a single trigger chain via `WF_SHORTS_PRODUCE` adaptation (renamed `OPS_RENDER_PIPELINE`)
- POST to one webhook → all stages fire in sequence
- Verify resume behaviour: kill n8n container mid-render, restart, verify pipeline picks up where it left off

**Deliverable:** One-call render pipeline. Reproducible from a single curl invocation.

### Day 11 — Foundation: register + niche styling

**Tasks:**
- Verify `OPS_TTS_AUDIO` correctly reads `production_registers.config.tts_voice` (defaults to Chirp 3 HD `en-NG-Standard-A`)
- Verify `OPS_IMAGE_GENERATION` correctly assembles prompt from `composition_prefix + scene_subject + style_dna + register_anchors`
- Verify `OPS_CAPTIONS_ASSEMBLY` correctly applies niche colour to emphasis words (extend `generate_kinetic_ass.py` per fork manual §8.7)

**Deliverable:** Same script renders differently across our 5 niches with niche-correct kinetic caption colours.

### Day 12 — Foundation: resume scenarios

Test the three failure scenarios from fork manual §9.4:
1. Kill n8n mid-TTS, restart, verify resume from where it stopped
2. Simulate caption burn 3-hour timeout
3. Simulate fal.ai outage during image generation

**Deliverable:** Documented test results for each scenario.

### Day 13 — Foundation: Realtime check

**Tasks:**
- Wire up a tiny test Python script that subscribes to `videos` table updates via Supabase Realtime
- Trigger a render
- Verify UPDATE events arrive with the changed columns (this validates `REPLICA IDENTITY FULL`)
- Verify JWT chain works (no `JWSInvalidSignature` errors)

**Deliverable:** Realtime subscription works end-to-end. Necessary precondition for Phase 1.

### Day 14 — Foundation: catch-up + go/no-go

Fix anything still broken from Phase 0. Run a full end-to-end manual order with a real customer brief. Decide go/no-go for Phase 1.

If anything from Days 1–13 isn't working solidly, **do not proceed to Phase 1.** The customer flow on top of broken render is a worse outcome than a 1-week delay.

---

### Day 15 — Customer flow: marketing site shell

**Tasks:**
- Initialise Next.js 15 app in `apps/web/`
- Configure Tailwind with our design tokens
- Set up Traefik labels in `docker-compose.yml` for `plovera.shop` route
- Deploy a "coming soon" landing page

**Deliverable:** `plovera.shop` resolves with valid TLS to a placeholder.

### Day 16 — Customer flow: intake form

**Tasks:**
- Build `/start` route with the 15-question multi-step form per `docs/specs/intake-form.md`
- Implement save-token resume mechanism
- POST handler at `/api/intake/submit` writes to `briefs` and `customers`

**Deliverable:** A real human can fill out the form, see all 15 questions, refresh the page mid-form, and resume from email link.

### Day 17 — Customer flow: Paystack integration (test mode)

**Tasks:**
- Set up Paystack test account
- Build `/api/webhooks/paystack` endpoint with HMAC-SHA512 signature verification per fork manual §11.3
- Test with Paystack's test cards
- Insert `payments` row on signature-verified webhook

**Deliverable:** A test payment ₦100 card transaction triggers a `payments` row insert with `status='paid'`.

### Day 18 — Customer flow: WF_OPS_INTAKE_RECEIVE + WF_OPS_PAYSTACK_WEBHOOK

**Tasks:**
- Write `WF_OPS_INTAKE_RECEIVE.json` in n8n: takes the brief insert, fires email + WhatsApp acknowledgement
- Write `WF_OPS_PAYSTACK_WEBHOOK.json`: receives forwarded webhook, transitions `orders.pipeline_stage = 'paid'`
- Test both end-to-end

**Deliverable:** Form submit → ack arrives. Test payment → order transitions to paid.

### Day 19 — Customer flow: LangGraph agent skeleton

**Tasks:**
- Set up Python 3.11 environment in `apps/agent/`
- Implement state machine skeleton per `AGENT.md`
- Implement `brief_received` and `gate_0_review` states
- Set up Supabase Realtime listener
- Deploy to `operscale-agent` container

**Deliverable:** Agent process runs, listens for new briefs, transitions to `gate_0_review` and pauses correctly.

### Day 20 — Customer flow: WF_OPS_QUOTE_DELIVER

**Tasks:**
- Implement angle generation in agent (`generating_angles` state)
- Write `WF_OPS_QUOTE_DELIVER.json` — renders rich quote message, attaches Paystack link, sends via Resend + Evolution API
- Test against a real Akinwunmi-as-customer brief

**Deliverable:** Submit a real brief → 3 angles generate → quote email + WhatsApp arrive with Paystack link.

### Day 21 — Customer flow: catch-up day

Fix anything broken in Days 15–20.

### Day 22 — Customer flow: Notion gate review setup

**Tasks:**
- Create Notion workspace (or use Akinwunmi's personal Notion)
- Set up the Gate Review database per `docs/specs/notion-gate-review.md`
- Configure Notion automation to POST to `/webhook/operscale/gate/resume` on row update

**Deliverable:** Manually creating a card in Notion → editing the decision field → POSTs to our webhook.

### Day 23 — Customer flow: WF_OPS_GATE_NOTIFY + WF_OPS_GATE_RESUME

**Tasks:**
- Write `WF_OPS_GATE_NOTIFY.json` — Notion API call to insert a card with the relevant artefacts (brief, angles, script, render URL)
- Write `WF_OPS_GATE_RESUME.json` — receives the Notion automation POST, writes to `gate_decisions` table
- Wire agent's gate states to call `WF_OPS_GATE_NOTIFY` and listen for `gate_decisions` Realtime updates

**Deliverable:** Agent fires Gate 0 → Notion card appears → founder approves on phone → agent transitions to `generating_angles` automatically.

### Day 24 — Customer flow: script generation node

**Tasks:**
- Implement `generating_script` state in agent: takes approved angle, calls Claude Opus 4.7 with full brief + niche-brief context
- Writes `videos.script_json` and individual `scenes` rows
- Logs to `llm_calls`

**Deliverable:** Approve an angle in Notion → agent generates script → script lands in DB → Gate 2 card pushed.

### Day 25 — Customer flow: WF_OPS_DELIVERY_FANOUT

**Tasks:**
- Write `WF_OPS_DELIVERY_FANOUT.json` — generates 7-day signed Supabase Storage URL, sends Resend email, sends Evolution API WhatsApp
- Schedule the 7-day post-delivery follow-up via n8n cron

**Deliverable:** A delivered render fires email + WhatsApp with signed URL the customer can click.

### Day 26 — Customer flow: end-to-end real-payment test

**Tasks:**
- Submit a real test brief with Akinwunmi's email + WhatsApp
- Pay with Paystack test card
- Watch the pipeline run through all 4 gates
- Verify final video lands in inbox

**Deliverable:** Documented end-to-end run, time-tracked stage by stage.

### Day 27 — Customer flow: 3 more end-to-end runs

Run 3 more orders with internal team members. Vary the niche and tier. Note any UX friction or bugs.

### Day 28 — Customer flow: catch-up day

Fix everything noted in Day 26-27.

---

### Day 29 — Production polish: monitoring

**Tasks:**
- Set up cost-per-order tracking via `llm_calls` aggregation
- Configure `WF_OPS_SUPERVISOR` cron (every 30 min): scan for stuck orders, alert if `pipeline_stage = 'failed'` for >1 hour
- WhatsApp escalation to founder when SLA approaches breach (T-12h on tier delivery time)

**Deliverable:** A simple SQL dashboard query that gives founder current state of all in-flight orders with cost and SLA progress.

### Day 30 — Production polish: refund flow

**Tasks:**
- Test `WF_OPS_REFUND` end-to-end with Paystack test card
- Verify customer receives refund notification email
- Verify `payments.status = 'refunded'` and `orders.pipeline_stage = 'refunded'`

**Deliverable:** A real refund completes within 5 minutes of founder approving the refund decision in Notion.

### Day 31 — Production polish: rate limits + error pages

**Tasks:**
- Add rate-limit middleware to `/api/intake/submit` (10/IP/hour) and `/api/webhooks/paystack` (no limit needed but signature verification rejects abuse)
- Implement 404 + 500 error pages with branded design
- Add a `/status` page at the marketing site that reports system health

**Deliverable:** Marketing site survives basic adversarial probing without 500s or rate-bypass.

### Day 32 — Production polish: lint rules

**Tasks:**
- Port VG's `tools/lint_n8n_workflows.py` to our repo
- Configure `AUTH-01` (Authorization headers must start with `=` if expression) and `CRED-01` (no inline credentials)
- Run linter on all our workflow JSONs
- Add to GitHub Actions CI

**Deliverable:** PRs that introduce broken auth headers or inline credentials are blocked at CI.

### Day 33 — Production polish: internal QA

**Tasks:**
- 5 humans (Akinwunmi + 4 friends/team) fill out the intake form on different niches
- Note every UX wrinkle, copy that doesn't read well, form validation gap
- Triage: must-fix vs nice-to-have

**Deliverable:** A `qa-day-33.md` notes file with prioritised issues. Must-fix items get fixed Day 33-34.

### Day 34 — Production polish: live Paystack switch

**Tasks:**
- Submit Paystack live-mode application (if not already done)
- Once approved, swap test keys for live keys in env
- Smoke test with a real ₦100 transaction (refund yourself afterward)

**Deliverable:** Live Paystack working. ₦100 test transaction successful.

### Day 35 — Production polish: Definition of Done check

**Tasks:**
- Walk through every item in fork manual §16's 26-item checklist
- For each unchecked box, decide: fix today or document as known-deficiency

**Deliverable:** Either all 26 boxes checked → ready for soft launch. Or documented gap list with mitigation plan.

If all 26 boxes are checked, soft launch begins.

---

## Soft launch (Day 36+)

Per the launch budget Phase 1 timeline:
- Days 36–60: Content bank posting, friends-and-family beta orders only
- Days 61–90: Ad spend phase, real customer acquisition

If first paid customer doesn't land by Day 90, see fork manual §15 + launch budget §kill-criterion.

---

## Roles & ownership

For a lean team (per launch budget):

| Person | Owner of |
|---|---|
| Akinwunmi (founder, unpaid) | Strategy, Notion gate reviews, prompts, customer relationships, sales, content posting |
| Senior full-stack engineer | Render core integration (Days 5–14), LangGraph agent (Days 19–24), production hardening (Days 29–35) |
| Junior engineer / content creator | Marketing site (Days 15–17), intake form (Day 16), 90-video content bank in parallel |
| Content creator (3 days/week, optional) | Posts content bank, manages IG/TikTok during build |

---

## Critical dependencies

A red mark means this blocks downstream work. Track these:

🔴 **Day 5 migration must apply cleanly.** If RLS isn't right or REPLICA IDENTITY isn't set, no Realtime works = no agent works.

🔴 **Day 9 caption burn must work.** This is the single most complex inheritance. If we can't get our path through it correctly, every render is broken.

🔴 **Day 13 Realtime must work.** Without Realtime, the agent can't react to gate decisions. Notion gate review breaks.

🔴 **Day 17 Paystack signature verification must be correct.** Skipping signature check = anyone can fake a payment.

🟡 **Day 22 Notion automation reliability.** If Notion's automation engine is flaky, gate review degrades. Backup: founder manually POSTs to webhook from a phone shortcut.

🟡 **Day 26 first end-to-end run.** This is when latent bugs surface. Plan 2 catch-up days minimum after.

---

## What we're not building in Phase 0/1/2

Per the audit in fork manual §13 and tier spec v2:

- **Multi-character dialogue UI.** Phase 3+ (post-Day 90).
- **Custom avatar from photo.** Phase 3+ — the Creative Pod tier offers it but the UI/consent flow gets built later.
- **Founder dashboard (custom React).** Notion-based gate review for v1; revisit at scale.
- **Ad performance tracking.** Out of scope for v1.
- **Analytics for founder.** Simple SQL queries against the DB suffice for first 90 days.
- **Customer self-service portal.** No — see ADR 0005.

These deferrals are deliberate. They are documented to prevent scope creep during the Day 1–35 push.
