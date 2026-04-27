#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Operscale Video Ads — Environment Setup + Skill Installer
# Run once on fresh Claude Code session: bash skills.sh
# Idempotent — safe to run multiple times.
# ═══════════════════════════════════════════════════════════════

set -e
echo "══════════════════════════════════════════════════"
echo "  Operscale Video Ads — Setup"
echo "══════════════════════════════════════════════════"
echo ""
echo "  Codebase name:    operscale-video-ads"
echo "  Customer brand:   plovera  (locked 2026-04-27 per ADR 0017)"
echo "  Build methodology: Superpowers (primary) + gstack (selective) + frontend-design"
echo ""

# ─── 1. VERIFY ENVIRONMENT ─────────────────────────────────

echo "▶ Checking environment..."

# Docker
if command -v docker &> /dev/null; then
  echo "  ✅ Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
  echo "  ❌ Docker not found"
fi

# n8n (shared with Vision GridAI on the same VPS)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q n8n; then
  echo "  ✅ n8n: running (shared instance with Vision GridAI)"
else
  echo "  ⚠️  n8n container not running — Operscale workflows will not fire"
fi

# FFmpeg (required version ≥ 4.3 for xfade)
if docker exec n8n-n8n-1 ffmpeg -version &> /dev/null 2>&1; then
  FF_VERSION=$(docker exec n8n-n8n-1 ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')
  echo "  ✅ FFmpeg in n8n container: $FF_VERSION"
elif command -v ffmpeg &> /dev/null; then
  echo "  ✅ FFmpeg: $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"
else
  echo "  ❌ FFmpeg not found — render core cannot run"
fi

# FFprobe (master clock measurements)
if docker exec n8n-n8n-1 ffprobe -version &> /dev/null 2>&1; then
  echo "  ✅ FFprobe: available in container"
elif command -v ffprobe &> /dev/null; then
  echo "  ✅ FFprobe: available"
else
  echo "  ❌ FFprobe not found — TTS duration measurement will fail"
fi

# Node.js (for Next.js marketing site)
if command -v node &> /dev/null; then
  echo "  ✅ Node.js: $(node --version)"
else
  echo "  ❌ Node.js not found — apps/web cannot build"
fi

# npm
if command -v npm &> /dev/null; then
  echo "  ✅ npm: $(npm --version)"
else
  echo "  ❌ npm not found"
fi

# Python 3.11 (LangGraph agent)
if command -v python3 &> /dev/null; then
  echo "  ✅ Python: $(python3 --version 2>&1 | awk '{print $2}')"
else
  echo "  ❌ Python 3 not found — apps/agent cannot run"
fi

# Caption burn service (host-side, port 9998, shared with VG)
echo ""
echo "▶ Checking caption-burn service (shared with Vision GridAI)..."
if curl -sf http://172.18.0.1:9998/health &> /dev/null 2>&1; then
  echo "  ✅ Caption burn: alive on port 9998"
elif command -v systemctl &> /dev/null && systemctl is-active --quiet caption-burn.service 2>/dev/null; then
  echo "  ✅ Caption burn: systemd unit active"
else
  echo "  ⚠️  Caption burn service not reachable. SSH to VPS and check:"
  echo "     systemctl status caption-burn.service"
  echo "     journalctl -u caption-burn.service -f"
fi

# Supabase (shared with VG)
echo ""
echo "▶ Checking Supabase (shared with Vision GridAI)..."
SUPABASE_URL="${SUPABASE_URL:-https://supabase.operscale.cloud}"
SUPABASE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${SUPABASE_URL}/rest/v1/" -H "apikey: ${SUPABASE_ANON_KEY:-none}" 2>/dev/null || echo "000")
if [ "$SUPABASE_STATUS" = "200" ] || [ "$SUPABASE_STATUS" = "401" ]; then
  echo "  ✅ Supabase: reachable at ${SUPABASE_URL}"
else
  echo "  ⚠️  Supabase: not reachable (HTTP ${SUPABASE_STATUS}). Check SUPABASE_URL in .env.agent"
fi

# Traefik (handles TLS for both products)
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q traefik; then
  echo "  ✅ Traefik: running (will route plovera.shop once DNS is set)"
else
  echo "  ⚠️  Traefik not running — TLS termination unavailable"
fi

# ─── 2. CINEMATIC FFMPEG CAPABILITIES ──────────────────────

echo ""
echo "▶ Checking FFmpeg cinematic filters (inherited from Vision GridAI render core)..."
if docker exec n8n-n8n-1 ffmpeg -filters 2>/dev/null | grep -q zoompan; then
  echo "  ✅ zoompan filter (Ken Burns motion)"
else
  echo "  ⚠️  zoompan filter not found — Ken Burns will fail"
fi
if docker exec n8n-n8n-1 ffmpeg -filters 2>/dev/null | grep -q "xfade"; then
  echo "  ✅ xfade filter (scene transitions, requires FFmpeg ≥ 4.3)"
else
  echo "  ⚠️  xfade filter not found — transitions will fail"
fi
if docker exec n8n-n8n-1 ffmpeg -filters 2>/dev/null | grep -q colorbalance; then
  echo "  ✅ colorbalance filter (7 colour mood profiles)"
else
  echo "  ⚠️  colorbalance filter not found"
fi
if docker exec n8n-n8n-1 ffmpeg -filters 2>/dev/null | grep -E "^ ... ass " &> /dev/null; then
  echo "  ✅ ass filter (kinetic typography subtitles via libass)"
else
  echo "  ⚠️  ass filter not found — kinetic captions will fail"
fi
if docker exec n8n-n8n-1 ffmpeg -filters 2>/dev/null | grep -q amix; then
  echo "  ✅ amix filter (music ducking under voiceover, volume=0.12)"
else
  echo "  ⚠️  amix filter not found"
fi

# ─── 3. n8n CREDENTIALS CHECKLIST ──────────────────────────

echo ""
echo "▶ n8n credentials required (the shared instance at n8n.srv1297445.hstgr.cloud)..."
echo ""
echo "  REUSED from Vision GridAI (do NOT duplicate; already exist):"
echo "    - Anthropic API Key (httpHeaderAuth) — used for Opus 4.7 + Haiku 4.5"
echo "    - Google Cloud Service Account (Chirp 3 HD TTS + Whisper alignment)"
echo "    - Fal API Key (httpHeaderAuth, prefix 'Key') — Seedream 4.5 + Seedance 2.0 Fast + PlayHT v3"
echo "    - Supabase API Key (httpHeaderAuth) — service-role for n8n, anon for marketing site"
echo "    - Dashboard Bearer Token (httpHeaderAuth, id KtMyWD7uJJBZYLjt) — webhook auth"
echo ""
echo "  OPERSCALE-ONLY (create these new):"
echo "    - HeyGen API Key (httpHeaderAuth) — Creative Pod tier only"
echo "    - Resend API Key (httpHeaderAuth) — transactional email (quote, delivery, follow-up)"
echo "    - Evolution API Key (httpHeaderAuth) — WhatsApp Business send/receive"
echo "    - Notion Integration Token (httpHeaderAuth) — gate review database"
echo ""
echo "  EXPLICITLY NOT NEEDED (these are Vision GridAI publishing concerns, not ours):"
echo "    - YouTube OAuth2  — we deliver to customer; customer posts"
echo "    - TikTok OAuth2   — same"
echo "    - Instagram OAuth2 — same"
echo "    - Apify / SerpAPI / pytrends / Reddit — we don't research niches"
echo ""
echo "  NOT IN n8n (lives in agent container env, NOT credential store):"
echo "    - PAYSTACK_SECRET_KEY — used to verify HMAC-SHA512 webhook signatures in apps/agent"
echo ""
echo "  Verify: log into n8n → Settings → Credentials"

# ─── 4. PUBLIC + LOBEHUB SKILL MANIFEST ────────────────────

echo ""
echo "▶ Public skill manifest (install via Claude Code → Settings → Skills)..."
echo ""
echo "  AUTO-ACTIVATE (Anthropic public skills — already loaded by /mnt/skills/public/):"
echo "    - frontend-design     — used for ANY React/Next.js work in apps/web"
echo "    - file-reading        — when user uploads files"
echo "    - pdf-reading         — for customer-uploaded brand decks"
echo "    - docx, xlsx, pptx    — for customer brand asset packages"
echo ""
echo "  LOBEHUB MARKETPLACE (relevant subset, install on demand):"
LOBEHUB_SKILLS=(
  "ffmpeg-core"
  "ffmpeg-video-toolkit"
  "ffmpeg-reference"
  "supabase-integration"
  "n8n-expression-syntax"
  "api-credentials-manager"
  "react-dashboard"
  "google-gemini-media"
  "automation-workflows"
)
for skill in "${LOBEHUB_SKILLS[@]}"; do
  echo "    - ${skill}"
done
echo ""
echo "  EXPLICITLY NOT INSTALLED (Vision GridAI used these; we don't):"
echo "    - youtube-uploader, youtube-data-api-v3"
echo "    - n8n-workflow-design (we don't write workflows from scratch — we adapt VG's)"
echo "    - n8n-custom-node-builder"
echo "    - google-sheets-cli, google-workspace-cli-gog"

# ─── 5. CREATE DIRECTORY STRUCTURE ─────────────────────────

echo ""
echo "▶ Creating project directory structure..."

DIRS=(
  "apps/web/src/app"
  "apps/web/src/components"
  "apps/web/src/lib"
  "apps/web/public"
  "apps/agent/src/states"
  "apps/agent/src/heygen"
  "apps/agent/src/voice"
  "apps/agent/src/consent"
  "apps/n8n-workflows/operscale"
  "packages/shared"
  "infra/docker"
  "infra/traefik"
  "supabase/migrations"
  "supabase/functions"
  "niche-briefs"
  "docs/adr"
  "docs/specs"
  "docs/diagrams"
  "docs/superpowers/specs"
  "docs/superpowers/plans"
  "_vendored_for_reference"
  "data"
)

for dir in "${DIRS[@]}"; do
  mkdir -p "$dir"
  echo "  📁 ${dir}/"
done

# ─── 6. INSTALL SUPERPOWERS (PRIMARY BUILD METHODOLOGY) ────

echo ""
echo "▶ Installing Superpowers (obra/superpowers) — PRIMARY build methodology..."

if [ -d ".claude/plugins/superpowers" ] || [ -f ".claude/plugins/superpowers/plugin.json" ]; then
    echo "  ⏭️  Superpowers already installed"
else
    echo "  Run in Claude Code: /plugin marketplace add obra/superpowers"
    echo "  Specs go to: docs/superpowers/specs/"
    echo "  Plans go to: docs/superpowers/plans/"
fi

echo ""
echo "  ⚠️  GSD (Get Shit Done) is DEPRECATED for this project."
echo "     Vision GridAI used GSD; we use Superpowers exclusively for new work."
echo "     Do NOT install GSD."

# ─── 7. INSTALL FRONTEND-DESIGN SKILL ──────────────────────

echo ""
echo "▶ frontend-design skill (Anthropic, auto-activates for React/UI work)..."

if [ -d "/mnt/skills/public/frontend-design" ] || [ -d ".claude/skills/frontend-design" ]; then
    echo "  ✅ frontend-design available"
else
    if command -v npx &> /dev/null; then
        echo "  Run: npx skills add https://github.com/anthropics/skills --skill frontend-design"
    else
        echo "  ⚠️  npx not found — install Node.js first"
    fi
fi

# ─── 8. INSTALL GSTACK (SELECTIVE COMMANDS ONLY) ───────────

echo ""
echo "▶ gstack — selective use only..."

if [ -d ".claude/skills/gstack" ]; then
    echo "  ⏭️  gstack already installed"
else
    if command -v npx &> /dev/null; then
        echo "  Run: npx skills add https://github.com/garrytan/gstack --skill gstack"
    fi
fi

echo ""
echo "  ⚠️  IMPORTANT: Use ONLY these 5 gstack commands. All others are off-limits:"
echo "    /qa       — Quality assurance after completing a deliverable"
echo "    /browse   — Research third-party APIs (Paystack docs, HeyGen API, etc.)"
echo "    /careful  — Precision mode for Paystack signature verification, JWT rotation"
echo "    /freeze   — Lock state before merging into main"
echo "    /review   — Full code review before phase complete"
echo ""
echo "  DO NOT use gstack /plan, /architect, /design — those conflict with Superpowers."

# ─── 9. INSTALL AGENCY AGENTS (61 SPECIALISTS) ─────────────

echo ""
echo "▶ Installing Agency Agents (61 AI specialists)..."

AGENTS_DIR="$HOME/.claude/agents"
if [ -d "$AGENTS_DIR" ] && [ "$(ls -1 $AGENTS_DIR/*.md 2>/dev/null | wc -l)" -gt 50 ]; then
  AGENT_COUNT=$(ls -1 "$AGENTS_DIR"/*.md 2>/dev/null | wc -l)
  echo "  ⏭️  Agency Agents already installed ($AGENT_COUNT agents at $AGENTS_DIR/)"
else
  if command -v git &> /dev/null; then
    echo "  Cloning agency-agents repo..."
    rm -rf /tmp/agency-agents
    git clone --depth 1 https://github.com/msitarzewski/agency-agents.git /tmp/agency-agents 2>/dev/null

    if [ -d "/tmp/agency-agents" ]; then
      mkdir -p "$AGENTS_DIR"
      for division in engineering design marketing product project-management testing support spatial-computing specialized; do
        if [ -d "/tmp/agency-agents/$division" ]; then
          cp /tmp/agency-agents/$division/*.md "$AGENTS_DIR/" 2>/dev/null || true
        fi
      done
      AGENT_COUNT=$(ls -1 "$AGENTS_DIR"/*.md 2>/dev/null | wc -l)
      echo "  ✅ Installed $AGENT_COUNT agents to $AGENTS_DIR/"
      rm -rf /tmp/agency-agents
    else
      echo "  ⚠️  Git clone failed. Install manually:"
      echo "     git clone https://github.com/msitarzewski/agency-agents.git /tmp/agency-agents"
      echo "     mkdir -p ~/.claude/agents && cp /tmp/agency-agents/*/*.md ~/.claude/agents/"
    fi
  else
    echo "  ⚠️  git not found"
  fi
fi

echo ""
echo "  Most-relevant agents for Operscale Video Ads:"
echo "    Engineering: Frontend Developer (apps/web), Backend Architect (apps/agent),"
echo "                 DevOps Automator (Traefik+Docker), Security Engineer (Paystack+JWT),"
echo "                 AI Engineer (LangGraph orchestration)"
echo "    Design:      UI Designer (marketing site), Brand Guardian (plovera identity stewardship),"
echo "                 Image Prompt Engineer (9:16 ad image generation)"
echo "    Marketing:   Content Creator (ad scripts), Growth Hacker (acquisition funnel)"
echo "    Product:     Sprint Prioritizer (35-day plan), Feedback Synthesizer (Gate 3 rejects)"
echo "    Testing:     API Tester (Paystack webhooks), Workflow Optimizer (gate SLAs),"
echo "                 Performance Benchmarker (render pipeline)"
echo "    Specialized: Agents Orchestrator (LangGraph coordination)"
echo ""
echo "  EXPLICITLY NOT relevant for Operscale (skip even if auto-activated):"
echo "    Marketing:   TikTok Strategist, Instagram Curator, Twitter Engager — we don't post for customers"
echo "    Product:     Trend Researcher — niches are static, not researched"

# ─── 10. CREATE OPERSCALE-SPECIFIC COMMANDS ────────────────

echo ""
echo "▶ Setting up Operscale-specific Claude Code commands..."

OPS_COMMANDS_DIR=".claude/commands/operscale"
mkdir -p "$OPS_COMMANDS_DIR"

if [ ! -f "$OPS_COMMANDS_DIR/workflow-rebind.md" ]; then
  cat > "$OPS_COMMANDS_DIR/workflow-rebind.md" << 'CMDEOF'
Take a Vision GridAI workflow JSON file path as input. Produce a rebound version for Operscale:

1. Webhook path: prefix with `/operscale/` (e.g., `/webhook/production/tts` → `/webhook/operscale/production/tts`)
2. Workflow name: prefix with `OPS_` (e.g., `WF_TTS_AUDIO` → `OPS_TTS_AUDIO`)
3. SQL FK rebind: `topic_id` → `video_id`, `topics` → `videos`, `project_id` → `order_id`, `projects` → `orders`
4. Path remap: `/tmp/production/` → `/tmp/operscale-production/`
5. Verify every Authorization header value starts with `=` (the missing-`=` expression trap)
6. Verify no inline credentials — must reference n8n credential by ID

Output the rebound JSON. Highlight any node that requires manual review.
CMDEOF
  echo "  ✅ /operscale:workflow-rebind"
fi

if [ ! -f "$OPS_COMMANDS_DIR/gate-card.md" ]; then
  cat > "$OPS_COMMANDS_DIR/gate-card.md" << 'CMDEOF'
Generate the Notion gate review card payload for a given gate transition.

Input: order_id, gate_number (0|1|2|3-bis|3), context (brief excerpt or render URL)
Output: Notion API request body with:
  - Title field: "[Gate N] <customer business name> — <tier>"
  - Status: pending
  - Decision dropdown options matching the gate
  - Brief context block
  - Direct link to the relevant render or script

For Gate 3-bis (avatar quality), include the photo URL and the 6 quality checkpoints.
For Gate 3, include the final render URL with a 7-day signed URL.
CMDEOF
  echo "  ✅ /operscale:gate-card"
fi

if [ ! -f "$OPS_COMMANDS_DIR/paystack-verify.md" ]; then
  cat > "$OPS_COMMANDS_DIR/paystack-verify.md" << 'CMDEOF'
Generate Paystack webhook signature verification code for the target language.

Input: language (typescript | python)
Output: handler that:
  1. Reads raw request body BEFORE any JSON parsing (parsing changes whitespace and breaks HMAC)
  2. Computes HMAC-SHA512 with PAYSTACK_SECRET_KEY
  3. Compares using constant-time comparison (crypto.timingSafeEqual / hmac.compare_digest)
  4. Returns 401 on mismatch with no body (don't leak signature info)
  5. On success, parses body and proceeds to event processing

Reminder: PAYSTACK_SECRET_KEY lives in apps/agent env vars, NOT in n8n credentials.
CMDEOF
  echo "  ✅ /operscale:paystack-verify"
fi

# ─── 11. INSTALL PROJECT SKILLS (THE CORE 12) ──────────────

echo ""
echo "▶ Installing Operscale project-specific skills..."

SKILLS_DIR="$HOME/.claude/skills/operscale-video-ads"
mkdir -p "$SKILLS_DIR"

# ─── Fork-related skills (most important) ──────────────

cat > "$SKILLS_DIR/vg-fork-aware.md" <<'EOF'
---
name: vg-fork-aware
description: When working with Vision GridAI inherited code (workflows, schema, render pipeline, caption burn), inherit unchanged. Don't refactor. Reference the fork manual.
---

# vg-fork-aware

This codebase is a fork of Vision GridAI. The render core (TTS → image gen → Ken Burns → caption assembly → caption burn) is inherited untouched. Built around it is a new customer-facing layer (intake, payment, agent orchestration, delivery).

## The single rule

Inherit Vision GridAI's render core untouched. Build everything around it new. Trust that the original team paid the debugging cost.

If you find yourself thinking "I could rewrite this in fewer lines / a more modern framework / a cleaner pattern" — stop. That instinct will cost the project 6 weeks. Wrap, don't refactor.

## The 12 inherited gotchas

1. `localhost` from inside an n8n container resolves to IPv6 ::1 — use 172.18.0.1
2. n8n Authorization headers MUST start with `=` to evaluate as expressions
3. Mismatched FFmpeg input fps causes silent truncation under -c copy
4. REPLICA IDENTITY FULL required on every Realtime-published table
5. Supabase JWT chain has 5 sync points (4 from VG + our container env)
6. Music volume is 0.12, not 0.5 — non-negotiable
7. Caption burn service runs on host (not container), 3-hour timeout
8. fal.ai async queue limits handled by WF_RETRY_WRAPPER
9. NODE_FUNCTION_ALLOW_BUILTIN=child_process required for Code nodes
10. Audio is the master clock — never derive duration from word count
11. Supabase writes are scene-by-scene, never batched
12. caption_highlight_word has shell-injection CHECK constraint

## Reference

`docs/VISION_GRIDAI_FORK_MANUAL.md` — the comprehensive 1764-line reference. This skill is the lighthouse, not the map.
EOF

cat > "$SKILLS_DIR/vg-workflow-rebind.md" <<'EOF'
---
name: vg-workflow-rebind
description: When importing or modifying a Vision GridAI workflow JSON, follow the rebind procedure to namespace it for Operscale.
---

# vg-workflow-rebind

When importing a VG workflow into our n8n instance:

## Steps

1. **Webhook path namespace.** Every webhook path becomes `/webhook/operscale/...` (not just `/webhook/...`). This avoids collision with VG's running workflows.

2. **Workflow name prefix.** Rename in n8n UI: `WF_X` → `OPS_X`. Keeps both products' workflows discoverable.

3. **FK rebinding.** SQL queries inside workflow nodes:
   - `topic_id` → `video_id`
   - `topics` → `videos`
   - `project_id` → `order_id`
   - `projects` → `orders`

4. **Authorization headers MUST start with `=`.** This is the missing-`=` expression trap. n8n string parameters that begin with `=` evaluate as expressions; without the `=`, the literal `{{ $env.X }}` is sent over the wire and rejected.

5. **No inline credentials.** All authentication uses the n8n credential store (httpHeaderAuth or supabaseApi credential types). Inline Authorization headers are blocked by lint rule CRED-01.

6. **Path remap for scratch dir.** Replace `/tmp/production/` references with `/tmp/operscale-production/` (matches our `/data/operscale-production` mount).

## Lint enforcement

`tools/lint_n8n_workflows.py` catches violations of #4 and #5 at CI time. Don't disable.

## Reference

`docs/VISION_GRIDAI_FORK_MANUAL.md` §6.5 (workflow import) and §10.3 (the missing-`=` trap).
EOF

cat > "$SKILLS_DIR/prune-commit.md" <<'EOF'
---
name: prune-commit
description: For Day 1's mass deletion of unused VG surface area, do it as a single commit. Don't trickle-delete.
---

# prune-commit

The Day 1 Prune Commit is a single commit that removes ~60% of VG's surface area: YouTube/social workflows, niche research, 3-pass long-form scripting, analytics, intelligence layer, Australia overlay.

## Why a single commit

Trickle-deletion creates ambiguous in-between states where some workflows reference deleted dependencies. You spend 3 days chasing phantom errors that didn't exist before you started "incrementally cleaning up."

## The procedure

1. Read `docs/VISION_GRIDAI_FORK_MANUAL.md` §3 in full
2. Run all the `rm -rf` and `rm -f` commands from §3.1
3. Move VG migrations to `_vendored_for_reference/`
4. `git add -A && git commit` with the commit message template from §3.4
5. Push

After this commit: do NOT pull more files from Vision GridAI. Anything you discover later that you wish you'd kept can be cherry-picked manually with full context, not bulk-imported.

## What stays untouched

The render core: WF_TTS_AUDIO, WF_IMAGE_GENERATION, WF_KEN_BURNS, WF_CAPTIONS_ASSEMBLY, WF_RETRY_WRAPPER, the host-side caption burn service. See fork manual §3.3 for the keep-list.
EOF

cat > "$SKILLS_DIR/jwt-chain-rotation.md" <<'EOF'
---
name: jwt-chain-rotation
description: When rotating any JWT or shared secret, follow the 5-sync-point checklist or face silent failures.
---

# jwt-chain-rotation

The Supabase JWT secret has 5 sync points across the platform. Skipping any one produces a different silent failure mode.

## The 5 sync points (in order)

1. `/docker/supabase/.env` — JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY → restart Supabase stack
2. `_realtime.tenants.jwt_secret` (DB rows × 2: `realtime` and `realtime-dev`)
3. `/docker/supabase/supabase/kong.yml` → `docker exec supabase-kong-1 kong reload`
4. `/docker/n8n/docker-compose.override.yml` env vars → restart n8n
5. **`/docker/operscale-video-ads/docker-compose.override.yml`** → `docker compose up -d`

Plus optionally:
6. VG's dashboard `/opt/dashboard/.env` if rebuilt

## Skip-symptoms

- Skip 1: nothing works
- Skip 2: WSS connects then 401 jwt invalid (Realtime broken)
- Skip 3: Kong serves cached old keys
- Skip 4: n8n PostgREST calls return JWSInvalidSignature
- Skip 5: our agent + web containers can't read/write Supabase

## Rotation discipline

- Backup current state to `/root/backups/operscale-deploy-$(date -u +%Y%m%dT%H%M%SZ)/` first
- Update `/root/operscale_keys.env` (chmod 600)
- Run through the 5 syncs in order
- Health-check every layer after

## Reference

`security.md` §JWT-chain, fork manual §10.4.
EOF

# ─── Customer-flow skills ──────────────────────────────

cat > "$SKILLS_DIR/niche-aware-prompting.md" <<'EOF'
---
name: niche-aware-prompting
description: When generating angles, scripts, or quote messages, load the relevant niche brief first.
---

# niche-aware-prompting

The prompts in `prompt_configs` are context-skinny by design. The niche briefs in `niche-briefs/<niche>.md` carry the operational knowledge: tone, regulatory red lines, audience pain points, hooks that work in that niche.

## Procedure

1. Read `niche-briefs/<niche>.md` (real-estate, education, fashion-ecom, fintech, health, restricted)
2. Construct prompt = system prompt from prompt_configs + brief context + niche-brief excerpt
3. Generate
4. Log to `llm_calls` with niche tag

For restricted niches, gate review fires at Gate 0 with a "restricted-niche detected" warning.

## Reference

`niche-briefs/`, `ad-creative-playbook.md`.
EOF

cat > "$SKILLS_DIR/paystack-integration.md" <<'EOF'
---
name: paystack-integration
description: When implementing Paystack payment, signature verification is non-negotiable. Idempotency via paystack_tx_ref UNIQUE.
---

# paystack-integration

## Webhook signature verification (HMAC-SHA512)

Every Paystack webhook MUST pass HMAC-SHA512 signature verification before any side effect. Skipping this means anyone can fake a payment.

```typescript
const computedSignature = crypto
  .createHmac('sha512', process.env.PAYSTACK_SECRET_KEY!)
  .update(rawBody)
  .digest('hex');

if (computedSignature !== signature) {
  return new Response('Invalid signature', { status: 401 });
}
```

Always read `rawBody` BEFORE JSON parsing — JSON parsing reformats whitespace and breaks HMAC.

## Idempotency

`payments.paystack_tx_ref` has a UNIQUE constraint. Duplicate webhook deliveries from Paystack (which happen) are no-ops at the DB layer.

## NGN/kobo

Paystack uses kobo (1 NGN = 100 kobo). All amounts in `payments.amount_kobo` and `orders.amount_paid_kobo` are stored in kobo. Display logic divides by 100 for human-readable NGN.

## Reference

`security.md` §paystack-webhook-security, `docs/specs/paystack-integration.md`.
EOF

cat > "$SKILLS_DIR/notion-gate-review.md" <<'EOF'
---
name: notion-gate-review
description: For gate workflows. Notion is the gate UI; we don't build a custom dashboard for v1.
---

# notion-gate-review

The 4 gates (0, 1, 2, 3) and the 1 branch gate (3-bis) all surface in a single Notion DB. Founder reviews on phone or laptop, clicks Approve/Reject/Edit, Notion automation POSTs the decision back to our webhook.

## Why Notion

Per ADR 0016: we don't build a custom React dashboard for v1. Notion gives us:
- Mobile-friendly review UI on day 1
- Built-in collaboration if we hire a reviewer
- Audit trail via Notion's row history

## Schema

See `docs/specs/notion-gate-review.md` for the canonical Notion DB schema and automation specifics.

## Decision flow

1. Agent transitions order to `gate_N_review`
2. `WF_OPS_GATE_NOTIFY` POSTs to Notion API, creates a card
3. Founder edits the Decision field on the card
4. Notion automation POSTs to `/webhook/operscale/gate/resume`
5. `WF_OPS_GATE_RESUME` writes to `gate_decisions`
6. Agent picks up via Realtime subscription on `gate_decisions`
EOF

cat > "$SKILLS_DIR/langgraph-node.md" <<'EOF'
---
name: langgraph-node
description: When adding a new state to the agent's state machine, ensure the contract: write pipeline_stage first, then side effect.
---

# langgraph-node

Every LangGraph state in the agent must:

1. **Write `orders.pipeline_stage` BEFORE any side effect.** If the agent crashes after writing the stage but before the side effect, restart picks up at that stage and idempotently re-fires.

2. **Be idempotent on restart.** Re-running a state should produce the same outcome, not duplicate work.

3. **Log to `production_log`** for major state events.

4. **Log to `llm_calls`** when calling Anthropic with input tokens, output tokens, cost, model, duration.

5. **Use Supabase Realtime for waits.** Never busy-poll. The agent listens for `gate_decisions` row inserts and `videos.assembly_status` updates.

## Reference

`AGENT.md`, `docs/diagrams/order-lifecycle.mmd`.
EOF

cat > "$SKILLS_DIR/gate-reviewer.md" <<'EOF'
---
name: gate-reviewer
description: For any gate-related workflow. Know the 4 gates + 1 branch gate, their SLAs, their decision trees.
---

# gate-reviewer

The 4 main gates plus the avatar-quality branch gate are documented in `gates-and-approvals.md`.

## Gate fast-reference

| Gate | Reviewing | SLA | Decisions |
|---|---|---|---|
| 0 | Brief sanity check | First business hours | approve / reject / edit |
| 1 | Angle approval (3 candidates) | ≤ 4 business hours | pick angle 1/2/3 / regenerate / reject all |
| 2 | Full script | ≤ 12 business hours | approve / edit / reject / pause |
| 3-bis | Avatar photo quality (Creative Pod custom-avatar only) | ≤ 4 hours | pass / reject / override-with-warning |
| 3 | Final render | ≤ 6 hours | approve / regen scene N / regen from script / refund |

## Bundling

For Pilot tier, Gate 1 + Gate 2 are bundled into a single Notion card. Standard and Creative Pod keep them separate.

## Reference

`gates-and-approvals.md`.
EOF

# ─── Cross-cutting skills ──────────────────────────────

cat > "$SKILLS_DIR/cost-monitor.md" <<'EOF'
---
name: cost-monitor
description: For any new LLM call or external API call. Log to llm_calls, respect tier COGS targets.
---

# cost-monitor

## Always log

Every Anthropic call writes a row to `llm_calls`:
- order_id, video_id, node_name (e.g., 'generate_angles')
- model ('claude-opus-4-7' or 'claude-haiku-4-5')
- input_tokens, output_tokens
- cost_usd
- duration_ms
- called_at

This enables per-order cost reconciliation:
```sql
SELECT order_id, SUM(cost_usd) FROM llm_calls WHERE order_id = ? GROUP BY order_id
```

## Tier COGS targets

- Pilot: < $3 (Claude $2 + TTS $0.10 + images $0.24 + render $0)
- Standard: < $6 (Claude $4 + TTS $0.10 + images $0.36 + i2v ~$0.50 + music $0.02)
- Creative Pod: < $25 worst case (3 videos × Standard cost + optional HeyGen $0–15 + optional voice cloning $0–2)

## 15% margin guard

Supervisor cron flags any order where `total_cost_usd > 0.15 * (amount_paid_kobo / 100 / 1650)` (rough NGN-to-USD margin guard). Order pauses for founder review.

## Reference

`AGENT.md` §cost-budgeting.
EOF

cat > "$SKILLS_DIR/voice-cloning.md" <<'EOF'
---
name: voice-cloning
description: For implementing the optional Creative Pod voice cloning via fal.ai PlayHT v3.
---

# voice-cloning

Creative Pod tier offers optional voice cloning via fal.ai PlayHT v3.

## Voice sample requirements

- 60 seconds of clean audio
- Single speaker (no overlap)
- No background music or noise
- Clear pronunciation
- WAV or MP3 format

## Consent

Customer signs voice-clone consent at upload (separate from photo consent for HeyGen avatar). Consent text logged in `order_consent`.

## Cost

~$2 per video using cloned voice. No upcharge to customer (included in Creative Pod tier).

## Reference

`docs/specs/voice-cloning.md`.
EOF

cat > "$SKILLS_DIR/heygen-integration.md" <<'EOF'
---
name: heygen-integration
description: For implementing Creative Pod avatar features. Custom avatar + multi-character (cap at 2).
---

# heygen-integration

Creative Pod tier offers two HeyGen-driven options:

## Custom avatar from photo

Customer uploads photo, signs consent. Photo passes Gate 3-bis quality check. HeyGen renders an avatar that lip-syncs to the script.

Cost: ~$5-15 per video depending on length. No upcharge to customer.

## Multi-character dialogue

Up to 2 speakers per video. Camera cuts between them at speaker turns. Hard cap at 2 — 3+ speakers requires custom quote (per ADR 0012).

Per-segment HeyGen render: ~3 min per segment. Parallelised across speakers.

## Quality check (Gate 3-bis)

Auto-checks before HeyGen render starts:
- Front-facing? (face detection)
- Sharpness adequate? (Laplacian variance threshold)
- Brightness adequate?
- Single subject?
- No obstructions?
- Consent text actually signed?

3 failed photos triggers founder escalation.

## Reference

`docs/specs/heygen-integration.md`, `gates-and-approvals.md` §gate-3-bis.
EOF

echo "  ✅ 12 project skills installed at $SKILLS_DIR"

# ─── 12. CREATE .ENV TEMPLATES ─────────────────────────────

echo ""
echo "▶ Creating .env templates (chmod 600 — never commit)..."

if [ ! -f .env.agent ]; then
  cat > .env.agent <<'EOF'
# ═══════════════════════════════════════════════════
# Operscale Video Ads — Agent Container Environment
# Loaded by /docker/operscale-video-ads/docker-compose.override.yml
# Path on VPS: /docker/operscale-video-ads/.env.agent (chmod 600)
# ═══════════════════════════════════════════════════

# ─── Anthropic ──────────────────────────────────────
ANTHROPIC_API_KEY=sk-ant-…

# ─── Supabase (shared instance with Vision GridAI) ──
SUPABASE_URL=https://supabase.operscale.cloud
SUPABASE_SERVICE_ROLE_KEY=eyJ…
SUPABASE_ANON_KEY=eyJ…

# ─── n8n (shared instance) ──────────────────────────
N8N_WEBHOOK_BASE=https://n8n.srv1297445.hstgr.cloud/webhook
DASHBOARD_API_TOKEN=…  # Same token VG uses; do not generate a new one

# ─── External services ─────────────────────────────
FAL_KEY=…                # Seedream 4.5 + Seedance 2.0 Fast + PlayHT v3
HEYGEN_API_KEY=…         # Creative Pod tier only
PAYSTACK_SECRET_KEY=sk_live_…
RESEND_API_KEY=re_…
EVOLUTION_API_KEY=…      # WhatsApp send/receive
EVOLUTION_API_BASE=https://evolution.…
NOTION_API_KEY=secret_…  # Gate review database

# ─── Brand identity (locked per ADR 0017) ──────────
BRAND_NAME=plovera
BRAND_DOMAIN=plovera.shop
FOUNDER_EMAIL=akinwunmi@operscale.ng
FOUNDER_WHATSAPP=+447592233052

# ─── Note ───────────────────────────────────────────
# ELEVENLABS_API_KEY is intentionally absent. We use Chirp 3 HD for TTS
# and fal.ai PlayHT v3 for cloning (per ADR 0009 + ADR 0010).
EOF
  echo "  ✅ Created .env.agent (edit with actual keys)"
  chmod 600 .env.agent 2>/dev/null || true
else
  echo "  ⏭️  .env.agent already exists"
fi

if [ ! -f .env.web ]; then
  cat > .env.web <<'EOF'
# ═══════════════════════════════════════════════════
# Operscale Video Ads — Marketing Site (apps/web)
# Public-facing keys only. Service role keys belong in .env.agent.
# ═══════════════════════════════════════════════════

NEXT_PUBLIC_SUPABASE_URL=https://supabase.operscale.cloud
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ…
NEXT_PUBLIC_PAYSTACK_PUBLIC_KEY=pk_live_…

# Brand identity (locked per ADR 0017)
NEXT_PUBLIC_BRAND_NAME=plovera
NEXT_PUBLIC_BRAND_DOMAIN=plovera.shop

# Server-side only (Next.js API routes can read; browser bundle cannot)
SUPABASE_SERVICE_ROLE_KEY=eyJ…
PAYSTACK_SECRET_KEY=sk_live_…  # For server-side webhook signature verification
EOF
  echo "  ✅ Created .env.web"
else
  echo "  ⏭️  .env.web already exists"
fi

# ─── 13. SUPABASE MIGRATION TEMPLATE ───────────────────────

echo ""
echo "▶ Creating Supabase migration 001_initial.sql..."

if [ ! -f supabase/migrations/001_initial.sql ]; then
  cat > supabase/migrations/001_initial.sql <<'EOSQL'
-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Initial Schema (12 tables)
-- See docs/VISION_GRIDAI_FORK_MANUAL.md §5 for design rationale.
-- ═══════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Customers
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  whatsapp_phone TEXT,
  full_name TEXT,
  business_name TEXT,
  website_or_handle TEXT,
  source TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_order_at TIMESTAMPTZ,
  marketing_opt_in BOOLEAN DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);

-- Briefs (raw form submissions)
CREATE TABLE IF NOT EXISTS briefs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  niche TEXT NOT NULL,
  business_name TEXT,
  website_url TEXT,
  product_or_service TEXT,
  ideal_customer TEXT,
  unique_value_prop TEXT,
  problem_solved TEXT,
  current_marketing TEXT,
  budget_for_ads_monthly_ngn INTEGER,
  preferred_tone TEXT,
  must_include TEXT,
  must_avoid TEXT,
  example_competitor TEXT,
  call_to_action TEXT,
  niche_specific_followup JSONB,
  raw_form_payload JSONB,
  save_token TEXT UNIQUE,
  submitted_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_briefs_customer ON briefs(customer_id);
CREATE INDEX IF NOT EXISTS idx_briefs_save_token ON briefs(save_token);

-- Orders
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id),
  brief_id UUID NOT NULL REFERENCES briefs(id),
  tier TEXT NOT NULL CHECK (tier IN ('pilot', 'standard', 'creative_pod')),
  amount_paid_kobo INTEGER NOT NULL,
  paystack_tx_ref TEXT UNIQUE,
  niche TEXT NOT NULL,
  production_register TEXT,
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
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_stage ON orders(pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at DESC);

-- Videos (1 row per Pilot/Standard order; 3 rows per Creative Pod)
CREATE TABLE IF NOT EXISTS videos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  video_number INTEGER NOT NULL,
  approved_angle JSONB,
  script_json JSONB,
  scene_count INTEGER,
  duration_seconds INTEGER,
  drive_video_url TEXT,
  delivered_url TEXT,
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
CREATE INDEX IF NOT EXISTS idx_videos_order ON videos(order_id);

-- Scenes (column names cloned VERBATIM from VG — render workflows reference them by name)
CREATE TABLE IF NOT EXISTS scenes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  scene_number INTEGER NOT NULL,
  scene_id TEXT NOT NULL,
  narration_text TEXT,
  image_prompt TEXT,
  visual_type TEXT,
  emotional_beat TEXT,
  chapter TEXT,
  audio_duration_ms INTEGER,
  audio_file_drive_id TEXT,
  audio_file_url TEXT,
  start_time_ms BIGINT,
  end_time_ms BIGINT,
  image_url TEXT,
  image_drive_id TEXT,
  video_url TEXT,
  video_drive_id TEXT,
  audio_status TEXT DEFAULT 'pending',
  image_status TEXT DEFAULT 'pending',
  video_status TEXT DEFAULT 'pending',
  clip_status TEXT DEFAULT 'pending',
  composition_prefix TEXT,
  color_mood TEXT,
  zoom_direction TEXT,
  transition_to_next TEXT,
  caption_highlight_word TEXT
    CHECK (caption_highlight_word IS NULL
           OR caption_highlight_word !~ '[`$|;<>&\\]'),
  selective_color_element TEXT,
  skipped BOOLEAN DEFAULT false,
  skip_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_scenes_video ON scenes(video_id);
CREATE INDEX IF NOT EXISTS idx_scenes_order ON scenes(order_id);
CREATE INDEX IF NOT EXISTS idx_scenes_status ON scenes(video_id, audio_status);

-- Production registers
CREATE TABLE IF NOT EXISTS production_registers (
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

INSERT INTO production_registers (register_id, name, short_description, accent_color_hex, config) VALUES
('OPERSCALE_01_DOCUMENTARY',
 'Documentary',
 'Default cinematic style for Pilot, Standard, and most Creative Pod orders',
 '#B4532A',
 '{"image_anchors":"muted color with controlled warmth, subtle film grain, 35mm look, rule of thirds, generous negative space, shallow depth of field","negative_additions":"no text overlays, no watermarks, no logos in image","tts_voice":"en-NG-Standard-A","tts_speaking_rate":0.95,"music_bpm_min":80,"music_bpm_max":100,"music_mood_keywords":["uplifting","cinematic","moderate energy"],"ken_burns_default_preset":"slow_push","typical_scene_length_sec":4,"transition_duration_ms":400,"font_family":"Inter"}'::jsonb),
('OPERSCALE_02_AVATAR_LED',
 'Avatar-Led',
 'Creative Pod only — talking-head avatar via HeyGen',
 '#C9994A',
 '{"image_anchors":"studio-lit talking head, high-contrast subject, clean professional background","negative_additions":"no scene cuts within shot, no environmental distractions","tts_voice":"en-NG-Standard-A","tts_speaking_rate":1.00,"music_bpm_min":90,"music_bpm_max":110,"music_mood_keywords":["energetic","modern","confident"],"ken_burns_default_preset":"static","typical_scene_length_sec":6,"transition_duration_ms":250,"font_family":"Inter"}'::jsonb)
ON CONFLICT (register_id) DO NOTHING;

-- Prompt configs
CREATE TABLE IF NOT EXISTS prompt_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  niche TEXT NOT NULL,
  prompt_type TEXT NOT NULL,
  prompt_text TEXT NOT NULL,
  version INTEGER DEFAULT 1,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (niche, prompt_type, version)
);

-- Production log
CREATE TABLE IF NOT EXISTS production_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  customer_id UUID REFERENCES customers(id),
  stage TEXT NOT NULL,
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_log_order ON production_log(order_id);
CREATE INDEX IF NOT EXISTS idx_log_video ON production_log(video_id);

-- Payments (Paystack)
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  customer_id UUID NOT NULL REFERENCES customers(id),
  paystack_tx_ref TEXT NOT NULL UNIQUE,
  amount_kobo INTEGER NOT NULL,
  currency TEXT DEFAULT 'NGN',
  status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),
  payment_method TEXT,
  webhook_payload JSONB,
  paid_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  refund_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);

-- Gate decisions (founder audit)
CREATE TABLE IF NOT EXISTS gate_decisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  gate_number TEXT NOT NULL CHECK (gate_number IN ('0', '1', '2', '3-bis', '3')),
  decision TEXT NOT NULL CHECK (decision IN ('approved', 'rejected', 'edit_requested')),
  feedback TEXT,
  decided_by TEXT NOT NULL,
  decided_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gates_order ON gate_decisions(order_id);

-- Order consent (Creative Pod custom avatar + voice cloning)
CREATE TABLE IF NOT EXISTS order_consent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  consent_type TEXT NOT NULL CHECK (consent_type IN ('voice_clone', 'face_avatar', 'both')),
  photo_storage_url TEXT,
  voice_sample_storage_url TEXT,
  consent_text_version TEXT NOT NULL,
  consent_text_hash TEXT NOT NULL,
  signed_at TIMESTAMPTZ DEFAULT now(),
  signed_via TEXT DEFAULT 'notion_form',
  ip_address INET,
  revocation_at TIMESTAMPTZ,
  quality_check_status TEXT DEFAULT 'pending'
    CHECK (quality_check_status IN ('pending', 'passed', 'rejected', 'overridden_with_warning'))
);

-- LLM call audit
CREATE TABLE IF NOT EXISTS llm_calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id),
  video_id UUID REFERENCES videos(id),
  node_name TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_usd DECIMAL(8,6),
  duration_ms INTEGER,
  called_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_llm_calls_order ON llm_calls(order_id);

-- Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE videos;
ALTER PUBLICATION supabase_realtime ADD TABLE scenes;
ALTER PUBLICATION supabase_realtime ADD TABLE production_log;
ALTER PUBLICATION supabase_realtime ADD TABLE gate_decisions;

-- REPLICA IDENTITY FULL (gotcha #4 from fork manual)
ALTER TABLE orders REPLICA IDENTITY FULL;
ALTER TABLE videos REPLICA IDENTITY FULL;
ALTER TABLE scenes REPLICA IDENTITY FULL;
ALTER TABLE production_log REPLICA IDENTITY FULL;
ALTER TABLE gate_decisions REPLICA IDENTITY FULL;

-- RLS lockdown
DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'customers','briefs','orders','videos','scenes','production_log',
    'payments','gate_decisions','order_consent','llm_calls',
    'production_registers','prompt_configs'
  ])
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I_anon_deny ON %I AS RESTRICTIVE FOR ALL TO anon USING (false)', t, t);
    EXECUTE format('CREATE POLICY %I_service_role_all ON %I AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true)', t, t);
  END LOOP;
END $$;
EOSQL
  echo "  ✅ Created supabase/migrations/001_initial.sql"
else
  echo "  ⏭️  Migration file already exists, skipping creation"
fi

# ─── 14. AUTO-RUN MIGRATION (if Supabase reachable) ────────

echo ""
echo "▶ Running Supabase migration (against shared instance)..."

SUPABASE_CONTAINER=""
for name in supabase-db-1 supabase-db supabase_db supabase-postgres; do
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
    SUPABASE_CONTAINER="$name"
    break
  fi
done

if [ -n "$SUPABASE_CONTAINER" ]; then
  echo "  Found Supabase container: $SUPABASE_CONTAINER"
  if docker exec -i "$SUPABASE_CONTAINER" psql -U postgres < supabase/migrations/001_initial.sql 2>&1 | tail -5; then
    echo "  ✅ Migration applied (Operscale tables now coexist with Vision GridAI tables)"
  else
    echo "  ⚠️  Migration had errors. Run manually:"
    echo "     docker exec -i $SUPABASE_CONTAINER psql -U postgres < supabase/migrations/001_initial.sql"
  fi
else
  echo "  ⚠️  No Supabase container found locally."
  echo "     SSH to VPS: ssh -i ~/.ssh/id_ed25519_antigravity root@srv1297445.hstgr.cloud"
  echo "     Then: docker exec -i supabase-db-1 psql -U postgres < supabase/migrations/001_initial.sql"
fi

# ─── 15. MARKETING SITE PACKAGE.JSON ───────────────────────

echo ""
echo "▶ Creating apps/web/package.json (Next.js 15 + Tailwind)..."

if [ ! -f apps/web/package.json ]; then
  cat > apps/web/package.json <<'EOF'
{
  "name": "operscale-video-ads-web",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "15.0.0",
    "react": "19.0.0",
    "react-dom": "19.0.0",
    "@supabase/supabase-js": "^2.39.0",
    "@supabase/ssr": "^0.1.0",
    "lucide-react": "^0.400.0",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.0",
    "tailwind-merge": "^2.2.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "@types/node": "^20.10.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32",
    "tailwindcss": "^3.4.0",
    "eslint": "^8.56.0",
    "eslint-config-next": "15.0.0"
  }
}
EOF
  echo "  ✅ Created apps/web/package.json"
else
  echo "  ⏭️  apps/web/package.json already exists"
fi

# ─── 16. TRAEFIK LABELS DOCUMENTATION ──────────────────────

echo ""
echo "▶ Creating Traefik label snippet for plovera.shop..."

if [ ! -f infra/traefik/operscale-labels.yml ]; then
  cat > infra/traefik/operscale-labels.yml <<'EOF'
# Traefik labels for the Operscale web container.
# Paste these into /docker/operscale-video-ads/docker-compose.yml under the `web` service.
# Domain is locked: plovera.shop (per ADR 0017).

labels:
  - "traefik.enable=true"
  - "traefik.http.routers.operscale-web.rule=Host(`plovera.shop`) || Host(`www.plovera.shop`)"
  - "traefik.http.routers.operscale-web.tls=true"
  - "traefik.http.routers.operscale-web.tls.certresolver=letsencrypt"
  - "traefik.http.routers.operscale-web.entrypoints=websecure"
  - "traefik.http.services.operscale-web.loadbalancer.server.port=3000"
EOF
  echo "  ✅ Created infra/traefik/operscale-labels.yml"
else
  echo "  ⏭️  Traefik labels file already exists"
fi

# ─── 17. TABLE EXISTENCE CHECKS ────────────────────────────

echo ""
echo "▶ Checking Operscale Supabase tables exist..."
for table in customers briefs orders videos scenes production_log payments gate_decisions order_consent llm_calls production_registers prompt_configs; do
    RESP=$(curl -s -o /dev/null -w "%{http_code}" \
        "${SUPABASE_URL}/rest/v1/${table}?select=id&limit=1" \
        -H "apikey: ${SUPABASE_ANON_KEY:-none}" \
        -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-none}" 2>/dev/null || echo "000")
    if [ "$RESP" = "200" ] || [ "$RESP" = "401" ]; then
        echo "  ✅ $table"
    else
        echo "  ❌ $table — HTTP ${RESP} (run migration 001)"
    fi
done

# Cinematic fields on scenes (inherited from VG)
echo ""
echo "▶ Checking cinematic fields on scenes table..."
SCENE_CHECK=$(curl -s "${SUPABASE_URL}/rest/v1/scenes?select=color_mood,zoom_direction,transition_to_next&limit=1" \
    -H "apikey: ${SUPABASE_ANON_KEY:-none}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-none}" 2>/dev/null || echo "error")
if echo "$SCENE_CHECK" | grep -q "color_mood"; then
    echo "  ✅ Cinematic fields present (color_mood, zoom_direction, transition_to_next)"
else
    echo "  ❌ Cinematic fields missing — migration 001 not applied or partial"
fi

# ─── 18. SKILL DIRECTORY LISTING ───────────────────────────

echo ""
echo "▶ Project skills installed:"
if [ -d "$SKILLS_DIR" ]; then
  ls -1 "$SKILLS_DIR" | sed 's/^/  - /'
else
  echo "  ⚠️  Skills directory empty — re-run this script"
fi

# ─── DONE ───────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════"
echo "  ✅ Setup complete!"
echo ""
echo "  Next steps:"
echo "  1. Edit .env.agent + .env.web with actual keys (chmod 600)."
echo "  2. Brand is locked: plovera / plovera.shop (ADR 0017)"
echo "     If you need to change it, write a superseding ADR."
echo "  3. Read docs/VISION_GRIDAI_FORK_MANUAL.md cover-to-cover before"
echo "     touching the render core."
echo "  4. Read CLAUDE.md for the build methodology rules."
echo "  5. Read AGENT.md for the LangGraph state machine."
echo "  6. Verify Agency Agents installed: ls ~/.claude/agents/ | wc -l"
echo "  7. Install Superpowers: /plugin marketplace add obra/superpowers"
echo "  8. Begin Day 1 of implementation.md — the Prune Commit."
echo ""
echo "  Build methodology reminders:"
echo "    PRIMARY:    Superpowers (specs → plans → subagent execution)"
echo "    SELECTIVE:  gstack — ONLY /qa /browse /careful /freeze /review"
echo "    AUTO:       frontend-design (read SKILL.md before any React work)"
echo "    AUTO:       Agency Agents (61 specialists, context-activated)"
echo "    DEPRECATED: GSD — do not install"
echo "══════════════════════════════════════════════════"
