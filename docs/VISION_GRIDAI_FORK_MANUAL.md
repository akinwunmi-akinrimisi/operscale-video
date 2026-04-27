# Operscale Video Ads — Vision GridAI Fork Build Manual

> **Audience:** The senior engineer who will execute the fork.
> **Premise:** Vision GridAI is a working, battle-tested 235-commit production system. We are not rebuilding its render pipeline from scratch — we are forking it, pruning ~60% of the surface area, and bolting a customer-facing intake/payment/delivery flow onto the remaining ~40%.
> **Time saved by following this doc faithfully:** approximately 6–10 weeks of trial-and-error.
> **Source repo:** https://github.com/akinwunmi-akinrimisi/vision-gridai-platform · live docs at https://akinwunmi-akinrimisi.github.io/vision-gridai-platform/

---

## 0. Reading order — do not skip

This document is sequenced. Read it top to bottom **once** before touching any code. The early sections establish the mental model that makes the later sections obvious.

1. §1 — The two products (mental model)
2. §2 — Repository creation (clean checkout strategy)
3. §3 — Day 1 Prune Commit (the most important commit you'll write)
4. §4 — VPS environment & infrastructure inheritance
5. §5 — Supabase schema fork (database first, always)
6. §6 — n8n workflows: inventory and disposition
7. §7 — The render core — what to clone byte-for-byte
8. §8 — Caption burn service — host-side, untouched
9. §9 — Resume/retry guarantees you must preserve
10. §10 — Auth, secrets, and the JWT chain
11. §11 — What you build new (intake → payment → delivery)
12. §12 — LangGraph agent shape
13. §13 — Cost calculator + tier mapping
14. §14 — Inherited gotchas — read this twice
15. §15 — Day-by-day execution plan
16. §16 — Definition of Done — tier 1 ship

A senior engineer who skims this and starts coding from §15 will rebuild bugs that took the original team weeks to find. **Read in order.**

---

## 1. The two products — what we're forking and what we're not

Vision GridAI is **a YouTube channel factory**. It exists to:
- Take a niche as input (e.g. "credit card optimisation").
- Research it, generate 25 topics, write 19,000-word scripts, produce 2-hour 16:9 documentary videos plus 20 viral 9:16 shorts each.
- Auto-publish to YouTube + TikTok + Instagram.
- Pull analytics and feed them back into a 16-table intelligence layer.

Operscale Video Ads is **a customer-facing ad agency**. It exists to:
- Take a paying SMB customer's brief as input via a marketing-site form.
- Take payment via Paystack.
- Generate one (Pilot/Standard) or three (Creative Pod) 9:16 vertical ad videos of 15-60 seconds.
- Deliver the finished MP4 to the customer via email + WhatsApp.
- That's it. We don't post to platforms, we don't run analytics, we don't track audience comments.

The Venn diagram intersection is **"the renderer that turns a script into a 9:16 video with kinetic captions and warm cinema-grade colour."** That intersection is most of what makes Vision GridAI valuable to fork. Everything around it — niche research, topic generation, 3-pass long-form scripting, social publishing, the intelligence layer — is wrong-shape for our product and will be deleted in §3.

**Mental model: imagine a kitchen.** Vision GridAI's kitchen has 78 appliances. We need about 26 of them. Some we'll use untouched (the FFmpeg renderer, the caption burn service, the TTS workflow). Some we'll repurpose (the dashboard becomes founder-facing, the schema gains customer/payment tables, the LLM workflow handles 1-pass ad scripts instead of 3-pass long-form). The rest — the social media publisher, the YouTube uploader, the topic discovery engine — get demolished.

---

## 2. Repository creation — clean checkout strategy

### Step 2.1 — Create the new GitHub repo

```bash
# On your machine:
gh repo create operscale/<product-name>-platform --private --description "Operscale AI video ads platform"
cd ~/code
gh repo clone operscale/<product-name>-platform operscale-video-ads
cd operscale-video-ads
```

(Substitute `<product-name>` for the brand name once locked. Per the v2 tier spec discussion, recommended candidates are `sello`, `layi`, `reelcraft`. `vision-gridai-platform` had ~88% JavaScript / 7.7% Python / 3.7% Shell content distribution; expect ours to be similar.)

### Step 2.2 — Initial commit: your own scaffolding only

The first commit on `main` should be **your own** scaffolding files: `README.md`, `LICENSE` (private/proprietary), `.gitignore`, `CLAUDE.md`. Do **not** start by importing Vision GridAI files — see Step 2.3 for why.

```bash
git checkout -b main
echo "# Operscale Video Ads" > README.md
git add README.md .gitignore
git commit -m "chore: initial scaffold"
git push origin main
```

### Step 2.3 — Bring in Vision GridAI as a vendored snapshot, not a fork

Do **not** use `git fork` or `git clone --mirror`. Those carry Vision GridAI's commit history, branches, tags, and authorship into your repo, which is wrong on three axes: (a) credit attribution, (b) license clarity, (c) noise — Vision GridAI's 235 commits include 30+ debugging-disaster-recovery sessions you don't want diffed against your work.

Instead, vendor a snapshot:

```bash
# In a temp directory:
cd /tmp
git clone --depth 1 https://github.com/akinwunmi-akinrimisi/vision-gridai-platform vgai-snapshot
cd vgai-snapshot
SHA=$(git rev-parse HEAD)
echo "Vision GridAI snapshot taken at SHA: $SHA"
# Note this SHA — you'll commit it as a marker.

# Strip Vision GridAI's git history:
rm -rf .git
rm -rf .planning .claude    # personal/working files of the original author

# Copy into our repo:
cp -r . ~/code/operscale-video-ads/
cd ~/code/operscale-video-ads
```

### Step 2.4 — The "imported" commit

```bash
git add -A
git commit -m "chore: import Vision GridAI snapshot at SHA $SHA

This commit is the entire Vision GridAI repository at the snapshot SHA above,
imported as our starting point. The next commit (the Prune Commit) will delete
~60% of this surface area. After that point, no further code from Vision GridAI
will be imported — divergence begins.

Source: https://github.com/akinwunmi-akinrimisi/vision-gridai-platform
SHA at snapshot: $SHA"
git push origin main
```

This commit gives you a clean blame trail: anything that's still in the repo three months from now and dates back to this commit is "inherited untouched"; anything from the next commit forward is "ours."

---

## 3. Day 1 Prune Commit — the most important commit you'll write

This is a single commit that deletes everything Vision GridAI has that we do not need. Do not trickle-delete; do it as one focused commit. Trickle-deletion leaves ambiguous in-between states where some workflows reference deleted dependencies, which generates phantom errors during testing.

### 3.1 — Files and directories to delete entirely

```bash
# Long-form-only Vision GridAI artefacts (we don't make 2-hour videos):
rm -rf video_production/REGISTER_*.md           # 2hr documentary register SOPs (we keep registers conceptually but redefine)
rm -rf image_creation_guidelines_prompts/       # YouTube-thumbnail-tuned prompt library
rm -f generate_thumbnails.py                    # YouTube thumbnail compositor
rm -f thumbnail_description.md
rm -f Dashboard_Implementation_Plan.md          # Vision GridAI's dashboard plan, not ours
rm -f VisionGridAI_Dashboard_Specification.md
rm -f VisionGridAI_Platform_Agent.md            # Replaced by our AGENT.md
rm -f Kinetic_Typography_Captioning_System_v2.0.md  # Concept lives in our docs

# YouTube + social workflows (we don't publish to platforms):
rm -f workflows/WF_YOUTUBE_UPLOAD.json
rm -f workflows/WF_VIDEO_METADATA.json
rm -f workflows/WF_SOCIAL_POSTER.json
rm -f workflows/WF_SOCIAL_ANALYTICS.json
rm -f workflows/WF_SCHEDULE_PUBLISHER.json
rm -f workflows/WF_WEBHOOK_PUBLISH.json
rm -f workflows/WF_INSTAGRAM*.json
rm -f workflows/WF_TIKTOK*.json
rm -f workflows/WF_YT_*.json
rm -f workflows/WF_YOUTUBE_DISCOVERY.json
rm -f workflows/WF_YOUTUBE_ANALYZE.json

# Niche-research / topic-generation engine (we have 5 fixed niches with static briefs):
rm -f workflows/WF_NICHE_RESEARCH.json
rm -f workflows/WF_TOPIC_INTELLIGENCE.json
rm -f workflows/WF_TOPICS_GENERATE.json
rm -f workflows/WF_TOPICS_ACTION.json
rm -f workflows/WF_RESEARCH_*.json
rm -f workflows/WF_KEYWORD_SCAN.json
rm -f workflows/WF_DAILY_IDEAS.json
rm -f workflows/WF_DISCOVER_COMPETITORS.json
rm -f workflows/WF_COMPETITOR_*.json
rm -f workflows/WF_CHANNEL_*.json
rm -f workflows/WF_NICHE_HEALTH.json
rm -f workflows/WF_NICHE_VIABILITY.json
rm -f workflows/WF_CREATE_PROJECT_FROM_ANALYSIS.json
rm -f workflows/WF_PROJECT_CREATE.json

# 3-pass long-form script generator (we use single-pass for short ad scripts):
rm -f workflows/WF_SCRIPT_GENERATE.json
rm -f workflows/WF_SCRIPT_PASS.json
rm -f workflows/WF_SCRIPT_APPROVE.json
rm -f workflows/WF_SCRIPT_REJECT.json
rm -f workflows/WF_HOOK_ANALYZER.json

# Long-form analytics + intelligence layer (we don't track post-publish):
rm -f workflows/WF_ANALYTICS_CRON.json
rm -f workflows/WF_COMMENTS_SYNC.json
rm -f workflows/WF_COMMENT_ANALYZE.json
rm -f workflows/WF_AUDIENCE_INTELLIGENCE.json
rm -f workflows/WF_AI_COACH.json
rm -f workflows/WF_AB_TEST_ROTATE.json
rm -f workflows/WF_CTR_OPTIMIZE.json
rm -f workflows/WF_OUTLIER_SCORE.json
rm -f workflows/WF_SEO_SCORE.json
rm -f workflows/WF_PPS_*.json
rm -f workflows/WF_PREDICT_PERFORMANCE.json
rm -f workflows/WF_REVENUE_ATTRIBUTION.json
rm -f workflows/WF_RPM_CLASSIFY.json
rm -f workflows/WF_THUMBNAIL_SCORE.json
rm -f workflows/WF_VIRAL_TAG.json
rm -f workflows/WF_STYLE_DNA.json
rm -f workflows/WF_SUPERVISOR.json   # We'll write our own simpler one

# Australia overlay (region-specific to Vision GridAI's roadmap, not ours):
rm -f workflows/WF_COUNTRY_ROUTER.json
rm -f workflows/WF_DEMONETIZATION_AUDIT.json
rm -f workflows/WF_COACH_REPORT.json
rm -f workflows/WF_COMPETITOR_ANALYZER.json
rm -rf docs-site/au/    # if checked in

# Cost calculator workflow specific to long-form 172-scene I2V ratio gate:
# (Keep the concept, but our cost calc is much simpler — see §13.)
# rm -f workflows/WF_COST_CALC*.json     # Only if such a file exists

# Documentation site (it's Vision GridAI's, we'll write our own later):
rm -rf docs-site/    # If you cloned the GitHub Pages source
```

### 3.2 — Migrations to remove

Vision GridAI has migrations 001–032 plus several uncommitted migrations applied directly to the live VPS. We will **not** copy migrations forward. Instead:

```bash
# Move all existing migrations to a reference folder (don't delete — we want them readable):
mkdir -p _vendored_for_reference/supabase-migrations-vgai
mv supabase/migrations/*.sql _vendored_for_reference/supabase-migrations-vgai/

# We'll write our own clean migration history in §5 below.
```

### 3.3 — Files to keep but mark for adaptation

Add a top-of-file comment block to these so the next person to touch them knows they were imported and need work:

- `execution/caption_burn_service.py` — keep untouched, see §8.
- `execution/generate_kinetic_ass.py` — keep untouched, see §8.
- `execution/burn_captions.sh` — keep, minor path tweak per §8.
- `execution/whisper_align.py` — keep untouched.
- `workflows/WF_TTS_AUDIO.json` — keep, will rebind FK (§7).
- `workflows/WF_IMAGE_GENERATION.json` — keep, force aspect ratio to 9:16 (§7).
- `workflows/WF_KEN_BURNS.json` — keep untouched.
- `workflows/WF_CAPTIONS_ASSEMBLY.json` — keep, this is the crown jewel (§7).
- `workflows/WF_SHORTS_PRODUCE.json` — keep, this is our primary render workflow (§7).
- `workflows/WF_SEEDANCE_I2V.json` — keep, gated to Creative Pod tier only.
- `workflows/WF_SCENE_CLASSIFY.json` — keep, simplified.
- `workflows/WF_SCENE_*_PROCESSOR.json` — keep, scene-level workers.
- `workflows/WF_RETRY_WRAPPER.json` — **keep absolutely untouched.** This is non-negotiable. See §9.
- `workflows/WF_ENDCARD.json` — keep, we use end card on Standard+.
- `workflows/WF_THUMBNAIL_GENERATE.json` — keep, used for our case-study OG images.
- `workflows/WF_MUSIC_GENERATE.json` — keep, used Standard+.
- `workflows/WF_DASHBOARD_READ.json` — keep, founder dashboard reads through it.
- `workflows/WF_WEBHOOK_PRODUCTION.json` — keep, simplified (drop YouTube routes).
- `workflows/WF_WEBHOOK_STATUS.json` — keep as health-check.
- `workflows/WF_SHORTS_ANALYZE.json` — **delete**, we don't slice from a parent video.
- `workflows/WF_QA_CHECK.json` — keep.
- `workflows/WF_PLATFORM_METADATA.json` — delete (YouTube/TikTok/IG metadata).
- `workflows/WF_ASSEMBLY_WATCHDOG.json` — keep, critical for monitoring stuck FFmpeg.
- `infra/` — keep, adapt per §4.

### 3.4 — Commit the prune

```bash
git add -A
git commit -m "feat: prune Vision GridAI surface to ad-rendering core

Removes:
- All long-form (2hr documentary) production assets
- All YouTube + TikTok + Instagram publishing workflows
- All niche research / topic discovery / 3-pass scripting
- All post-publish analytics + intelligence layer
- Australia overlay
- Vision GridAI's own dashboard implementation plan + agent doc

Keeps untouched (the render core):
- WF_TTS_AUDIO, WF_IMAGE_GENERATION, WF_SCENE_*_PROCESSOR
- WF_KEN_BURNS, WF_CAPTIONS_ASSEMBLY, WF_SHORTS_PRODUCE
- WF_RETRY_WRAPPER (sub-workflow, used by all external API calls)
- execution/caption_burn_service.py + generate_kinetic_ass.py + burn_captions.sh
- WF_DASHBOARD_READ, WF_WEBHOOK_STATUS

Migrations moved to _vendored_for_reference/ — clean migration history begins
in next commit (see docs/VISION_GRIDAI_FORK_MANUAL.md §5).

Net change: ~60% file count reduction. The remaining files are the kitchen
appliances we'll actually use to cook the customer's order."
git push origin main
```

After this commit, **do not pull more files from Vision GridAI**. Anything you discover later that you wish you'd kept can be cherry-picked manually with full context, not bulk-imported.

---

## 4. VPS environment & infrastructure inheritance

Vision GridAI runs on a single Hostinger KVM VPS. **You are sharing this same VPS** for the launch period (per ADR 0004). You are not provisioning new infrastructure; you are running your containers alongside Vision GridAI's.

### 4.1 — Filesystem layout you inherit

```
/docker/
├── n8n/                            # Vision GridAI's n8n stack (don't touch)
│   ├── docker-compose.yml
│   ├── docker-compose.override.yml # has DASHBOARD_API_TOKEN, JWT keys, etc.
│   └── (n8n-managed volumes)
├── supabase/                       # Shared Supabase stack
│   ├── docker-compose.yml
│   ├── .env                        # JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY
│   ├── .env.bak.YYYY-MM-DD         # Pre-rotation backups
│   └── supabase/
│       ├── kong.yml                # Kong consumer keys
│       └── kong.yml.bak.YYYY-MM-DD
└── operscale-video-ads/            # ← NEW, ours
    ├── docker-compose.yml
    └── docker-compose.override.yml

/data/
├── n8n-production/                 # Vision GridAI scratch
└── operscale-production/           # ← NEW, our scratch directory
                                    # /data/operscale-production/<order_id>/
                                    # mirrors VG's per-topic structure

/opt/
├── dashboard/                      # Vision GridAI's React dashboard
├── caption-burn/                   # SHARED with VG. caption_burn_service.py on :9998
│   ├── caption_burn_service.py
│   └── caption-burn.service        # systemd unit
└── operscale/                      # ← NEW, our deployable assets
    ├── web/                        # Static Next.js export (or proxied via Traefik)
    └── (other operscale-only paths)

/root/
├── keys_new.env                    # Vision GridAI's live keys (do not modify)
├── operscale_keys.env              # ← NEW, our keys (chmod 600)
└── backups/
    ├── jwt-fix-YYYYMMDDTHHMMSSZ/   # VG rotations
    └── operscale-deploy-YYYYMMDDTHHMMSSZ/  # ← NEW, our rotations
```

### 4.2 — SSH access

```bash
# Same key as Vision GridAI (this is Akinwunmi's machine):
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
```

### 4.3 — Domain mapping

Vision GridAI uses three hostnames:
- `n8n.srv1297445.hstgr.cloud` — n8n editor + webhook endpoints
- `supabase.operscale.cloud` — Kong → PostgREST + Realtime
- `dashboard.operscale.cloud` — VG's React dashboard

We will add (per ADR 0012):
- `<product-domain>.com` — public marketing site + customer flow
- `app.<product-domain>.com` — founder gate-review console (later, optional)
- The shared n8n endpoint serves our webhooks too — we just create new paths like `/webhook/operscale/intake`

DNS is managed in Hostinger's panel. Add A records pointing at the same VPS IP as `dashboard.operscale.cloud` resolves to.

### 4.4 — Containers we run

We add **two new** Docker services on the same VPS (no new infrastructure):

```yaml
# /docker/operscale-video-ads/docker-compose.yml
services:
  web:
    image: ghcr.io/operscale/<product-name>-web:latest
    container_name: operscale-web
    restart: unless-stopped
    networks:
      - traefik
      - operscale
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.operscale-web.rule=Host(`<product-domain>.com`)"
      - "traefik.http.routers.operscale-web.tls=true"
      - "traefik.http.routers.operscale-web.tls.certresolver=letsencrypt"
    environment:
      - NODE_ENV=production
      - SUPABASE_URL=https://supabase.operscale.cloud
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
      - PAYSTACK_PUBLIC_KEY=${PAYSTACK_PUBLIC_KEY}

  agent:
    image: ghcr.io/operscale/<product-name>-agent:latest
    container_name: operscale-agent
    restart: unless-stopped
    networks:
      - traefik
      - operscale
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - SUPABASE_URL=https://supabase.operscale.cloud
      - SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
      - N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook
      - DASHBOARD_API_TOKEN=${DASHBOARD_API_TOKEN}
      - PAYSTACK_SECRET_KEY=${PAYSTACK_SECRET_KEY}
      - HEYGEN_API_KEY=${HEYGEN_API_KEY}    # Phase 3+ only
      - FAL_KEY=${FAL_KEY}                  # for PlayHT v3 voice cloning

networks:
  traefik:
    external: true                # Pre-existing, set up by VG
  operscale:
    driver: bridge
```

```yaml
# /docker/operscale-video-ads/docker-compose.override.yml
# Sensitive values; chmod 600; not in git.
services:
  agent:
    environment:
      - ANTHROPIC_API_KEY=sk-ant-…
      - SUPABASE_SERVICE_ROLE_KEY=eyJ…
      - DASHBOARD_API_TOKEN=… (same value as VG's, see §10)
      - PAYSTACK_SECRET_KEY=sk_live_…
      - FAL_KEY=…
      - HEYGEN_API_KEY=…
```

Bring up:

```bash
cd /docker/operscale-video-ads && docker compose up -d
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep operscale
```

### 4.5 — Disk capacity check

Vision GridAI as of session 35 cleanup (2026-04-10) used 39% of 200GB. Our additional load will push that. Plan:
- After day 30 (when we have first paying customers), monitor `df -h /` weekly.
- Each Operscale order generates ~150-300MB of intermediate files. Cleanup script runs after each delivery (per VG pattern).
- If sustained ≥ 70% disk usage for >7 days, upgrade to KVM 8 (~$30 → ~$60/month).

---

## 5. Supabase schema fork — write our own clean migration history

**Do NOT copy Vision GridAI's migrations 001-032 forward.** They include 30+ migrations that incrementally added the long-form analytics layer, the intelligence layer, the Australia overlay, and the post-RLS-audit lockdown. Inheriting that history means inheriting all those scars.

Instead, write a small clean migration history that recreates **only the tables we actually need**, then start fresh from `001`.

### 5.1 — Tables we keep (cloned from Vision GridAI's `001_initial_schema.sql`)

These four tables transfer almost as-is, with FK renames:

| VG table | Operscale table | Action |
|---|---|---|
| `scenes` | `scenes` | Clone — change FK from `topic_id` to `order_id` |
| `production_log` | `production_log` | Clone — change FK to `order_id` |
| `prompt_configs` | `prompt_configs` | Clone — re-key from `project_id` to `niche_id` (5 fixed niches) |
| `production_registers` | `production_registers` | Clone — but seed only 2-3 of the 5 registers (see §5.5) |

These tables get **renamed** to fit our domain:

| VG table | Operscale table | Action |
|---|---|---|
| `topics` | `orders` | Rename + drop ~70% of columns (no YouTube analytics, no script_pass_scores, etc.) |
| `shorts` | (merged into `orders` for v1) | Single-video Pilot/Standard = no separate table; Creative Pod = 3 rows in `videos` (a new table) |
| `avatars` (VG = marketing personas) | dropped | Replaced by intake form's `target_audience` field on `briefs` |

These tables are **new** — Vision GridAI didn't have them because it's single-tenant:

- `customers` — the SMB owner record
- `briefs` — raw form submissions (Q1-Q15)
- `payments` — Paystack transaction records
- `gate_decisions` — founder approval audit log
- `order_consent` — Creative Pod photo upload + consent (Phase 3+)
- `videos` — Creative Pod multi-video record (1-3 rows per order)
- `llm_calls` — per-call Anthropic audit (cost monitoring)

### 5.2 — Migration `001_initial.sql` — the canonical starting point

Write this verbatim. The render core depends on the column names in `scenes` matching exactly (the n8n workflows reference them by name). The `audio_status / image_status / clip_status / video_status` enums in particular must match Vision GridAI's `pending → generated → uploaded → failed` exactly — these are referenced inside `WF_TTS_AUDIO`, `WF_IMAGE_GENERATION`, etc.

```sql
-- supabase/migrations/001_initial.sql
-- Operscale Video Ads — Initial Schema
-- This file is the canonical starting point. Forks render-core columns
-- from Vision GridAI's 001_initial_schema.sql, drops everything else.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Customers (NEW — VG is single-tenant) ─────────────────────────
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  whatsapp_phone TEXT,
  full_name TEXT,
  business_name TEXT,
  website_or_handle TEXT,
  source TEXT,                      -- 'meta_ad', 'tiktok_ad', 'organic', 'referral'
  created_at TIMESTAMPTZ DEFAULT now(),
  last_order_at TIMESTAMPTZ,
  marketing_opt_in BOOLEAN DEFAULT false
);
CREATE INDEX idx_customers_email ON customers(email);

-- ── Briefs (NEW — raw form submissions) ───────────────────────────
CREATE TABLE briefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  niche TEXT NOT NULL,              -- 'real_estate' | 'education' | 'fashion' | 'fintech' | 'health'
  business_name TEXT,
  website_url TEXT,
  product_or_service TEXT,
  ideal_customer TEXT,
  unique_value_prop TEXT,
  problem_solved TEXT,
  current_marketing TEXT,
  budget_for_ads_monthly_ngn INTEGER,
  preferred_tone TEXT,              -- 'warm', 'authoritative', 'energetic', 'playful'
  must_include TEXT,
  must_avoid TEXT,
  example_competitor TEXT,
  call_to_action TEXT,
  niche_specific_followup JSONB,    -- niche-tailored Q15+
  raw_form_payload JSONB,           -- full original submission for audit
  save_token TEXT UNIQUE,           -- for resume-form-later flow
  submitted_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_briefs_customer ON briefs(customer_id);
CREATE INDEX idx_briefs_save_token ON briefs(save_token);

-- ── Orders (RENAMED from VG's `topics`, ~70% column reduction) ────
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id),
  brief_id UUID NOT NULL REFERENCES briefs(id),
  tier TEXT NOT NULL CHECK (tier IN ('pilot', 'standard', 'creative_pod')),
  amount_paid_kobo INTEGER NOT NULL,    -- kobo = NGN cents (Paystack convention)
  paystack_tx_ref TEXT UNIQUE,
  niche TEXT NOT NULL,                  -- denormalised from briefs for fast queries
  production_register TEXT,             -- 'documentary' (default) | 'avatar_led' (Creative Pod only)
  pipeline_stage TEXT NOT NULL DEFAULT 'pending'
    CHECK (pipeline_stage IN (
      'pending', 'brief_received', 'awaiting_payment', 'paid',
      'generating_angles', 'awaiting_angle_approval',
      'generating_script', 'awaiting_script_approval',
      'classifying', 'tts', 'images', 'i2v', 'ken_burns',
      'captions', 'assembly', 'rendering', 'awaiting_render_approval',
      'delivered', 'failed', 'refunded'
    )),
  delivery_email_sent_at TIMESTAMPTZ,
  delivery_whatsapp_sent_at TIMESTAMPTZ,
  total_cost_usd DECIMAL(8,4),
  cost_breakdown JSONB,
  retry_count INTEGER DEFAULT 0,
  supervisor_alerted BOOLEAN DEFAULT false,
  last_error TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_stage ON orders(pipeline_stage);
CREATE INDEX idx_orders_created ON orders(created_at DESC);

-- ── Videos (NEW — supports Creative Pod's 3 videos per order) ─────
-- For Pilot + Standard, exactly 1 row per order.
-- For Creative Pod, 3 rows per order.
CREATE TABLE videos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  video_number INTEGER NOT NULL,        -- 1, 2, or 3 within an order
  approved_angle JSONB,                 -- which of the 3 angles the customer picked
  script_json JSONB,
  scene_count INTEGER,
  duration_seconds INTEGER,
  drive_video_url TEXT,                 -- legacy name for source compatibility — actually Supabase Storage URL
  delivered_url TEXT,                   -- signed URL emitted to customer
  signed_url_expires_at TIMESTAMPTZ,
  thumbnail_url TEXT,
  audio_progress TEXT DEFAULT 'pending',
  images_progress TEXT DEFAULT 'pending',
  i2v_progress TEXT DEFAULT 'pending',
  assembly_status TEXT DEFAULT 'pending',
  caption_burn_status TEXT DEFAULT 'pending',
  total_cost_usd DECIMAL(6,4),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (order_id, video_number)
);
CREATE INDEX idx_videos_order ON videos(order_id);

-- ── Scenes (CLONED from VG, FK rebound to videos) ─────────────────
-- Column names MATCH Vision GridAI's `scenes` exactly. The n8n workflows
-- reference these column names verbatim. Do not rename.
CREATE TABLE scenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  scene_number INTEGER NOT NULL,
  scene_id TEXT NOT NULL,
  narration_text TEXT,
  image_prompt TEXT,
  visual_type TEXT,                     -- 'static_image' | 'i2v' | 't2v'
  emotional_beat TEXT,
  chapter TEXT,
  audio_duration_ms INTEGER,
  audio_file_drive_id TEXT,             -- legacy name; actually Supabase Storage object key
  audio_file_url TEXT,
  start_time_ms BIGINT,
  end_time_ms BIGINT,
  image_url TEXT,
  image_drive_id TEXT,
  video_url TEXT,
  video_drive_id TEXT,
  audio_status TEXT DEFAULT 'pending',  -- pending → generated → uploaded → failed
  image_status TEXT DEFAULT 'pending',
  video_status TEXT DEFAULT 'pending',
  clip_status TEXT DEFAULT 'pending',
  composition_prefix TEXT,
  color_mood TEXT,
  zoom_direction TEXT,
  transition_to_next TEXT,
  caption_highlight_word TEXT
    CHECK (caption_highlight_word IS NULL
           OR caption_highlight_word !~ '[`$|;<>&\\]'),  -- inherited from VG migration 031
  selective_color_element TEXT,
  skipped BOOLEAN DEFAULT false,
  skip_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_scenes_video ON scenes(video_id);
CREATE INDEX idx_scenes_order ON scenes(order_id);
CREATE INDEX idx_scenes_status ON scenes(video_id, audio_status);
CREATE INDEX idx_scenes_visual ON scenes(video_id, visual_type);

-- ── Production registers (CLONED from VG migration 024) ───────────
-- We keep VG's table exactly so the workflows that read register config
-- work without modification. We seed only 2 registers at launch.
CREATE TABLE production_registers (
  register_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  short_description TEXT,
  accent_color_hex TEXT,
  config JSONB NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Seed: Documentary register (default for all tiers)
-- Adapted from VG's REGISTER_01 'The Economist'
INSERT INTO production_registers (register_id, name, short_description, accent_color_hex, config) VALUES
('OPERSCALE_01_DOCUMENTARY',
 'Documentary',
 'Default cinematic style for Pilot, Standard, and most Creative Pod orders',
 '#B4532A',
 '{
   "image_anchors": "muted color with controlled warmth, subtle film grain, 35mm look, rule of thirds, generous negative space, shallow depth of field",
   "negative_additions": "no text overlays, no watermarks, no logos in image",
   "tts_voice": "en-NG-Standard-A",
   "tts_speaking_rate": 0.95,
   "music_bpm_min": 80,
   "music_bpm_max": 100,
   "music_mood_keywords": ["uplifting", "cinematic", "moderate energy"],
   "ken_burns_default_preset": "slow_push",
   "typical_scene_length_sec": 4,
   "transition_duration_ms": 400,
   "font_family": "Inter"
 }'::jsonb),
('OPERSCALE_02_AVATAR_LED',
 'Avatar-Led',
 'Creative Pod only — talking-head avatar via HeyGen (Phase 3+)',
 '#C9994A',
 '{
   "image_anchors": "studio-lit talking head, high-contrast subject, clean professional background",
   "negative_additions": "no scene cuts within shot, no environmental distractions",
   "tts_voice": "en-NG-Standard-A",
   "tts_speaking_rate": 1.00,
   "music_bpm_min": 90,
   "music_bpm_max": 110,
   "music_mood_keywords": ["energetic", "modern", "confident"],
   "ken_burns_default_preset": "static",
   "typical_scene_length_sec": 6,
   "transition_duration_ms": 250,
   "font_family": "Inter"
 }'::jsonb);

-- ── Prompt configs (CLONED from VG, re-keyed to niche) ────────────
CREATE TABLE prompt_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche TEXT NOT NULL,
  prompt_type TEXT NOT NULL,            -- 'angle_generator' | 'script' | 'evaluator' | 'visual_director' | 'quote_writer'
  prompt_text TEXT NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (niche, prompt_type, version)
);

-- ── Production log (CLONED from VG) ───────────────────────────────
CREATE TABLE production_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  customer_id UUID REFERENCES customers(id),
  stage TEXT NOT NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_log_order ON production_log(order_id);
CREATE INDEX idx_log_video ON production_log(video_id);
CREATE INDEX idx_log_created ON production_log(created_at DESC);

-- ── Payments (NEW) ────────────────────────────────────────────────
CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  customer_id UUID NOT NULL REFERENCES customers(id),
  paystack_tx_ref TEXT NOT NULL UNIQUE,
  amount_kobo INTEGER NOT NULL,
  currency TEXT DEFAULT 'NGN',
  status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  payment_method TEXT,                  -- 'card', 'bank_transfer', 'ussd'
  webhook_payload JSONB,                -- full Paystack webhook for audit
  paid_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  refund_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_payments_order ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(status);

-- ── Gate decisions (NEW — founder audit log) ──────────────────────
CREATE TABLE gate_decisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  gate_number INTEGER NOT NULL CHECK (gate_number BETWEEN 0 AND 3),
  -- 0 = brief sanity check, 1 = angle approval, 2 = script approval, 3 = render approval
  decision TEXT NOT NULL CHECK (decision IN ('approved', 'rejected', 'edit_requested')),
  feedback TEXT,
  decided_by TEXT NOT NULL,             -- email of approver
  decided_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_gates_order ON gate_decisions(order_id);

-- ── Order consent (NEW — Creative Pod custom avatar, Phase 3+) ────
CREATE TABLE order_consent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  photo_storage_url TEXT NOT NULL,
  consent_text_signed TEXT NOT NULL,
  signed_at TIMESTAMPTZ DEFAULT now(),
  ip_address INET,
  quality_check_status TEXT DEFAULT 'pending'
    CHECK (quality_check_status IN ('pending', 'passed', 'rejected', 'overridden_with_warning')),
  quality_check_feedback TEXT
);

-- ── LLM calls (NEW — per-call Anthropic audit) ────────────────────
CREATE TABLE llm_calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  node_name TEXT NOT NULL,              -- e.g. 'generate_angles', 'write_script', 'gate2_review'
  model TEXT NOT NULL,                  -- 'claude-opus-4-7' | 'claude-haiku-4-5'
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_usd DECIMAL(8,6),
  duration_ms INTEGER,
  called_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_llm_calls_order ON llm_calls(order_id);
CREATE INDEX idx_llm_calls_model ON llm_calls(model);

-- ── Realtime publication (CLONED from VG pattern) ─────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE videos;
ALTER PUBLICATION supabase_realtime ADD TABLE scenes;
ALTER PUBLICATION supabase_realtime ADD TABLE production_log;

-- REPLICA IDENTITY FULL is REQUIRED for UPDATE events to carry changed columns.
-- Forgetting this is the #1 cause of "dashboard says it's connected but never receives updates".
ALTER TABLE orders REPLICA IDENTITY FULL;
ALTER TABLE videos REPLICA IDENTITY FULL;
ALTER TABLE scenes REPLICA IDENTITY FULL;
ALTER TABLE production_log REPLICA IDENTITY FULL;

-- ── RLS lockdown (CLONED from VG migration 030 pattern) ───────────
-- Anon role gets DENY on every table; service_role gets PERMISSIVE.
-- Browser never reads directly — only through Next.js server-side or n8n webhooks.

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE briefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE scenes ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE gate_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE llm_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_registers ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt_configs ENABLE ROW LEVEL SECURITY;

-- Repeat for every table:
DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'customers','briefs','orders','videos','scenes','production_log',
    'payments','gate_decisions','order_consent','llm_calls',
    'production_registers','prompt_configs'
  ])
  LOOP
    EXECUTE format('CREATE POLICY %I_anon_deny ON %I AS RESTRICTIVE FOR ALL TO anon USING (false)', t, t);
    EXECUTE format('CREATE POLICY %I_service_role_all ON %I AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true)', t, t);
  END LOOP;
END $$;
```

### 5.3 — Apply the migration

```bash
# From the dev machine, with Supabase CLI configured:
supabase db push --db-url "postgresql://postgres:$POSTGRES_PASSWORD@srv1297445.hstgr.cloud:54321/postgres"

# Or directly via SSH:
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
docker exec -i supabase-db-1 psql -U postgres < /tmp/001_initial.sql
```

### 5.4 — Why we DON'T just clone VG's `001_initial_schema.sql`

Look at VG's `topics` table — 67 columns, including `script_pass_scores`, `yt_views`, `yt_actual_cpm`, `script_force_passed`, `playlist_group`, `narrative_hook`, `viral_potential`. Inheriting these means:
- Junior engineers will look at them and try to populate them (waste).
- The dashboard read endpoint returns rows 5x larger than needed (latency).
- Schema migrations later have to drop them (technical debt).

Better to start with a 14-column `orders` table and add columns deliberately as features ship.

### 5.5 — What about VG's other ~40 tables?

We do not need:
- The 16-table intelligence layer (`rpm_benchmarks`, `competitor_*`, `pps_*`, `ab_tests`, etc.)
- The 3 research tables (`research_runs`, `research_results`, `research_categories`)
- The 3 channel-analysis tables
- The 3 YouTube-discovery tables
- `niche_profiles` (replaced by static markdown niche briefs in `packages/shared/`)
- `social_accounts` (we don't post for customers)
- `scheduled_posts`, `platform_metadata`, `comments`, `audience_*`
- `cost_calculator_snapshots` — we have a much simpler cost calc (§13)

These add up to ~36 tables we are not creating. The four tables we keep (`scenes`, `production_log`, `prompt_configs`, `production_registers`) are the only render-core dependencies.

---

## 6. n8n workflows: inventory and disposition

Vision GridAI has **~78 named workflows** documented in [the workflow reference](https://akinwunmi-akinrimisi.github.io/vision-gridai-platform/workflows/reference/). Here is what each becomes in our fork:

### 6.1 — Workflows we keep AS-IS (rebind only foreign keys)

These workflows are imported, the `topic_id` references are renamed to `video_id`, the `project_id` references to `order_id`, and otherwise the JSON is untouched. Webhook paths get `/operscale` prefix to namespace them on the shared n8n instance.

| VG workflow | n8n ID | Trigger | Operscale webhook | Action in fork |
|---|---|---|---|---|
| `WF_TTS_AUDIO` | `4L2j3aU2WGnfcvvj` | webhook | `/webhook/operscale/production/tts` | Rebind FK only. Keep all 39 nodes. |
| `WF_IMAGE_GENERATION` | `ScP3yoaeuK7BwpUo` | webhook | `/webhook/operscale/production/images` | Force `aspect_ratio=portrait_9_16` always (drop `landscape_16_9` branch). |
| `WF_SCENE_IMAGE_PROCESSOR` | `Lik3MUT0E9a6JUum` | webhook | `/webhook/operscale/process-scene/image` | Untouched. |
| `WF_SCENE_I2V_PROCESSOR` | `TOkpPY35veSf5snS` | webhook | `/webhook/operscale/process-scene/i2v` | Untouched. |
| `WF_SCENE_T2V_PROCESSOR` | `VLrMKfaDeKYFLU75` | webhook | `/webhook/operscale/process-scene/t2v` | Untouched. |
| `WF_KEN_BURNS` | — | webhook | `/webhook/operscale/production/ken-burns` | Untouched. |
| `WF_CAPTIONS_ASSEMBLY` | `Fhdy66BLRh7rAwTi` | webhook | `/webhook/operscale/production/assembly` | **Crown jewel — 47 nodes, 3-layer crash prevention. Touch nothing.** |
| `WF_RETRY_WRAPPER` | — | sub-workflow | n/a | **Touch nothing.** Used by every external API call. |
| `WF_ASSEMBLY_WATCHDOG` | `Exm836gCGtxNKOeD` | cron | n/a | Untouched. |
| `WF_ENDCARD` | — | sub-workflow | n/a | Untouched (used Standard+ tier). |
| `WF_MUSIC_GENERATE` | — | sub-workflow | n/a | Untouched (used Standard+ tier). |
| `WF_DASHBOARD_READ` | — | webhook | `/webhook/operscale/dashboard/read` | Adapt for our schema (replaces `topics` queries with `orders`). |
| `WF_WEBHOOK_STATUS` | — | webhook | `/webhook/operscale/status` | Health check, untouched. |

### 6.2 — Workflows we adapt

| VG workflow | What changes |
|---|---|
| `WF_SCENE_CLASSIFY` | Drop the cost-calculator-gate handoff (we have no per-order I2V ratio choice — see §13). Keep visual_type classification: `static_image` for Pilot, `i2v` for Standard scenes flagged motion-worthy, mixed for Creative Pod. |
| `WF_SHORTS_PRODUCE` | This is the closest match to our render workflow, but it assumes a parent long-form topic exists. Refactor: it now reads from a `videos` row instead of a `shorts` row. Reuse all the rendering chain, drop the parent-topic dependency. |
| `WF_THUMBNAIL_GENERATE` | We use this for the case-study OG image of delivered videos, not for YouTube thumbnails. Same workflow logic, different output destination (Supabase Storage instead of Drive). |
| `WF_QA_CHECK` | Reuse the 13 automated QA checks. Adjust thresholds for 9:16 only. |
| `WF_WEBHOOK_PRODUCTION` | Vision GridAI's 77-node router. We keep its router pattern but trim heavily — only routes that exist in our pipeline survive. |

### 6.3 — Workflows we delete (already removed in §3.1)

The 50+ workflows around niche research, topic generation, 3-pass scripting, social publishing, analytics, intelligence layer, and Australia overlay — all gone. See §3.1 for the deletion list.

### 6.4 — Workflows we write new

Eight new workflows the customer flow requires. None exist in Vision GridAI.

| New workflow | Purpose |
|---|---|
| `WF_OPS_INTAKE_RECEIVE` | POST handler from `/start` form. Persists `briefs`, fires acknowledgement email + WhatsApp. |
| `WF_OPS_PAYSTACK_WEBHOOK` | Verifies HMAC-SHA512 signature, updates `payments`, transitions order to `paid`. |
| `WF_OPS_ANGLE_GENERATE` | Claude Opus 4.7 generates 3 niche-tailored ad angles from brief. Writes to `videos.approved_angle` candidates. |
| `WF_OPS_QUOTE_DELIVER` | Renders the rich quote email + WhatsApp message with Paystack link. |
| `WF_OPS_GATE_NOTIFY` | On gate transition, push card to Notion DB + WhatsApp nudge to founder. |
| `WF_OPS_GATE_RESUME` | Notion DB row update → POSTs decision back to LangGraph agent's `/resume` endpoint. |
| `WF_OPS_DELIVERY_FANOUT` | Email + WhatsApp delivery of signed download link, parallelised, logged. |
| `WF_OPS_REFUND` | Triggered by Gate 3 reject + customer refund election; calls Paystack refund API + updates `payments.status='refunded'`. |

These are written as fresh n8n workflows. Use the VG pattern (Switch nodes for actions, Code nodes for transforms, HTTP Request nodes wrapped in `WF_RETRY_WRAPPER` for external calls). Save JSON exports to `workflows/operscale/`.

### 6.5 — Importing the kept workflows

n8n stores workflows in the SQLite at `~/.n8n/database.sqlite` inside the `n8n-n8n-1` container. To import VG's workflows for our use:

```bash
# SSH to the VPS
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud

# For each kept workflow, the JSON is already in our repo at workflows/<name>.json.
# Use n8n CLI to import:
docker exec -i n8n-n8n-1 n8n import:workflow --input=/repo/workflows/WF_TTS_AUDIO.json
# Repeat for each kept workflow.
```

After import, **rename each workflow** in the n8n UI by prefixing `OPS_` so they don't collide with VG's running workflows. Activate the renamed ones; do not deactivate VG's originals.

---

## 7. The render core — what to clone byte-for-byte

This is the heart of the value transfer. Six workflows + four scripts + one schema fragment took the original team ~6 months of iteration to dial in. **Do not re-engineer them.** Take them as gospel.

### 7.1 — Phase D production sub-stages (per VG's spec)

This is the exact pipeline a video goes through after script approval:

```
script_approved
  → D1: TTS Audio (Google Cloud Chirp 3 HD, master clock — every visual derives duration from this)
  → D2: Images (Fal.ai Seedream 4.5 portrait_9_16, $0.030–$0.040 per image)
  → D2.5: I2V Clips (Fal.ai Seedance 2.0 Fast, Creative Pod only)
  → D3: Ken Burns + Color Grade (FFmpeg zoompan + 7 colour filter chains)
  → D4: Captions + Transitions + Assembly (Whisper align + kinetic ASS + xfade)
  → D5: Background Music (Vertex AI Lyria, volume=0.12 NOT 0.5 — non-negotiable)
  → D6: End Card (Standard+ only)
  → D7: Single 9:16 render (we don't do 4 platform exports — single output)
```

### 7.2 — The master clock rule

**The TTS audio duration drives every downstream timing.** This is the most important architectural rule in the entire pipeline. Every visual's display time = its scene's TTS audio duration measured by FFprobe in milliseconds.

```bash
# Inside WF_TTS_AUDIO, after each TTS file is generated:
ffprobe -v quiet -show_entries format=duration -of csv=p=0 scene_001.mp3
# Output written to scenes.audio_duration_ms

# Inside WF_KEN_BURNS, the Ken Burns clip duration is calculated from this:
# -t (audio_duration_ms / 1000)
```

Never derive a visual's duration from word count, estimated reading time, or file size. Always FFprobe-measure the actual audio. This rule alone has saved Vision GridAI from sync drift bugs more times than the team can count.

### 7.3 — Image generation: prompt construction formula

`WF_IMAGE_GENERATION` builds each image prompt mechanically:

```
final_prompt = composition_prefix + ", " + scene_subject + ", " + style_dna + ", " + register_anchors
```

Where:
- `composition_prefix` is per-scene (e.g. "wide establishing shot, golden hour, ").
- `scene_subject` is what the LLM wrote about the scene's subject.
- `style_dna` is locked at the **order level** (not the project level — for us, every order is its own "project"). It's the niche's recurring visual fingerprint.
- `register_anchors` come from `production_registers.config.image_anchors` (see §5.5).

The universal negative prompt is appended on every call. It lives in a `prompt_templates` table or as a constant in `WF_IMAGE_GENERATION`. The default is:

```
text, watermark, logo, signature, low quality, blurry, distorted, deformed,
cropped, oversaturated, undersaturated, low contrast, bad anatomy, bad proportions,
extra limbs, mutated hands, poorly drawn hands, poorly drawn face,
out of frame, cluttered background, disfigured, ugly, gross proportions
```

### 7.4 — Ken Burns: 6 zoom expressions and 7 colour filters

Per `directives/05-ken-burns-color.md` (referenced in VG's Phase D doc), `WF_KEN_BURNS` maps:

**Zoom direction → FFmpeg zoompan expression** (intensity 0.0008–0.001 for our format, NOT 0.0015 which is Vision GridAI's short-form aggressive setting — we want subtler motion for ads):

| `zoom_direction` | FFmpeg zoompan expression |
|---|---|
| `zoom_in_center` | `zoom='min(zoom+0.0008,1.5)':d=125:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'` |
| `zoom_out_center` | `zoom='if(eq(on,0),1.5,zoom-0.0008)':d=125:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'` |
| `pan_left` | `zoom='1.2':x='iw-(iw/zoom)-(on*2)':y='ih/2-(ih/zoom/2)':d=125` |
| `pan_right` | `zoom='1.2':x='on*2':y='ih/2-(ih/zoom/2)':d=125` |
| `pan_up` | `zoom='1.2':x='iw/2-(iw/zoom/2)':y='ih-(ih/zoom)-(on*2)':d=125` |
| `pan_down` | `zoom='1.2':x='iw/2-(iw/zoom/2)':y='on*2':d=125` |

**Colour mood → FFmpeg filter chain** (`eq` + `colorbalance`):

| `color_mood` | Filter chain |
|---|---|
| `warm_golden` | `eq=brightness=0.04:saturation=1.1,colorbalance=rs=0.05:gs=0.02:bs=-0.05` |
| `cool_blue` | `eq=brightness=0:saturation=0.95,colorbalance=rs=-0.05:gs=0:bs=0.05` |
| `neutral` | `eq=saturation=1.0` (no colorbalance) |
| `dramatic` | `eq=brightness=-0.04:contrast=1.15:saturation=1.05` |
| `vintage` | `eq=brightness=0.02:saturation=0.85,colorbalance=rs=0.04:gs=0:bs=-0.04` |
| `neon` | `eq=brightness=0:contrast=1.1:saturation=1.4` |
| `desaturated` | `eq=saturation=0.5` |

**Critical rule:** if `selective_color_element IS NOT NULL`, the colour grade is **skipped entirely**. Selective-colour scenes use a separate filter chain that desaturates everything except the named colour. This branch matters for fashion/beauty niche.

**Output format must be locked:** `-r 30 -c:v libx264 -pix_fmt yuv420p`. Mismatched fps between scenes causes the `-c copy` concat in `WF_CAPTIONS_ASSEMBLY` to **silently truncate** the output. This was VG's Session 35 incident that took weeks to root-cause. Their fix: `WF_CAPTIONS_ASSEMBLY` now auto-validates each clip's fps and re-encodes outliers before concat. Inherit that fix; don't loosen it.

### 7.5 — Caption assembly (D4) — three-layer crash prevention

This is the most complex workflow in VG (47 nodes). The three layers protect against a 172-clip xfade chain hitting FFmpeg's memory ceiling:

1. **Build Scene Clip auto-fix** — each clip is FFprobe-checked for fps, sample rate, codec; outliers are re-encoded to canonical 30fps/24kHz/h264/aac before they're allowed into the concat.
2. **Concat Video pre-scan** — before the final concat, scan all clips and batch into 15-20-clip chunks (`batch_N.mp4`), then crossfade the batches.
3. **Post-concat duration drift check** — the final assembled MP4's duration is compared to the sum of TTS durations. If short by >5%, log a WARNING and route to fix (rather than silently shipping a truncated video).

Even though our videos are 15-60 seconds (not 2 hours), keep all three layers. A drift bug on a paying customer's order is an automatic refund obligation.

### 7.6 — The render volumes you must mount

n8n's container needs scratch space. Update `/docker/n8n/docker-compose.override.yml` to add an Operscale-specific bind mount **without** disturbing VG's existing mount:

```yaml
services:
  n8n:
    volumes:
      - /data/n8n-production:/tmp/production    # VG's existing mount, untouched
      - /data/operscale-production:/tmp/operscale-production    # NEW
```

Then restart n8n: `cd /docker/n8n && docker compose up -d`.

The render workflows we kept all reference `/tmp/production/<topic_id>/...` inside the container. We add a sed-style path remap to those workflow JSONs: replace `/tmp/production/` with `/tmp/operscale-production/` in the imported copies. Do this once at import time, not at runtime.

---

## 8. Caption burn service — host-side, untouched

This is the crown of crowns of the render pipeline. **Do not modify it.** Use it as-is.

### 8.1 — What it is

A 196-line Python HTTP service that lives on the VPS host (NOT inside any Docker container) and burns kinetic ASS subtitles into videos. It exists because the n8n task runner OOMs when re-encoding video with libass. The service runs FFmpeg via `docker exec` from the host, piggybacking the n8n container's filesystem (where Drive credentials and the production volume live) without using the n8n container's RAM budget.

### 8.2 — Where it lives

```
/opt/caption-burn/
├── caption_burn_service.py          # The 196-line HTTP service
└── caption-burn.service             # systemd unit (optional, for prod)
```

It's **shared** with Vision GridAI. We do not run a second copy.

### 8.3 — The service is already running

It's currently bound to Vision GridAI. The header constants are:

```python
PORT = 9998
N8N_CONTAINER = "n8n-n8n-1"
HOST_BASE = "/data/n8n-production"        # ← VG-specific!
CONTAINER_BASE = "/tmp/production"        # ← VG-specific!
N8N_WEBHOOK_BASE = os.environ.get("N8N_WEBHOOK_BASE", "https://n8n.srv1297445.hstgr.cloud/webhook")
DASHBOARD_API_TOKEN = os.environ.get("DASHBOARD_API_TOKEN", "")
```

There is one issue: `HOST_BASE` and `CONTAINER_BASE` are hardcoded for VG's path. **Do not change them inline.** Instead, make them environment-variable-driven so the same service can serve both products:

```python
# In caption_burn_service.py — change two lines:
HOST_BASE = os.environ.get("CB_HOST_BASE", "/data/n8n-production")
CONTAINER_BASE = os.environ.get("CB_CONTAINER_BASE", "/tmp/production")

# Then for Operscale calls, the request payload includes the override:
# POST /burn { topic_id, srt_filename, video_filename, drive_folder_id, host_base_override?, container_base_override? }
```

But really — the cleanest solution is to **encode the project in the path itself**. Make Operscale's render output land in `/data/operscale-production/<order_id>/...` inside the container (per §7.6 above) and pass that as `topic_id` style:

```python
# Operscale call from WF_CAPTIONS_ASSEMBLY:
POST http://172.18.0.1:9998/burn
{
  "topic_id": "operscale-<order_id>-v<video_number>",
  "srt_filename": "kinetic.ass",
  "video_filename": "video.mp4",
  "drive_folder_id": "<supabase-storage-path-encoded>"
}
```

The service's `os.path.join(HOST_BASE, topic_id, ...)` will resolve correctly if we mount `/data/operscale-production` to the same parent path as `/data/n8n-production`. Or — simpler — we add a small shim:

```bash
# On the host:
ln -sf /data/operscale-production /data/n8n-production/operscale
# Then operscale "topics" become operscale/<order_id> within VG's tree.
```

Pick one approach (env vars OR symlink). Document the choice in your decision log.

### 8.4 — The kinetic ASS generator (`generate_kinetic_ass.py`)

238 lines. Untouched. It reads:
1. `word_timings.json` — Whisper forced alignment output (one entry per scene, word-level start/end ms).
2. `scenes.json` — per-scene narration text and cumulative timestamps.

It emits an ASS file with these tuned-per-mobile-readability defaults:

```python
FONT_NAME = "Inter"
FONT_SIZE_NORMAL = 68
FONT_SIZE_EMPHASIS = 88
OUTLINE_SIZE = 5
SHADOW_DEPTH = 4
MARGIN_BOTTOM = 140
MAX_WORDS_PER_GROUP = 4
```

Emphasis word detection is built in:
- Numbers and money (`$5,000`, `2026`)
- ALL CAPS tokens (`CRITICAL`)
- Words after negation (`not ENOUGH`)
- Curated power-word list (`secret, hidden, exposed, billion, illegal, scam, fraud, …`)

Emphasis renders in **yellow `#FFD700`** with optional **red `#FF4444`**. Per-word "pop-in bounce" animation: `100% → 115% → 100%` over 200ms.

### 8.5 — The shell wrapper (`burn_captions.sh`)

106 lines. Local-development orchestration wrapper. In production, n8n calls the HTTP service directly, but for testing on a dev machine:

```bash
bash burn_captions.sh <order_id> <supabase_url> <supabase_anon_key> <supabase_service_role_key>
```

Works against a Supabase Postgres at the URL given. Useful when debugging caption issues before involving the full n8n chain.

### 8.6 — Whisper forced alignment (`whisper_align.py`)

Runs from `/opt/whisper-env/bin/python3` — that's the VG installation. It uses `whisper.transcribe(word_timestamps=True)`. Untouched.

### 8.7 — Caption styles per niche (Standard tier)

Vision GridAI uses one caption style globally (yellow + red emphasis). For Standard tier we want niche-styled subtitles per the v2 tier spec. Implement this by extending `generate_kinetic_ass.py` with a niche parameter:

```python
NICHE_PRESETS = {
    "real_estate": {"emphasis_color": "#D4AF37", "font": "Inter"},     # gold
    "education":   {"emphasis_color": "#3D4A78", "font": "Inter"},     # indigo
    "fashion":     {"emphasis_color": "#FF4444", "font": "Inter"},     # red (default)
    "fintech":     {"emphasis_color": "#00D4FF", "font": "JetBrains Mono"},  # tech cyan
    "health":      {"emphasis_color": "#5A7846", "font": "Inter"},     # sage
}
```

Pass `--niche=fintech` from `WF_CAPTIONS_ASSEMBLY`. This is a 20-line addition; don't fork the whole script.

---

## 9. Resume/retry guarantees you must preserve

Vision GridAI survives 3am failures. It does so via two complementary mechanisms that **must not be weakened**:

### 9.1 — `WF_RETRY_WRAPPER`

Every external API call (Anthropic, Fal.ai, Google TTS, HeyGen, Paystack callbacks) goes through this 3-node sub-workflow. Exponential backoff: **1s → 2s → 4s → 8s, capped at 30s, max 4 attempts**. After exhaustion, returns `{ success: false, ... }` rather than throwing.

The CLAUDE.md rule from VG: *"Exponential backoff retry on ALL external API calls. 1s → 2s → 4s → 8s, max 4 attempts. Applied via WF_RETRY_WRAPPER sub-workflow."*

**Do not bypass this for "performance" reasons.** Direct HTTP nodes that skip the wrapper accumulate transient failures into customer-visible errors. The marginal cost of the wrapper is two extra node executions per call; the cost of skipping it is the next time Fal.ai has a 503.

### 9.2 — Per-scene status fields drive resume

Every scene row carries four status columns, each owned by one production stage:

```sql
audio_status TEXT DEFAULT 'pending',   -- pending → generated → uploaded → failed
image_status TEXT DEFAULT 'pending',
clip_status  TEXT DEFAULT 'pending',
video_status TEXT DEFAULT 'pending',
```

Every production workflow's first node queries:

```sql
SELECT id FROM scenes
WHERE video_id = $1 AND <stage>_status = 'pending'
ORDER BY scene_number;
```

A workflow that crashed mid-run picks up where it stopped. **Writes are scene-by-scene, NEVER batched.** Batching the writes would break resume — a crash mid-batch leaves rows that succeeded marked as `pending`, forcing duplicate generation.

### 9.3 — Global pipeline stage on `orders`

`orders.pipeline_stage` advances through the lifecycle (see the CHECK constraint in §5.2). On restart, the master orchestrator reads this column and routes directly to the correct next workflow, rather than replaying upstream stages. For example: if `pipeline_stage = 'ken_burns'`, TTS + Images already finished — go straight to `WF_KEN_BURNS`.

### 9.4 — Three concrete resume scenarios

These three scenarios will happen to you. Test for them before launch:

1. **n8n container restart mid-render.** Kill the container during a render, start it back up. The next manual webhook call to `/webhook/operscale/production/<stage>` for that order should pick up at the right scene without regenerating completed scenes. Validate by counting `audio_status='uploaded'` rows before and after.

2. **Caption burn 3-hour timeout.** The burn service hangs on a problematic video. The workflow should notice `assembly_status != 'complete'` after the timeout, flag the order's `supervisor_alerted=true`, and the operator can re-trigger the burn step alone (not the whole pipeline).

3. **Fal.ai outage during image generation.** During the outage, ~half the scenes' `image_status` flip to `failed`. After Fal.ai recovers, a supervisor cron resets failed-scene rows back to `pending` and re-fires `WF_IMAGE_GENERATION`. The other scenes that succeeded stay untouched.

---

## 10. Auth, secrets, and the JWT chain

Vision GridAI has three trust boundaries. Operscale inherits all of them.

### 10.1 — The three trust boundaries

1. **Browser → n8n webhooks** — `Authorization: Bearer ${DASHBOARD_API_TOKEN}` shared secret.
2. **Anything → Supabase (PostgREST + Realtime)** — Kong's `key-auth` plugin checks `apikey` (ANON) and a JWT signed with `JWT_SECRET` (SERVICE_ROLE for server-to-server, ANON for read-only).
3. **n8n → external APIs** — n8n's stored credential store, encrypted at rest in `~/.n8n/database.sqlite`.

### 10.2 — The DASHBOARD_API_TOKEN — share with VG

The bearer token used by Vision GridAI's dashboard is the same token we'll use for Operscale's webhooks. It's stored in:
- `/docker/n8n/docker-compose.override.yml` (env var on the n8n container)
- `/opt/dashboard/.env` (VG's dashboard)
- An n8n credential, ID `KtMyWD7uJJBZYLjt` per VG's auth-secrets doc

For Operscale, our `apps/web` and `apps/agent` containers also need this token. **Do not generate a new one.** Use the existing one — both products' workflows live in the same n8n instance, so a single shared token simplifies operations.

```bash
# Read it from the live VPS:
ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud
grep DASHBOARD_API_TOKEN /docker/n8n/docker-compose.override.yml
```

Inject it into our Operscale containers via `/docker/operscale-video-ads/docker-compose.override.yml` (per §4.4).

### 10.3 — The missing-`=` expression trap (READ THIS)

n8n string parameters that begin with `=` evaluate as expressions. Without `=`, the literal `{{ $env.DASHBOARD_API_TOKEN }}` is sent over the wire and the receiving endpoint rejects it.

A 17-node sweep across `WF_SUPERVISOR` (11 nodes) and `WF_ANALYTICS_CRON` (6 nodes) had been failing silently this way **for ~30 days** before VG Session 38 caught it. The workflows ran without errors, the analytics just never updated.

In every webhook-triggered node we import or write, the Authorization header value MUST be:

```
={{ $env.DASHBOARD_API_TOKEN }}    ← correct (note the leading `=`)
```

NOT:

```
{{ $env.DASHBOARD_API_TOKEN }}    ← WRONG, sends literal text
```

VG's `tools/lint_n8n_workflows.py` has rule `AUTH-01` that fails CI when an `Authorization` header value contains `{{` but does not start with `=`. **Port this lint rule to our repo.** It's the cheapest possible insurance against repeating this 30-day silent failure.

### 10.4 — The JWT chain — 4 sync points

The Supabase JWT secret is in `/docker/supabase/.env`. After any rotation, **four** downstream copies must be updated, in this order:

| Location | What | After rotation |
|---|---|---|
| `/docker/n8n/docker-compose.override.yml` | `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` env vars | Replace, restart n8n stack |
| `_realtime.tenants.jwt_secret` (DB rows) | Per-tenant secret — **TWO rows**: `realtime` and `realtime-dev` | `UPDATE _realtime.tenants SET jwt_secret = '<NEW>' WHERE name IN ('realtime', 'realtime-dev')` |
| `/docker/supabase/supabase/kong.yml` | Kong consumer credentials | Replace, then `docker exec supabase-kong-1 kong reload` |
| `dashboard/.env` + `/opt/dashboard/.env` | `VITE_SUPABASE_ANON_KEY` | Replace, rebuild dashboard |

For Operscale, add a fifth sync point: our own `web` and `agent` containers. Update `/docker/operscale-video-ads/docker-compose.override.yml` and restart with `docker compose up -d`.

Skipping any sync point produces a different silent failure mode:
- Skip n8n env: HTTP requests to PostgREST get `JWSError JWSInvalidSignature`
- Skip Realtime tenants: dashboard WSS connects but immediately gets `401 jwt invalid`
- Skip Kong reload: Kong serves cached old keys, new keys are rejected
- Skip dashboard: dashboard reads cached tokens from prior build

VG has a full rotation playbook in `infrastructure/auth-secrets`. Read it before doing your first rotation.

### 10.5 — Critical n8n env vars

Two non-obvious env vars that VG had to learn the hard way:

```yaml
# In /docker/n8n/docker-compose.override.yml:
environment:
  - NODE_FUNCTION_ALLOW_BUILTIN=child_process    # Required for TTS + assembly Code nodes
  - N8N_ENCRYPTION_KEY=<sha256>                  # Encrypts ~/.n8n/database.sqlite credentials
```

Without `NODE_FUNCTION_ALLOW_BUILTIN=child_process`, Code nodes that use `subprocess` or `exec` fail silently. This is what broke VG's TTS for an entire session before Session 9 fixed it.

---

## 11. What you build new (intake → payment → delivery)

This is the new surface area Vision GridAI doesn't have. Six chunks:

### 11.1 — Marketing site (Next.js 15)

Public-facing site at `<product-domain>.com`. Routes:
- `/` — landing page, value prop, social proof, three pricing tiers
- `/start` — the 15-question intake form
- `/start/resume?token=…` — resume an in-progress form via save-token
- `/o/[order_id]` — anonymous case study page (per existing marketing-site spec)
- `/legal/terms` — Terms of Service
- `/legal/privacy` — Privacy Policy (NDPC-compliant)

### 11.2 — Intake form

The 15 questions are documented in our existing `option-a-detailed-spec.md`. Form is multi-step (5 steps × 3 questions each, roughly), saves to `briefs` table on every step transition. Save-token allows email-link resume.

POST to `/api/intake/submit` (Next.js API route) which persists to Supabase and fires `WF_OPS_INTAKE_RECEIVE`.

### 11.3 — Paystack payment flow

After the founder reviews the brief and approves the angle (Gate 0 → Gate 1), the system generates a Paystack payment link and emails it to the customer. The customer pays; Paystack POSTs to `/api/webhooks/paystack`; we verify the HMAC-SHA512 signature; we update `payments` and transition the order to `paid`.

The Paystack webhook handler MUST verify the signature using `PAYSTACK_SECRET_KEY`:

```typescript
// /api/webhooks/paystack/route.ts
import crypto from 'crypto';

export async function POST(req: Request) {
  const rawBody = await req.text();
  const signature = req.headers.get('x-paystack-signature');
  
  const computedSignature = crypto
    .createHmac('sha512', process.env.PAYSTACK_SECRET_KEY!)
    .update(rawBody)
    .digest('hex');
    
  if (computedSignature !== signature) {
    return new Response('Invalid signature', { status: 401 });
  }
  
  // … process the verified webhook …
}
```

### 11.4 — LangGraph agent (Python 3.11)

The order pipeline is orchestrated by a LangGraph state machine. See §12 for the state diagram. The agent runs in the `operscale-agent` container (per §4.4).

The agent is responsible for:
- Generating 3 niche-tailored angles (calls Claude Opus 4.7)
- Generating the script after angle approval (calls Claude Opus 4.7)
- Triggering production workflows in n8n via webhook calls
- Polling for completion (or listening to Supabase Realtime updates on `orders`/`videos`/`scenes`)
- Triggering delivery workflow after Gate 3 approval

### 11.5 — Founder gate-review console (Notion-based)

Per ADR 0005 in our existing docs, gate review surfaces in Notion, not a custom-built dashboard. A Notion DB has a row per pending gate; the founder reviews and clicks Approve/Reject; a Notion automation POSTs the decision to `/webhook/operscale/gate/resume` which updates the order and resumes the agent.

### 11.6 — Email + WhatsApp delivery

After Gate 3 approval, `WF_OPS_DELIVERY_FANOUT` runs:
1. Generate a 7-day signed URL for the video in Supabase Storage.
2. Send email via Resend with the signed URL + receipt.
3. Send WhatsApp message via Evolution API with a shorter copy + URL.
4. Mark `orders.delivered_email_sent_at` and `delivered_whatsapp_sent_at`.
5. Schedule the 7-day post-delivery follow-up email.

---

## 12. LangGraph agent shape

The agent is a state machine over the order lifecycle:

```
[IDLE]
  └─ on /start submit → [BRIEF_RECEIVED]
       │
       ├─ Gate 0: founder sanity check (Notion card)
       │    ├─ approved → [GENERATING_ANGLES]
       │    └─ rejected → [REFUNDED] (no money charged yet anyway)
       │
       └─ [GENERATING_ANGLES] (Claude Opus call)
            └─ angles ready → [AWAITING_QUOTE_DELIVERY]
                 └─ WF_OPS_QUOTE_DELIVER fires → email + WA sent
                      └─ customer clicks Paystack link
                           └─ Paystack webhook → [PAID]
                                └─ [GENERATING_SCRIPT] (Claude Opus call)
                                     │
                                     ├─ Gate 1: founder approves angle (Notion)
                                     │    ├─ approved → continue
                                     │    └─ regenerate → restart with feedback
                                     │
                                     └─ [GENERATING_SCRIPT] continues
                                          │
                                          ├─ Gate 2: founder approves script (Notion)
                                          │    ├─ approved → [PRODUCTION]
                                          │    └─ regenerate → re-call Claude with feedback
                                          │
                                          └─ [PRODUCTION] (parallel n8n workflows)
                                               │
                                               ├─ scene_classify → tts → images
                                               ├─ (Creative Pod only) i2v
                                               ├─ ken_burns
                                               ├─ captions + assembly
                                               └─ caption_burn
                                                    │
                                                    └─ Gate 3: founder approves render (Notion)
                                                         ├─ approved → [DELIVERED]
                                                         │    └─ WF_OPS_DELIVERY_FANOUT fires
                                                         ├─ regenerate → restart from script
                                                         └─ refund → [REFUNDED]
                                                              └─ WF_OPS_REFUND fires
```

Implementation: each node is a LangGraph step. The state object carries `order_id`, `customer_id`, the brief, the script JSON once generated, and the gate decisions. State persists in Supabase between steps (via the `orders.pipeline_stage` column).

The agent runs as a long-lived Python process. It listens to Supabase Realtime updates on `gate_decisions` table to know when a gate has been resolved, then resumes the appropriate state.

For agent skeleton:

```python
# apps/agent/main.py
from langgraph.graph import StateGraph, END
from typing import TypedDict

class OrderState(TypedDict):
    order_id: str
    customer_id: str
    brief: dict
    angles: list | None
    approved_angle: dict | None
    script: dict | None
    pipeline_stage: str
    last_error: str | None

def gate_0_check(state: OrderState) -> OrderState:
    # Trigger Notion card via WF_OPS_GATE_NOTIFY
    # Wait for gate_decisions row via Supabase Realtime
    # Update state.pipeline_stage based on decision
    return state

def generate_angles(state: OrderState) -> OrderState:
    # Call Anthropic Claude Opus 4.7
    # Use prompt_configs WHERE niche=state.brief.niche AND prompt_type='angle_generator'
    # Write 3 candidates back to videos table
    # Log to llm_calls
    return state

# … etc, one function per state

graph = StateGraph(OrderState)
graph.add_node("brief_received", brief_received)
graph.add_node("gate_0", gate_0_check)
graph.add_node("generate_angles", generate_angles)
# … etc
graph.set_entry_point("brief_received")
graph.add_edge("brief_received", "gate_0")
# … conditional edges based on gate decisions
graph.set_finish_point("delivered")

app = graph.compile()
```

---

## 13. Cost calculator + tier mapping

VG's `WF_SCENE_CLASSIFY` lets the operator choose I2V ratio (0/5/10/15%) for a 172-scene video. We do not need that complexity. Our cost calc is much simpler:

| Tier | Scene count | Visual mix | Per-order COGS (USD) |
|---|---|---|---|
| Pilot (₦75K) | 5-8 (15-30s video) | All `static_image` (Ken Burns only) | ~$2.50 (image $0.24, TTS $0.05, render $0, LLM $2) |
| Standard (₦175K) | 8-12 (15-45s video) | `static_image` + ~20% `i2v` | ~$5 (images $0.36, i2v ~$0.50, TTS $0.08, music $0.02, render $0, LLM $4) |
| Creative Pod (₦350K, 3 videos) | 30-36 total | Mixed; if customer chooses avatar-led, route to HeyGen for that video | ~$15-25 (3× images $1.08, 3× i2v ~$1.50, 3× TTS $0.24, 3× music $0.06, render $0, LLM $12-22, optional HeyGen $0-15) |

These costs go in `orders.total_cost_usd` after the order completes. The supervisor cron alerts if a single order's COGS exceeds 15% of revenue (pre-tier-cost margin guard).

---

## 14. Inherited gotchas — read this twice

A non-exhaustive list of failure modes Vision GridAI experienced. Each one is a real session in their MEMORY.md. Each one will happen to you eventually unless you remember it now.

### 14.1 — The `localhost` IPv6 trap

From inside the n8n container, **NEVER use `localhost` to reach a host service.** Node's runtime resolves `localhost` to IPv6 `::1`, which doesn't route off the container. Always use `172.18.0.1` (the Docker bridge gateway). VG has this hardcoded in workflow JSONs that call the caption burn service.

### 14.2 — The missing `=` expression trap (already covered in §10.3)

### 14.3 — Mismatched FFmpeg input formats cause silent truncation

If you concat 10 clips with `-c copy` and one of them has a different fps, sample rate, or audio codec, FFmpeg will silently truncate the output. The output file looks fine, the duration is just shorter than expected. VG's Session 35 took weeks to root-cause. The fix is the 3-layer crash prevention in `WF_CAPTIONS_ASSEMBLY` (see §7.5).

### 14.4 — REPLICA IDENTITY FULL is required for Realtime UPDATEs

If you forget `ALTER TABLE foo REPLICA IDENTITY FULL`, the Realtime UPDATE events arrive at the dashboard **without the changed columns**. The dashboard knows "something changed" but can't show what. Always set it; the migration in §5.2 already does.

### 14.5 — Don't put Supabase JWTs in workflow JSON

Use n8n credentials, never inline values. After the 2026-04-21 audit, VG had **22 structural fixes across 16 workflows** to remove inline credentials. The `CRED-01` lint rule in `tools/lint_n8n_workflows.py` blocks PRs that add inline auth headers — port it.

### 14.6 — Music volume is 0.12, not 0.5

In `WF_MUSIC_GENERATE`, the `volume=0.12` parameter for music ducking under voiceover is **non-negotiable**. Music must be barely perceptible. VG's directive is explicit: *"Music must be barely perceptible; this is non-negotiable per the directive."*

### 14.7 — Caption-burn 3-hour timeout

The caption burn service has a 3-hour timeout. The error message is `[BURN] FFmpeg timed out after 60 minutes` (the message string is older than the actual timeout — VG bumped it to 10800s but didn't update the log). If you see this error, restart the systemd service:

```bash
systemctl restart caption-burn.service
journalctl -u caption-burn.service -f
```

### 14.8 — Fal.ai async queue limits

- 2 image / 10s
- 1 T2V / 60s
- 2 I2V / 10s

Above these limits, Fal.ai returns 429s. `WF_RETRY_WRAPPER` absorbs 429s, but if you bypass the wrapper for "speed" you'll see them in production.

### 14.9 — The `/webhook/drive-upload` rename

The caption-burn service used to call `/webhook/kinetic/drive-upload`. After the Remotion/Kinetic system was removed, the path was renamed to `/webhook/drive-upload`. If you see legacy code calling the old path, update it.

### 14.10 — Supabase Realtime silently breaks on JWT mismatch

If the `_realtime.tenants.jwt_secret` doesn't match the JWT_SECRET in `.env`, the dashboard's WSS connection succeeds (TLS handshake works) but immediately drops with `401 jwt invalid` — and there's no obvious symptom on the server side. Always update both `realtime` and `realtime-dev` tenant rows on rotation.

### 14.11 — Fal.ai NSFW false positives

Fal.ai's content filter occasionally flags benign images (Session 28 incident). Single scene marked `image_status='failed'`. Pipeline continues — operator regenerates that scene from the dashboard.

### 14.12 — n8n Code node `child_process` requirement

If a Code node uses `subprocess` or `exec`, the n8n container env must include `NODE_FUNCTION_ALLOW_BUILTIN=child_process`. Without it, the node fails silently with no useful error.

---

## 15. Day-by-day execution plan

### Week 1 (Days 1-7) — Foundation

- **Day 1:** Repository setup + clean checkout (§2). Day 1 Prune Commit (§3). Push to GitHub.
- **Day 2:** Inspect inherited Vision GridAI infrastructure on the VPS (§4.1-4.3). Map every file path. Take notes.
- **Day 3:** Provision new Operscale containers in Docker Compose (§4.4). Bring them up empty. Verify Traefik routes.
- **Day 4:** Apply migration `001_initial.sql` to a NEW database (`operscale_video_ads` schema or separate DB) (§5). Test all RLS policies block anon, allow service_role.
- **Day 5:** Import the kept Vision GridAI workflows into n8n with `OPS_` prefix (§6.5). Test `WF_TTS_AUDIO` end-to-end with a fake order/video/scene row.
- **Day 6:** Test `WF_IMAGE_GENERATION` end-to-end. Verify portrait_9_16 aspect ratio. Inspect output.
- **Day 7:** Catch up day. Fix anything broken. Don't rush; the foundation matters.

### Week 2 (Days 8-14) — Render core integration

- **Day 8:** Test `WF_KEN_BURNS` with a real generated image. Verify zoom/colour mood correctness.
- **Day 9:** Test `WF_CAPTIONS_ASSEMBLY` end-to-end. This is the big one. Use a 30-second test sequence.
- **Day 10:** Configure caption-burn service for our path (§8.3). Run end-to-end render of a fake scene set.
- **Day 11:** Wire up `WF_SHORTS_PRODUCE` as our render pipeline. Test against a fake order.
- **Day 12:** Test resume scenarios (§9.4). Kill containers mid-render. Verify scenes pick up correctly.
- **Day 13:** Verify Realtime updates flow to a test dashboard.
- **Day 14:** Catch up day.

### Week 3 (Days 15-21) — Customer flow

- **Day 15:** Build Next.js marketing site shell (§11.1). Get Traefik routing working.
- **Day 16:** Build the intake form (§11.2). Persist to `briefs` table.
- **Day 17:** Build the Paystack integration (§11.3). Test mode only.
- **Day 18:** Build `WF_OPS_INTAKE_RECEIVE` and `WF_OPS_PAYSTACK_WEBHOOK` (§6.4).
- **Day 19:** Build the LangGraph agent skeleton (§12). Get a test order through Gate 0.
- **Day 20:** Build `WF_OPS_QUOTE_DELIVER` (rich quote email + WhatsApp).
- **Day 21:** Catch up day.

### Week 4 (Days 22-28) — Gates + delivery

- **Day 22:** Build the Notion gate review system (§11.5). Set up the Notion DB.
- **Day 23:** Wire `WF_OPS_GATE_NOTIFY` and `WF_OPS_GATE_RESUME`.
- **Day 24:** Build script generation node in the agent (§12).
- **Day 25:** Build `WF_OPS_DELIVERY_FANOUT` (§11.6).
- **Day 26:** End-to-end test: real Paystack-test payment → real Anthropic call → real render → real delivery.
- **Day 27:** Iterate on quality. Run 3-5 internal test orders.
- **Day 28:** Catch up day.

### Week 5 (Days 29-35) — Production polish

- **Day 29:** Set up monitoring. Cost-per-order tracking via `llm_calls` and `production_log`.
- **Day 30:** Test the kill criterion path: refund flow, `WF_OPS_REFUND`.
- **Day 31:** Production hardening: rate limits, error pages, 404s.
- **Day 32:** Lint rules: port `AUTH-01` and `CRED-01` from VG.
- **Day 33:** Internal QA round. Have 5 people fill out the intake form.
- **Day 34:** Switch Paystack to live mode. Smoke test with a real ₦100 transaction (refund yourself after).
- **Day 35:** Catch up day. Everything should be working.

### Week 6+ (Days 36+) — Soft launch

Per the launch-budget timeline. Phase 1 starts.

---

## 16. Definition of Done — tier 1 ship

Before shipping to a real customer, every one of these must be true:

- [ ] Migration `001_initial.sql` applied in production.
- [ ] All RLS policies tested: anon role can't read or write any table. Service role can.
- [ ] All 13+ kept workflows imported into n8n with `OPS_` prefix and active.
- [ ] All 8 new `WF_OPS_*` workflows built and tested.
- [ ] Marketing site live at `<product-domain>.com` with valid TLS.
- [ ] Intake form persists to `briefs` table.
- [ ] Paystack webhook signature verification working.
- [ ] LangGraph agent runs as systemd / Docker service, restarts automatically.
- [ ] Caption burn service shared correctly with Vision GridAI (no path conflicts).
- [ ] At least 3 internal end-to-end test orders rendered successfully.
- [ ] Resume scenarios tested (n8n container restart, caption-burn timeout).
- [ ] DASHBOARD_API_TOKEN bearer auth verified on every webhook endpoint.
- [ ] All n8n Authorization header values prefixed with `=` (lint check passes).
- [ ] No inline credentials in workflow JSON (lint check passes).
- [ ] REPLICA IDENTITY FULL set on `orders`, `videos`, `scenes`, `production_log`.
- [ ] Supabase Storage buckets created with signed-URL policy (7-day expiry).
- [ ] Email (Resend) and WhatsApp (Evolution API) delivery tested end-to-end.
- [ ] Notion gate review DB set up; founder can approve/reject from phone.
- [ ] Cost-per-order tracking working (`llm_calls` populated).
- [ ] Refund flow tested end-to-end.
- [ ] Privacy Policy + Terms of Service published. NDPC-compliant.
- [ ] Disk space check: VPS has at least 30% free for Operscale's growth.
- [ ] Backup script for `/data/operscale-production/` running nightly.
- [ ] Monitoring alert: order in `pipeline_stage='failed'` for >1 hour.
- [ ] Monitoring alert: `production_log` rate-of-error > 5% in last hour.

When all 26 boxes are checked, you can ship to a real paying customer.

---

## Appendix A — Source-of-truth files preserved verbatim

These four files from Vision GridAI's `execution/` directory should land in our repo unchanged. They are reproduced here for offline reference.

### A.1 — `execution/caption_burn_service.py` (196 lines)

Already documented in §8. The full source is at:
https://github.com/akinwunmi-akinrimisi/vision-gridai-platform/blob/main/execution/caption_burn_service.py

Key constants:
```python
PORT = 9998
N8N_CONTAINER = "n8n-n8n-1"
HOST_BASE = "/data/n8n-production"
CONTAINER_BASE = "/tmp/production"
CAPTION_STYLE = (
    "FontName=Arial,FontSize=26,Bold=1,"
    "PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,"
    "BackColour=&H80000000,Outline=3,Shadow=2,"
    "MarginV=35,Alignment=2"
)
# subprocess timeout=10800 (3 hours)
# os.replace for atomic swap
# Original kept as _no_captions.mp4
```

The FFmpeg command it runs inside the n8n container:
```bash
docker exec n8n-n8n-1 sh -c 'ffmpeg -y -i <video> \
  -vf "subtitles=<srt>:force_style=<style>" \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
  -c:v libx264 -preset medium -crf 18 \
  -c:a aac -ar 48000 -ac 1 -b:a 128k \
  -movflags +faststart <output>'
```

### A.2 — `execution/generate_kinetic_ass.py` (238 lines)

Already documented in §8.4. Full source:
https://github.com/akinwunmi-akinrimisi/vision-gridai-platform/blob/main/execution/generate_kinetic_ass.py

Key constants:
```python
WHITE   = "&H00FFFFFF"
YELLOW  = "&H0000D7FF"   # #FFD700 in BGR
RED     = "&H004444FF"   # #FF4444 in BGR
OUTLINE = "&H00000000"
SHADOW  = "&H96000000"

MAX_WORDS_PER_GROUP = 4
FONT_NAME = "Inter"
FONT_SIZE_NORMAL = 68
FONT_SIZE_EMPHASIS = 88
OUTLINE_SIZE = 5
SHADOW_DEPTH = 4
MARGIN_BOTTOM = 140

POP_IN_DURATION = 120
POP_SETTLE_DURATION = 80
FADE_IN = 80
FADE_OUT = 150
WORD_GAP_MS = 30
```

Power-word list for emphasis detection (excerpt):
```python
power_words = {
  "secret", "hidden", "exposed", "shocking", "billion", "million", "trillion",
  "illegal", "scam", "fraud", "truth", "lie", "lies", "corrupt", "broken",
  "massive", "enormous", "incredible", "impossible", "dangerous", "deadly",
  "critical", "urgent", "emergency", "crisis", "collapse", "destroy",
  "exactly", "precisely", "specifically", "literally", "absolutely",
  "everything", "nothing", "everyone", "nobody", "always", "never",
  "free", "zero", "double", "triple", "guaranteed", "proven", "exposed",
}
```

### A.3 — `execution/burn_captions.sh` (106 lines)

Bash wrapper for local-development testing. Full source:
https://github.com/akinwunmi-akinrimisi/vision-gridai-platform/blob/main/execution/burn_captions.sh

Three-step flow:
1. Whisper forced alignment → `word_timings.json`
2. `python3 generate_kinetic_ass.py timings.json scenes.json output.ass`
3. FFmpeg burns the ASS file onto the video

The FFmpeg invocation in the script:
```bash
ffmpeg -y -i "${VIDEO_FILE}" \
  -vf "ass=${ASS_FILE}:fontsdir=${FONT_DIR}" \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
  -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p \
  -c:a aac -ar 48000 -ac 1 -b:a 128k \
  -r 30 -movflags +faststart \
  "${OUTPUT_FILE}"
```

### A.4 — `execution/whisper_align.py`

Whisper forced-alignment wrapper. Runs from `/opt/whisper-env/bin/python3`. Uses `whisper.transcribe(word_timestamps=True)`. Output is `word_timings.json` keyed by scene number.

---

## Appendix B — Quick reference: VG SHA + commit at fork time

Record this at the time you do the snapshot in §2.3:

```
Vision GridAI repo: https://github.com/akinwunmi-akinrimisi/vision-gridai-platform
Snapshot SHA:       <fill in at fork time>
Snapshot date:      <YYYY-MM-DD>
```

This is your point of reference for "what we inherited" vs "what we built."

---

## Appendix C — Operator runbooks inherited

These VG runbooks apply to us too:

- **Caption-burn service hung or 3hr timeout:** `systemctl restart caption-burn.service`, then re-trigger assembly only for the affected order.
- **n8n container stuck:** `docker compose restart n8n` from `/docker/n8n/`. Resume logic picks up automatically.
- **JWT rotation procedure:** see §10.4 above + VG's `infrastructure/auth-secrets` docs.
- **Disk full:** clean `/data/operscale-production/` (per-order subdirs older than delivered_at + 7 days). Then `docker system prune -af`.
- **Anthropic rate limit hit:** `WF_RETRY_WRAPPER` handles transient. If sustained, request a tier increase from Anthropic.

---

**End of fork manual.**

This document is the senior engineer's source of truth for the fork. It is meant to be read once cover-to-cover, then kept open during the 6-week build. If you find something missing or wrong, edit this file directly and commit; do not let the doc drift behind reality.

The single rule that holds the whole thing together: **inherit Vision GridAI's render core untouched, build everything around it new, and trust that the original team already paid the debugging cost so you don't have to.**
