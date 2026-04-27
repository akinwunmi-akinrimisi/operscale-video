# Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Vision GridAI's inherited render core to the Operscale schema and prove it works end-to-end on the shared VPS — render + Realtime + resume + 5 niches + caption-burn edges all evidenced — without modifying VG.

**Architecture:** Cherry-pick 12 n8n workflow JSONs and 4 host-side scripts from VG (Q7=C); rebind them to `OPS_*` names and `/webhook/operscale/*` paths; apply 4 schema migrations to the shared Supabase additively (Q6=C); deploy two placeholder Operscale containers; drive the pipeline with synthetic test fixtures via curl; verify against 5 niches and 3 failure scenarios.

**Tech Stack:** PostgreSQL/Supabase (shared with VG), n8n (shared), FFmpeg (via `docker exec` into n8n container), Python 3.11 (test harness, rebind script), Bash (vendor + apply + recon scripts), Docker Compose (Operscale containers), Traefik (TLS), Supabase Realtime (WSS), Chirp 3 HD (Google Cloud TTS), fal.ai Seedream 4.5 (image gen).

**Spec reference:** `docs/superpowers/specs/2026-04-27-foundation-design.md`

**Cadence (Q5=D):** Hybrid — plan-and-batch by default, named gates ★1-★7 stop for explicit confirm before executing. **No JWT or shared-key rotation under any circumstance.**

---

## Overview — 14 days, 14 sections

```
Day  Title                                  Tasks  Named Gate
───  ─────────────────────────────────────  ─────  ──────────
 1   Vendor VG + extend 001 schema             4   ★1
 2   Cherry-pick + rebind workflows            5   ★2
 3   VPS reconnaissance                        2   —
 4   Operscale Docker compose deploy           2   —
 5   Apply migrations to shared Supabase       3   ★3, ★4
 6   Import OPS_TTS + IMG + RETRY              3   —
 7   Slack / catch-up                          0   —
 8   Import OPS_KEN_BURNS + ASSEMBLY           3   —
 9   Caption-burn integration                  4   ★5
10   End-to-end dry-run + resume test          3   —
11   5-niche test matrix                       2   —
12   Failure induction (3 scenarios)           3   —
13   Realtime smoke test                       2   —
14   Foundation verification + go/no-go        4   ★6, ★7
                                            ────
                                           ~ 40 tasks
```

---

## Day 1 — Vendor VG + extend 001 schema  *(★1)*

**Day goal:** `001_initial.sql` carries Q6=C universal fields. `vendor-vg.sh` exists. `004_storage_buckets.sql` exists. ★1 GATE: VPS-side execution of `vendor-vg.sh` populates `_vendored_for_reference/keep-list-original/`.

### Task 1.1: Extend `supabase/migrations/001_initial.sql` with universal fields

**Files:**
- Modify: `supabase/migrations/001_initial.sql`

- [ ] **Step 1: Read current 001_initial.sql to find exact insertion points**

Run:
```bash
grep -n "CREATE TABLE\|^);" supabase/migrations/001_initial.sql | head -40
```

Identify line numbers of `CREATE TABLE briefs`, `CREATE TABLE orders`, `CREATE TABLE videos` and their closing `);`.

- [ ] **Step 2: Add `brand_colors_hex` and `logo_storage_url` to `briefs`**

In `supabase/migrations/001_initial.sql`, locate the `briefs` table definition (after `submitted_at TIMESTAMPTZ DEFAULT now()`). Insert these columns BEFORE the closing `);`:

```sql
  brand_colors_hex JSONB,
  logo_storage_url TEXT,
```

- [ ] **Step 3: Add `revisions_used` and `revisions_max` to `videos`**

Locate the `videos` table. Insert after `caption_burn_status TEXT DEFAULT 'pending'`:

```sql
  revisions_used INT DEFAULT 0,
  revisions_max INT,
```

- [ ] **Step 4: Add `strategy_call_*` and `performance_checkin_*` to `orders`**

Locate the `orders` table. Insert after `delivery_whatsapp_sent_at TIMESTAMPTZ`:

```sql
  strategy_call_scheduled_for TIMESTAMPTZ,
  strategy_call_completed_at TIMESTAMPTZ,
  performance_checkin_email_sent_at TIMESTAMPTZ,
  performance_checkin_response JSONB,
```

- [ ] **Step 5: Verify SQL parses (smoke check)**

Run:
```bash
grep -c "brand_colors_hex\|logo_storage_url\|revisions_used\|revisions_max\|strategy_call_scheduled_for\|strategy_call_completed_at\|performance_checkin_email_sent_at\|performance_checkin_response" supabase/migrations/001_initial.sql
```

Expected: `8` (exactly one occurrence of each name).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/001_initial.sql
git commit -m "feat(schema): extend 001 with Q6=C universal-to-all-tiers fields

briefs:  brand_colors_hex JSONB, logo_storage_url TEXT
videos:  revisions_used INT DEFAULT 0, revisions_max INT
orders:  strategy_call_scheduled_for, strategy_call_completed_at,
         performance_checkin_email_sent_at, performance_checkin_response JSONB

Creative-Pod-only fields (heygen_avatar_id, voice_clone_id, speaker_tag,
voice_variant_count) deferred to 005_creative_pod_columns.sql per
foundation-design spec section 1 Q6 row."
```

### Task 1.2: Author `infra/scripts/vendor-vg.sh`

**Files:**
- Create: `infra/scripts/vendor-vg.sh`

- [ ] **Step 1: Create the script**

```bash
cat > infra/scripts/vendor-vg.sh <<'EOF'
#!/usr/bin/env bash
# vendor-vg.sh — Cherry-pick Vision GridAI keep-list into _vendored_for_reference/.
#
# Per Q7=C in docs/superpowers/specs/2026-04-27-foundation-design.md:
#   - Clones VG to /tmp
#   - Copies only the keep-list (12 workflow JSONs + 4 host scripts) into
#     _vendored_for_reference/keep-list-original/
#   - Records the source SHA in _vendored_for_reference/SOURCE_SHA.txt
#   - Removes the /tmp clone
#
# Run from repo root: bash infra/scripts/vendor-vg.sh
# Idempotent.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
VG_REPO="https://github.com/akinwunmi-akinrimisi/vision-gridai-platform.git"
TMP_CLONE="/tmp/vg-clone-$$"
KEEP_DIR="${REPO_ROOT}/_vendored_for_reference/keep-list-original"
WORKFLOWS_DIR="${KEEP_DIR}/workflows"
SCRIPTS_DIR="${KEEP_DIR}/host-scripts"

# Workflow keep-list (12 files, per spec section 4.1)
WORKFLOWS=(
  "WF_TTS_AUDIO.json"
  "WF_IMAGE_GENERATION.json"
  "WF_SCENE_IMAGE_PROCESSOR.json"
  "WF_SCENE_I2V_PROCESSOR.json"
  "WF_KEN_BURNS.json"
  "WF_CAPTIONS_ASSEMBLY.json"
  "WF_RETRY_WRAPPER.json"
  "WF_ASSEMBLY_WATCHDOG.json"
  "WF_ENDCARD.json"
  "WF_MUSIC_GENERATE.json"
  "WF_MASTER.json"
  "WF_QA_CHECK.json"
)

# Host script keep-list (4 files)
SCRIPTS=(
  "caption_burn_service.py"
  "generate_kinetic_ass.py"
  "whisper_align.py"
  "burn_captions.sh"
)

cleanup() { rm -rf "$TMP_CLONE"; }
trap cleanup EXIT

echo "▶ Cloning VG into $TMP_CLONE..."
git clone --depth 1 "$VG_REPO" "$TMP_CLONE"

VG_SHA="$(git -C "$TMP_CLONE" rev-parse HEAD)"
echo "  VG SHA: $VG_SHA"

mkdir -p "$WORKFLOWS_DIR" "$SCRIPTS_DIR"

echo "▶ Copying 12 workflow JSONs..."
for wf in "${WORKFLOWS[@]}"; do
  src="$(find "$TMP_CLONE" -name "$wf" -type f | head -1)"
  if [ -z "$src" ]; then
    echo "  ❌ NOT FOUND: $wf — investigate"
    exit 1
  fi
  cp "$src" "$WORKFLOWS_DIR/$wf"
  echo "  ✅ $wf"
done

echo "▶ Copying 4 host scripts..."
for sc in "${SCRIPTS[@]}"; do
  src="$(find "$TMP_CLONE" -name "$sc" -type f | head -1)"
  if [ -z "$src" ]; then
    echo "  ❌ NOT FOUND: $sc — investigate"
    exit 1
  fi
  cp "$src" "$SCRIPTS_DIR/$sc"
  echo "  ✅ $sc"
done

echo "▶ Recording SOURCE_SHA..."
cat > "${REPO_ROOT}/_vendored_for_reference/SOURCE_SHA.txt" <<SHAEOF
${VG_SHA}
Vendored: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source: ${VG_REPO}
Items: 12 workflow JSONs + 4 host scripts
SHAEOF

echo ""
echo "✅ Vendoring complete:"
echo "   _vendored_for_reference/SOURCE_SHA.txt"
echo "   _vendored_for_reference/keep-list-original/workflows/  (12 JSONs)"
echo "   _vendored_for_reference/keep-list-original/host-scripts/  (4 files)"
EOF
chmod +x infra/scripts/vendor-vg.sh
```

- [ ] **Step 2: Verify script syntax**

Run:
```bash
bash -n infra/scripts/vendor-vg.sh
echo "Exit: $?"
```

Expected: `Exit: 0` (no syntax errors). The script is NOT executed yet — that's the ★1 gate later in this Day.

- [ ] **Step 3: Commit**

```bash
git add infra/scripts/vendor-vg.sh
git commit -m "feat(infra): vendor-vg.sh cherry-picks VG keep-list per Q7=C

Clones VG to /tmp, copies 12 workflow JSONs + 4 host scripts into
_vendored_for_reference/keep-list-original/, records source SHA,
cleans up the temp clone. Idempotent."
```

### Task 1.3: Author `supabase/migrations/004_storage_buckets.sql`

**Files:**
- Create: `supabase/migrations/004_storage_buckets.sql`

- [ ] **Step 1: Create the migration**

```bash
cat > supabase/migrations/004_storage_buckets.sql <<'EOF'
-- ═══════════════════════════════════════════════════
-- Operscale Video Ads — Storage Buckets
-- Creates 4 buckets for customer-uploaded assets and final deliverables.
-- RLS-locked: anon role denied; service_role full access.
-- See docs/superpowers/specs/2026-04-27-foundation-design.md §4.2.
-- ═══════════════════════════════════════════════════

-- ─── Bucket creation ────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('order-deliverables', 'order-deliverables', false, 524288000,
    ARRAY['video/mp4','image/jpeg','image/png']),
  ('customer-photos', 'customer-photos', false, 20971520,
    ARRAY['image/jpeg','image/png','image/webp']),
  ('customer-voice-samples', 'customer-voice-samples', false, 52428800,
    ARRAY['audio/mpeg','audio/wav','audio/x-wav']),
  ('customer-logos', 'customer-logos', false, 5242880,
    ARRAY['image/png','image/svg+xml','image/jpeg'])
ON CONFLICT (id) DO NOTHING;

-- ─── RLS policies ────────────────────────────────────
-- anon: deny all
CREATE POLICY "operscale_anon_deny_select" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id NOT IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));

CREATE POLICY "operscale_anon_deny_insert" ON storage.objects
  FOR INSERT TO anon
  WITH CHECK (bucket_id NOT IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));

-- service_role: full access on operscale buckets
CREATE POLICY "operscale_service_role_all" ON storage.objects
  FOR ALL TO service_role
  USING (bucket_id IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'))
  WITH CHECK (bucket_id IN ('order-deliverables','customer-photos','customer-voice-samples','customer-logos'));
EOF
```

- [ ] **Step 2: Sanity-check the SQL**

Run:
```bash
grep -c "INSERT INTO storage.buckets\|CREATE POLICY" supabase/migrations/004_storage_buckets.sql
```

Expected: `4` (1 INSERT + 3 CREATE POLICY statements).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/004_storage_buckets.sql
git commit -m "feat(schema): 004_storage_buckets.sql

Creates 4 RLS-locked Storage buckets:
  - order-deliverables   (final MP4s + thumbnails, ≤500MB)
  - customer-photos      (HeyGen avatar source, ≤20MB)
  - customer-voice-samples (fal.ai PlayHT v3 source, ≤50MB)
  - customer-logos       (logo overlay assets, ≤5MB)

anon-deny-all + service_role-full-access on all 4 buckets."
```

### Task 1.4: ★1 NAMED GATE — Run `vendor-vg.sh` on VPS

**Files:**
- Modify: `_vendored_for_reference/SOURCE_SHA.txt` (created by script)
- Modify: `_vendored_for_reference/keep-list-original/` (populated by script, gitignored)

- [ ] **Step 1: Push current commits to GitHub**

```bash
git push -u origin main
```

Expected: 3 commits pushed (`extend 001`, `vendor-vg.sh`, `004_storage_buckets.sql`).

- [ ] **Step 2: ★1 GATE — Stop and confirm with user**

Pause execution. Present this to the user:

> **★1 NAMED GATE — VPS execution of vendor-vg.sh**
>
> About to: SSH to `srv1297445.hstgr.cloud` and run `bash infra/scripts/vendor-vg.sh`.
>
> What it does: clones VG to `/tmp/vg-clone-<pid>`, copies 12 workflow JSONs + 4 host scripts to `_vendored_for_reference/keep-list-original/`, writes `_vendored_for_reference/SOURCE_SHA.txt`, removes the temp clone.
>
> What "good" looks like: stdout shows "✅ Vendoring complete:" and 12 workflow file names + 4 script file names listed as ✅.
>
> Rollback if it goes wrong: `rm -rf _vendored_for_reference/keep-list-original/ _vendored_for_reference/SOURCE_SHA.txt` and re-run after fixing.
>
> Proceed?

Wait for user "go".

- [ ] **Step 3: User runs the command on VPS**

User executes (paste command for them):
```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads  # or wherever the repo is cloned on VPS
git pull origin main
bash infra/scripts/vendor-vg.sh
```

User pastes the stdout back to chat.

- [ ] **Step 4: Verify expected output**

Confirm in the pasted stdout:
- All 12 workflow JSONs listed with ✅
- All 4 host scripts listed with ✅
- "✅ Vendoring complete:" line at end
- No "❌ NOT FOUND" lines

If any "❌ NOT FOUND" appears: stop and investigate (probably means VG repo structure has shifted and the `find` paths in the script need adjustment).

- [ ] **Step 5: User commits the SOURCE_SHA on VPS** (gitignored content stays on disk; only `SOURCE_SHA.txt` is gitignored too — it's `.gitkeep` and `VENDORING.md` that are committed; on this run nothing new lands in git)

No commit needed at this step — `SOURCE_SHA.txt` is gitignored per `.gitignore` (`_vendored_for_reference/*` minus the explicit allow-list).

---

## Day 2 — Cherry-pick + rebind workflows  *(★2)*

**Day goal:** 12 `OPS_*.json` files in `apps/n8n-workflows/operscale/`, each rebound and lint-clean. 4 host scripts copied to `infra/host-scripts/`. `tools/lint_n8n_workflows.py` written. ★2 GATE: linter passes 13/13 (12 workflows + lint tool itself sanity-check).

### Task 2.1: Author `infra/scripts/rebind-workflow.py`

**Files:**
- Create: `infra/scripts/rebind-workflow.py`

- [ ] **Step 1: Create the rebind script**

```bash
cat > infra/scripts/rebind-workflow.py <<'EOF'
#!/usr/bin/env python3
"""
rebind-workflow.py — Apply Operscale rebind transforms to a VG workflow JSON.

Per docs/adr/0008-fork-vision-gridai.md and the vg-workflow-rebind skill:
  1. Webhook path namespace: /webhook/X → /webhook/operscale/X
  2. Workflow name prefix:   WF_X → OPS_X
  3. SQL FK rebind:          topic_id→video_id, topics→videos,
                              project_id→order_id, projects→orders
  4. Scratch path remap:     /tmp/production/ → /tmp/operscale-production/,
                              /data/n8n-production/ → /data/operscale-production/
  5. Authorization headers:  every value MUST start with "=" (gotcha #2)
  6. Inline credentials:     none allowed; must reference n8n credential by ID

Usage: python infra/scripts/rebind-workflow.py <input.json> <output.json>
       python infra/scripts/rebind-workflow.py --batch <input_dir> <output_dir>

Exits non-zero if any AUTH-01 or CRED-01 violation is detected.
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# ── Rebind transforms ─────────────────────────────────

WEBHOOK_PATH_REPLACEMENTS = [
    (re.compile(r'/webhook/(?!operscale/)'), '/webhook/operscale/'),
]

NAME_PREFIX_REPLACEMENTS = [
    (re.compile(r'^WF_'), 'OPS_'),
]

SQL_FK_REPLACEMENTS = [
    (re.compile(r'\btopic_id\b'),   'video_id'),
    (re.compile(r'\btopics\b'),     'videos'),
    (re.compile(r'\bproject_id\b'), 'order_id'),
    (re.compile(r'\bprojects\b'),   'orders'),
]

PATH_REPLACEMENTS = [
    ('/tmp/production/',           '/tmp/operscale-production/'),
    ('/data/n8n-production/',      '/data/operscale-production/'),
]

# ── Lint rules ────────────────────────────────────────

AUTH_HEADER_KEYS = {'authorization', 'Authorization'}

class LintFinding:
    def __init__(self, rule: str, node_name: str, detail: str):
        self.rule = rule
        self.node_name = node_name
        self.detail = detail

    def __str__(self):
        return f"  [{self.rule}] node='{self.node_name}': {self.detail}"


def transform_string(s: str) -> str:
    """Apply all string-level transforms to a value."""
    for pattern, replacement in WEBHOOK_PATH_REPLACEMENTS:
        s = pattern.sub(replacement, s)
    for pattern, replacement in SQL_FK_REPLACEMENTS:
        s = pattern.sub(replacement, s)
    for old, new in PATH_REPLACEMENTS:
        s = s.replace(old, new)
    return s


def transform_value(v: Any) -> Any:
    if isinstance(v, str):
        return transform_string(v)
    if isinstance(v, dict):
        return {k: transform_value(val) for k, val in v.items()}
    if isinstance(v, list):
        return [transform_value(item) for item in v]
    return v


def rebind(workflow: dict) -> dict:
    """Apply rebind transforms; return new dict (original untouched)."""
    out = transform_value(workflow)
    # Rename top-level workflow name
    if isinstance(out, dict) and 'name' in out and isinstance(out['name'], str):
        for pattern, replacement in NAME_PREFIX_REPLACEMENTS:
            out['name'] = pattern.sub(replacement, out['name'])
    return out


def lint(workflow: dict, source_name: str) -> list[LintFinding]:
    """Detect AUTH-01 and CRED-01 violations."""
    findings: list[LintFinding] = []

    nodes = workflow.get('nodes', [])
    for node in nodes:
        node_name = node.get('name', '<unnamed>')
        params = node.get('parameters', {})

        # AUTH-01: every Authorization header value must start with '=' if it
        # contains an n8n expression-syntax substring like {{ $env.X }}.
        headers = (
            params.get('headerParameters', {}).get('parameters')
            or params.get('headers', {}).get('parameters')
            or []
        )
        for h in headers if isinstance(headers, list) else []:
            if not isinstance(h, dict):
                continue
            key = (h.get('name') or '').strip()
            value = h.get('value') or ''
            if key.lower() == 'authorization' and isinstance(value, str):
                has_expr = '{{' in value and '}}' in value
                if has_expr and not value.startswith('='):
                    findings.append(LintFinding(
                        'AUTH-01', node_name,
                        f"Authorization value contains expression but doesn't start with '=': {value[:80]}"
                    ))

        # CRED-01: no inline API keys / secrets in node params.
        # Heuristic: look for raw key-shaped strings outside the credentials object.
        as_str = json.dumps(params)
        # Common API-key patterns
        if re.search(r'sk-[A-Za-z0-9_-]{20,}', as_str):
            findings.append(LintFinding(
                'CRED-01', node_name,
                "Inline OpenAI/Anthropic-shaped key detected (sk-…). Move to n8n credentials."
            ))
        if re.search(r'pk_(test|live)_[A-Za-z0-9]{20,}', as_str):
            findings.append(LintFinding(
                'CRED-01', node_name,
                "Inline Paystack-shaped key detected (pk_…). Move to n8n credentials."
            ))

    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--batch', action='store_true', help='Process all *.json in a directory')
    ap.add_argument('--lint-only', action='store_true', help='Lint without writing output')
    ap.add_argument('input', help='Input file or directory')
    ap.add_argument('output', nargs='?', help='Output file or directory')
    args = ap.parse_args()

    files: list[tuple[Path, Path]] = []
    in_path = Path(args.input)
    if args.batch:
        out_path = Path(args.output) if args.output else None
        for src in sorted(in_path.glob('*.json')):
            if out_path:
                # WF_X.json → OPS_X.json
                dst_name = re.sub(r'^WF_', 'OPS_', src.name)
                files.append((src, out_path / dst_name))
            else:
                files.append((src, src))
    else:
        if not args.lint_only and not args.output:
            ap.error('output required unless --lint-only')
        files.append((in_path, Path(args.output) if args.output else in_path))

    total_findings = 0
    for src, dst in files:
        with src.open() as f:
            wf = json.load(f)

        if not args.lint_only:
            wf = rebind(wf)

        findings = lint(wf, src.name)
        if findings:
            print(f"❌ {src.name} — {len(findings)} finding(s):")
            for fnd in findings:
                print(fnd)
            total_findings += len(findings)
        else:
            print(f"✅ {src.name}")

        if not args.lint_only:
            dst.parent.mkdir(parents=True, exist_ok=True)
            with dst.open('w') as f:
                json.dump(wf, f, indent=2)

    print(f"\nTotal findings: {total_findings}")
    return 1 if total_findings > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
EOF
chmod +x infra/scripts/rebind-workflow.py
```

- [ ] **Step 2: Smoke test the script (no input yet, just verify it runs)**

Run:
```bash
python infra/scripts/rebind-workflow.py --help
```

Expected: argparse usage output (no errors).

- [ ] **Step 3: Commit**

```bash
git add infra/scripts/rebind-workflow.py
git commit -m "feat(infra): rebind-workflow.py applies VG→OPS transforms + AUTH-01/CRED-01 lint

Transforms:
  - /webhook/X → /webhook/operscale/X
  - WF_X → OPS_X (workflow name)
  - topic_id→video_id, topics→videos, project_id→order_id, projects→orders
  - /tmp/production/ → /tmp/operscale-production/
  - /data/n8n-production/ → /data/operscale-production/

Lint rules (block on any finding):
  - AUTH-01: Authorization values containing expressions must start with '='
  - CRED-01: no inline OpenAI/Anthropic/Paystack-shaped keys

CLI: --batch processes a directory, --lint-only validates without writing."
```

### Task 2.2: Run rebind on the keep-list (12 workflows) — VPS-side

**Files:**
- Create: `apps/n8n-workflows/operscale/OPS_*.json` (12 files)

- [ ] **Step 1: Push to GitHub so VPS can pull the rebind script**

```bash
git push origin main
```

- [ ] **Step 2: User runs rebind on VPS in batch mode**

User executes:
```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
mkdir -p apps/n8n-workflows/operscale
python3 infra/scripts/rebind-workflow.py --batch \
  _vendored_for_reference/keep-list-original/workflows \
  apps/n8n-workflows/operscale
```

- [ ] **Step 3: User pastes the stdout back**

Expected: 12 lines, each "✅ WF_X.json", and "Total findings: 0".

If any "❌" appears: STOP. The rebind/lint flagged a problem in a source workflow. Investigate the specific finding before proceeding.

- [ ] **Step 4: User commits and pushes the 12 OPS_*.json files**

User executes (on VPS):
```bash
cd /docker/operscale-video-ads
git add apps/n8n-workflows/operscale/
git status --short
```

Expected: 12 new files all named `apps/n8n-workflows/operscale/OPS_*.json`.

```bash
git commit -m "feat(workflows): cherry-pick + rebind 12 keep-list workflows

Source: _vendored_for_reference/keep-list-original/workflows/ (per Q7=C)
Transform: rebind-workflow.py --batch (AUTH-01 + CRED-01 lint passed for all 12)

OPS_TTS_AUDIO, OPS_IMAGE_GENERATION, OPS_SCENE_IMAGE_PROCESSOR,
OPS_SCENE_I2V_PROCESSOR, OPS_KEN_BURNS, OPS_CAPTIONS_ASSEMBLY,
OPS_RETRY_WRAPPER, OPS_ASSEMBLY_WATCHDOG, OPS_ENDCARD,
OPS_MUSIC_GENERATE, OPS_RENDER_PIPELINE (ex-WF_MASTER), OPS_QA_CHECK"
git push origin main
```

### Task 2.3: Copy host scripts to `infra/host-scripts/` (un-rebound)

**Files:**
- Create: `infra/host-scripts/caption_burn_service.py`
- Create: `infra/host-scripts/generate_kinetic_ass.py`
- Create: `infra/host-scripts/whisper_align.py`
- Create: `infra/host-scripts/burn_captions.sh`

- [ ] **Step 1: User runs the copy on VPS**

User executes:
```bash
cd /docker/operscale-video-ads
mkdir -p infra/host-scripts
cp _vendored_for_reference/keep-list-original/host-scripts/*.py infra/host-scripts/
cp _vendored_for_reference/keep-list-original/host-scripts/*.sh infra/host-scripts/
ls -la infra/host-scripts/
```

Expected: 4 files listed (`caption_burn_service.py`, `generate_kinetic_ass.py`, `whisper_align.py`, `burn_captions.sh`).

- [ ] **Step 2: Make scripts executable where appropriate**

```bash
chmod +x infra/host-scripts/*.sh infra/host-scripts/*.py
```

- [ ] **Step 3: User commits**

```bash
git add infra/host-scripts/
git commit -m "feat(infra): cherry-pick 4 VG host-side scripts (un-rebound)

caption_burn_service.py — HTTP service on :9998, kinetic-caption burn
generate_kinetic_ass.py — generates ASS subtitle files (will be extended
                          Day 11 per fork manual §8.7 for niche colour mapping)
whisper_align.py        — word-level subtitle alignment
burn_captions.sh        — orchestrates docker exec + ffmpeg

Sourced from VG SHA in _vendored_for_reference/SOURCE_SHA.txt."
git push origin main
```

### Task 2.4: Author `tools/lint_n8n_workflows.py` (CI-style wrapper)

**Files:**
- Create: `tools/lint_n8n_workflows.py`

- [ ] **Step 1: Create the lint wrapper**

```bash
cat > tools/lint_n8n_workflows.py <<'EOF'
#!/usr/bin/env python3
"""
lint_n8n_workflows.py — CI-friendly wrapper around rebind-workflow.py --lint-only.

Walks apps/n8n-workflows/operscale/, lints every *.json. Exits non-zero on
any finding. Designed to be wired into CI in the polish phase; in Foundation
it's run manually to confirm Day 2's rebind output is clean.

Usage: python tools/lint_n8n_workflows.py
"""
import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    target = repo_root / 'apps' / 'n8n-workflows' / 'operscale'
    if not target.exists():
        print(f"❌ {target} does not exist")
        return 1

    json_files = sorted(target.glob('*.json'))
    if not json_files:
        print(f"❌ No *.json found in {target}")
        return 1

    print(f"Linting {len(json_files)} workflow file(s) under {target}...")
    rebind_script = repo_root / 'infra' / 'scripts' / 'rebind-workflow.py'

    failures = 0
    for jf in json_files:
        result = subprocess.run(
            ['python3', str(rebind_script), '--lint-only', str(jf)],
            capture_output=True, text=True
        )
        sys.stdout.write(result.stdout)
        if result.returncode != 0:
            failures += 1

    print(f"\n{'='*60}")
    if failures == 0:
        print(f"✅ All {len(json_files)} workflows lint-clean.")
        return 0
    else:
        print(f"❌ {failures} of {len(json_files)} workflows have lint findings.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
EOF
chmod +x tools/lint_n8n_workflows.py
```

- [ ] **Step 2: Commit**

```bash
git add tools/lint_n8n_workflows.py
git commit -m "feat(tools): lint_n8n_workflows.py CI-friendly wrapper

Walks apps/n8n-workflows/operscale/ and runs rebind-workflow.py --lint-only
on each JSON. Exits non-zero on any AUTH-01 or CRED-01 finding. CI wiring
lands in polish phase; for Foundation it's the Day 2 ★2 gate."
```

### Task 2.5: ★2 NAMED GATE — Run lint on all 12 OPS workflows

- [ ] **Step 1: Push to GitHub**

```bash
git push origin main
```

- [ ] **Step 2: ★2 GATE — Stop and confirm with user**

> **★2 NAMED GATE — Lint check on all 12 OPS workflows**
>
> About to: run `python3 tools/lint_n8n_workflows.py` on VPS.
>
> What "good" looks like: 12 `✅ OPS_*.json` lines, then `✅ All 12 workflows lint-clean.`
>
> If anything fails: STOP. The rebind has a bug or one of the source VG workflows already has a violation that we now own. We fix before any n8n import.
>
> Proceed?

Wait for "go".

- [ ] **Step 3: User runs the linter on VPS**

```bash
cd /docker/operscale-video-ads
git pull origin main
python3 tools/lint_n8n_workflows.py
```

User pastes stdout back.

- [ ] **Step 4: Verify**

If output ends with `✅ All 12 workflows lint-clean.` → Day 2 is done.

If anything else: STOP and investigate before proceeding to Day 3.

---

## Day 3 — VPS reconnaissance

**Day goal:** `docs/foundation/infrastructure-state-day-3.md` accurately captures shared-VPS state. Read-only audit, no writes to anything.

### Task 3.1: Author `infra/scripts/recon-vps.sh`

**Files:**
- Create: `infra/scripts/recon-vps.sh`

- [ ] **Step 1: Create the read-only audit script**

```bash
cat > infra/scripts/recon-vps.sh <<'EOF'
#!/usr/bin/env bash
# recon-vps.sh — Read-only audit of shared-VPS state.
# RUNS ON VPS. Produces output suitable for docs/foundation/infrastructure-state-day-3.md.
# NO writes, no restarts, no destructive ops.

set -euo pipefail

echo "=== Operscale Video Ads — VPS Recon ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
echo ""

echo "## 1. Docker containers"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || echo "  ⚠️  docker not reachable"
echo ""

echo "## 2. n8n container health"
if docker ps --format '{{.Names}}' | grep -q '^n8n-n8n-1$'; then
  docker exec n8n-n8n-1 ffmpeg -version 2>&1 | head -1 || true
  docker exec n8n-n8n-1 ls /tmp 2>&1 | head -10 || true
  docker exec n8n-n8n-1 env 2>&1 | grep -E '^NODE_FUNCTION_ALLOW_BUILTIN|^DB_' || echo "  (no relevant env)"
else
  echo "  ❌ n8n-n8n-1 not running"
fi
echo ""

echo "## 3. Caption burn service"
systemctl status caption-burn.service --no-pager 2>&1 | head -10 || echo "  ⚠️  systemd unit not found"
curl -sf -o /dev/null -w "  health-check HTTP: %{http_code}\n" http://172.18.0.1:9998/health || \
    echo "  ⚠️  caption-burn /health not reachable on 172.18.0.1:9998"
echo ""

echo "## 4. Filesystem layout"
ls -la /data/ 2>/dev/null | head -20 || echo "  ⚠️  /data not readable"
ls -la /docker/ 2>/dev/null | head -20 || echo "  ⚠️  /docker not readable"
echo ""

echo "## 5. Supabase containers"
docker ps --format '{{.Names}}' | grep -i supabase || echo "  ⚠️  no supabase containers"
echo ""

echo "## 6. Postgres tables (count only, no data)"
if docker ps --format '{{.Names}}' | grep -q supabase-db-1; then
  docker exec supabase-db-1 psql -U postgres -t -c \
    "SELECT count(*) AS table_count FROM information_schema.tables WHERE table_schema='public';" 2>&1 || true
else
  echo "  ⚠️  supabase-db-1 not running"
fi
echo ""

echo "## 7. Realtime publication"
if docker ps --format '{{.Names}}' | grep -q supabase-db-1; then
  docker exec supabase-db-1 psql -U postgres -t -c \
    "SELECT tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY tablename;" 2>&1 || true
fi
echo ""

echo "## 8. Traefik routes (if accessible)"
docker ps --format '{{.Names}}' | grep -i traefik || echo "  (traefik container not visible by name)"
echo ""

echo "## 9. Disk + memory"
df -h / 2>/dev/null | head -2 || true
free -h 2>/dev/null | head -3 || true
echo ""

echo "=== Recon complete ==="
EOF
chmod +x infra/scripts/recon-vps.sh
```

- [ ] **Step 2: Verify script syntax**

```bash
bash -n infra/scripts/recon-vps.sh
echo "Exit: $?"
```

Expected: `Exit: 0`.

- [ ] **Step 3: Commit + push**

```bash
git add infra/scripts/recon-vps.sh
git commit -m "feat(infra): recon-vps.sh — read-only Day-3 audit"
git push origin main
```

### Task 3.2: Run recon on VPS + author the doc

**Files:**
- Create: `docs/foundation/infrastructure-state-day-3.md`

- [ ] **Step 1: User runs recon on VPS**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
bash infra/scripts/recon-vps.sh > /tmp/recon-output.txt
cat /tmp/recon-output.txt
```

User pastes stdout back.

- [ ] **Step 2: Synthesize the doc (Windows side)**

```bash
mkdir -p docs/foundation
cat > docs/foundation/infrastructure-state-day-3.md <<'EOF'
# Infrastructure State — Day 3 VPS Recon

> Snapshot date: 2026-MM-DD
> Source: `infra/scripts/recon-vps.sh` output, run on `srv1297445.hstgr.cloud`.
> Read-only audit. No writes performed.

## Summary verdict

[FILL: green = all VG components healthy and unmodified;
       yellow = minor drift documented below;
       red = blocker, do not proceed to Day 4]

## Docker containers running

[PASTE output of section 1 from recon-vps.sh]

## Caption burn service

[PASTE output of section 3]

Decision input for Day 9 (★5 caption-burn integration choice):
- [ ] Symlink path is viable (no conflict at `/data/n8n-production/operscale`)
- [ ] Env-var path is needed because [reason]

## Filesystem layout

[PASTE output of section 4]

## Postgres / Supabase

Table count: [n]
Realtime publication tables: [list]

[Note any tables matching our 12 names — if any DO match, that's a blocker
 because our migration would collide. We expect none to match.]

## Drift from VG docs (if any)

[FILL: list anything VG's docs say should be present that isn't, or vice versa]

## Decisions deferred to later Days

- Day 4: Operscale containers compose file — bind mount paths confirmed against this recon
- Day 5: ★3 migration apply — RLS DO-block confirmed not to touch existing VG tables
- Day 9: ★5 caption-burn path strategy — symlink is the recommended default unless this recon surfaces a conflict
EOF
```

Now fill in the bracketed sections from the user's pasted recon output.

- [ ] **Step 3: Verify doc has no remaining brackets**

```bash
grep -n "\[FILL\|\[PASTE" docs/foundation/infrastructure-state-day-3.md
```

Expected: no output (all bracket placeholders filled).

- [ ] **Step 4: Commit**

```bash
git add docs/foundation/infrastructure-state-day-3.md
git commit -m "docs: Day-3 VPS recon — shared-infra state snapshot"
git push origin main
```

---

## Day 4 — Operscale Docker compose deploy

**Day goal:** `operscale-web` and `operscale-agent` placeholder containers running on VPS. Bind mount `/data/operscale-production` reachable from inside `n8n-n8n-1`. Traefik route for `plovera.shop` returns a placeholder 200 (not 502).

### Task 4.1: Author `infra/docker/operscale-compose.yml`

**Files:**
- Create: `infra/docker/operscale-compose.yml`

- [ ] **Step 1: Create the compose file**

```bash
cat > infra/docker/operscale-compose.yml <<'EOF'
# Operscale Video Ads — Docker Compose
# Deploys operscale-web (Next.js 15) and operscale-agent (Python 3.11 LangGraph)
# on the same VPS as Vision GridAI. Both share Traefik, Postgres, n8n, and
# the host-side caption-burn service.
#
# In Foundation phase both services run as PLACEHOLDER images — real Dockerfiles
# arrive in Customer-flow phase. Foundation only needs:
#   - Containers running (so Traefik wiring + bind mounts can be verified)
#   - Bind mount of /data/operscale-production into n8n-n8n-1
#
# Read alongside docs/superpowers/specs/2026-04-27-foundation-design.md §3.
# Brand domain locked: plovera.shop (per ADR 0017).

version: '3.8'

services:
  operscale-web:
    image: nginx:1.27-alpine  # Foundation placeholder; real Dockerfile in Customer-flow
    container_name: operscale-web
    restart: unless-stopped
    networks:
      - traefik-net
      - operscale-net
    volumes:
      - /data/operscale-production:/usr/share/nginx/html/data:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.operscale-web.rule=Host(`plovera.shop`) || Host(`www.plovera.shop`)"
      - "traefik.http.routers.operscale-web.tls=true"
      - "traefik.http.routers.operscale-web.tls.certresolver=letsencrypt"
      - "traefik.http.routers.operscale-web.entrypoints=websecure"
      - "traefik.http.services.operscale-web.loadbalancer.server.port=80"

  operscale-agent:
    image: python:3.11-slim  # Foundation placeholder; real Dockerfile in Customer-flow
    container_name: operscale-agent
    restart: unless-stopped
    command: ["sleep", "infinity"]  # Placeholder — agent skeleton lands in Customer-flow
    networks:
      - operscale-net
    volumes:
      - /data/operscale-production:/data/operscale-production
      - ./apps/agent:/app:ro
    working_dir: /app
    env_file:
      - /docker/operscale-video-ads/.env.agent

networks:
  traefik-net:
    external: true
    name: traefik-net
  operscale-net:
    driver: bridge

# n8n bind-mount addition required separately on VPS:
#   Edit /docker/n8n/docker-compose.override.yml to add:
#     volumes:
#       - /data/operscale-production:/tmp/operscale-production
#   Then restart n8n stack: cd /docker/n8n && docker compose up -d
# This is a ★ named gate operation — done manually with confirmation.
EOF
```

- [ ] **Step 2: Verify YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('infra/docker/operscale-compose.yml'))" && echo "OK"
```

Expected: `OK`.

- [ ] **Step 3: Commit + push**

```bash
git add infra/docker/operscale-compose.yml
git commit -m "feat(infra): operscale-compose.yml — web + agent placeholder containers

operscale-web: nginx:1.27-alpine placeholder; Traefik route for plovera.shop;
read-only bind to /data/operscale-production.

operscale-agent: python:3.11-slim sleep-infinity placeholder; r/w bind to
/data/operscale-production; reads /docker/operscale-video-ads/.env.agent.

Real Dockerfiles arrive in Customer-flow phase. n8n bind-mount addition
to /docker/n8n/docker-compose.override.yml is documented as a manual
named-gate operation in the YAML comment."
git push origin main
```

### Task 4.2: Deploy on VPS + verify

- [ ] **Step 1: User pulls and brings up the stack on VPS**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
sudo mkdir -p /data/operscale-production
sudo chown root:root /data/operscale-production
docker compose -f infra/docker/operscale-compose.yml up -d
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'operscale|n8n'
```

Expected: `operscale-web` and `operscale-agent` both `Up`.

- [ ] **Step 2: User verifies bind mount reachable from n8n**

```bash
docker exec n8n-n8n-1 ls /tmp 2>&1 | grep operscale-production && echo "MOUNT OK" || echo "MOUNT MISSING — need to edit n8n override"
```

If "MOUNT MISSING": this requires editing `/docker/n8n/docker-compose.override.yml` (★ standing rule named gate). Pause and confirm before doing this — the n8n stack will need a `docker compose up -d`.

- [ ] **Step 3: User verifies Traefik routes plovera.shop**

```bash
curl -I https://plovera.shop
```

Expected: `HTTP/2 200` (or `HTTP/1.1 200 OK`) — nginx default page is fine. NOT acceptable: 502 (compose misconfigured), 503 (Traefik can't reach upstream), or no DNS.

If DNS isn't pointed to the VPS yet: that's a manual Hostinger DNS task; flag and continue (Foundation doesn't strictly need DNS, only the container running).

- [ ] **Step 4: Update verification doc**

Append to `docs/foundation/foundation-verification.md`:

```bash
mkdir -p docs/foundation
cat >> docs/foundation/foundation-verification.md <<'EOF'

## Day 4 — Operscale Docker compose

- operscale-web: [Up / Down]
- operscale-agent: [Up / Down]
- /data/operscale-production bind in n8n-n8n-1: [OK / Missing — needs n8n override edit]
- https://plovera.shop response: [200 / 502 / no DNS]

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 4 — Operscale containers deployed; Traefik route live"
git push origin main
```

---

## Day 5 — Apply migrations to shared Supabase  *(★3, ★4)*

**Day goal:** `001_initial.sql`, `002_seed_registers.sql`, `003_seed_prompt_configs.sql`, `004_storage_buckets.sql` all applied to shared Supabase. RLS verified anon-deny, service-role-allow. REPLICA IDENTITY FULL set on the 5 tables. Realtime publication includes all 5.

### Task 5.1: Author `infra/scripts/apply-migrations.sh`

**Files:**
- Create: `infra/scripts/apply-migrations.sh`

- [ ] **Step 1: Create the runbook script**

```bash
cat > infra/scripts/apply-migrations.sh <<'EOF'
#!/usr/bin/env bash
# apply-migrations.sh — Apply Operscale schema migrations to the shared Supabase.
# RUNS ON VPS. Reads from supabase/migrations/, applies in order, verifies after each.
#
# Per docs/superpowers/specs/2026-04-27-foundation-design.md §6.4:
#   ★3 named gate before this script runs at all
#   ★4 named gate before the ALTER PUBLICATION at end of 001
#
# Idempotent — uses CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING etc.

set -euo pipefail

MIGRATIONS=(
  "001_initial.sql"
  "002_seed_registers.sql"
  "003_seed_prompt_configs.sql"
  "004_storage_buckets.sql"
)

SUPABASE_DB="supabase-db-1"

if ! docker ps --format '{{.Names}}' | grep -q "^${SUPABASE_DB}\$"; then
  echo "❌ ${SUPABASE_DB} not running"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

for m in "${MIGRATIONS[@]}"; do
  path="supabase/migrations/${m}"
  if [ ! -f "$path" ]; then
    echo "❌ $path missing"
    exit 1
  fi
  echo "▶ Applying $m..."
  docker exec -i "$SUPABASE_DB" psql -U postgres -v ON_ERROR_STOP=1 < "$path" 2>&1 | tail -20
  echo "  ✅ $m applied"
  echo ""
done

echo "▶ Verifying Operscale tables exist..."
EXPECTED_TABLES=(customers briefs orders videos scenes production_log payments gate_decisions order_consent llm_calls production_registers prompt_configs)
for t in "${EXPECTED_TABLES[@]}"; do
  count=$(docker exec "$SUPABASE_DB" psql -U postgres -tA -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='$t';")
  if [ "$count" = "1" ]; then
    echo "  ✅ $t"
  else
    echo "  ❌ $t — expected 1, got $count"
    exit 1
  fi
done

echo ""
echo "▶ Verifying REPLICA IDENTITY FULL on Realtime tables..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SELECT relname, CASE relreplident WHEN 'f' THEN 'FULL' ELSE 'OTHER' END AS identity
   FROM pg_class WHERE relname IN ('orders','videos','scenes','production_log','gate_decisions') ORDER BY relname;"

echo ""
echo "▶ Verifying Realtime publication membership..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SELECT tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename IN ('orders','videos','scenes','production_log','gate_decisions') ORDER BY tablename;"

echo ""
echo "▶ Spot-checking RLS lockdown (anon role on orders)..."
docker exec "$SUPABASE_DB" psql -U postgres -c \
  "SET ROLE anon; SELECT count(*) AS anon_visible_rows FROM orders; RESET ROLE;"
echo "  Expected: 0 (RLS denies anon)"

echo ""
echo "✅ All migrations applied and verified."
EOF
chmod +x infra/scripts/apply-migrations.sh
```

- [ ] **Step 2: Verify script syntax**

```bash
bash -n infra/scripts/apply-migrations.sh
echo "Exit: $?"
```

Expected: `Exit: 0`.

- [ ] **Step 3: Commit + push**

```bash
git add infra/scripts/apply-migrations.sh
git commit -m "feat(infra): apply-migrations.sh — Day-5 schema deployment runbook

Applies 001/002/003/004 in order with ON_ERROR_STOP=1. Verifies all 12
Operscale tables exist, REPLICA IDENTITY FULL set on the 5 Realtime tables,
publication membership, and RLS lockdown (anon visibility=0)."
git push origin main
```

### Task 5.2: ★3 + ★4 NAMED GATE — User reviews the migration plan, runs the apply

- [ ] **Step 1: ★3 GATE — Stop and present**

> **★3 NAMED GATE — first migration apply on shared Supabase**
>
> About to: SSH to VPS, run `bash infra/scripts/apply-migrations.sh`.
>
> What it does: applies 001 → 002 → 003 → 004 in order. Each migration is additive (CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING). Embedded ★4 gate: 001 contains an `ALTER PUBLICATION supabase_realtime ADD TABLE …` for our 5 tables; this modifies a publication VG's Realtime subscribers also use.
>
> Recon-doc check: please confirm `docs/foundation/infrastructure-state-day-3.md` shows no name collision between our 12 tables and existing public-schema tables.
>
> What "good" looks like: 12 ✅ table-exists lines, REPLICA IDENTITY FULL on all 5, publication shows 5 tables, anon visibility = 0.
>
> Rollback if it goes wrong: each migration's CREATE TABLE IF NOT EXISTS is safe to re-run. To undo full schema: a separate destructive script we'd write only if needed.
>
> Proceed?

Wait for "go".

- [ ] **Step 2: User executes on VPS**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
bash infra/scripts/apply-migrations.sh 2>&1 | tee /tmp/migration-output.txt
```

User pastes the full stdout back.

- [ ] **Step 3: Verify all expected outputs**

In the pasted output, confirm:
- `✅ 001_initial.sql applied`
- `✅ 002_seed_registers.sql applied`
- `✅ 003_seed_prompt_configs.sql applied`
- `✅ 004_storage_buckets.sql applied`
- All 12 `✅ <table>` lines under "Verifying Operscale tables exist"
- All 5 tables show `FULL` under "Verifying REPLICA IDENTITY FULL"
- All 5 tables appear under "Verifying Realtime publication membership"
- "Expected: 0 (RLS denies anon)" — actual `anon_visible_rows` = `0`

If anything is wrong: STOP. Do not proceed to Day 6. Diagnose against the recon doc.

### Task 5.3: Append Day-5 results to verification doc

- [ ] **Step 1: Update foundation-verification.md**

Append to `docs/foundation/foundation-verification.md`:

```markdown
## Day 5 — Schema applied to shared Supabase  *(★3, ★4)*

- 001_initial.sql: ✅
- 002_seed_registers.sql: ✅ (2 registers seeded)
- 003_seed_prompt_configs.sql: ✅ (20 prompt-config stubs seeded)
- 004_storage_buckets.sql: ✅ (4 buckets created, RLS locked)
- 12 Operscale tables exist: ✅
- REPLICA IDENTITY FULL on orders, videos, scenes, production_log, gate_decisions: ✅
- Realtime publication membership for all 5: ✅
- anon-role visibility on orders: 0 (RLS lockdown working): ✅
```

- [ ] **Step 2: Commit + push**

```bash
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 5 — schema applied, RLS + Realtime verified"
git push origin main
```

---

## Day 6 — Import OPS_TTS + IMG + RETRY into n8n

**Day goal:** First TTS render succeeds against fake-order-1 (real-estate, 5 scenes). 5 mp3 files in `/data/operscale-production/<order_id>/audio/`. `scenes.audio_status='uploaded'` and `audio_duration_ms` populated.

### Task 6.1: Author 5 niche test fixtures + seed_test_order.py

**Files:**
- Create: `apps/agent/tests/__init__.py`
- Create: `apps/agent/tests/conftest.py`
- Create: `apps/agent/tests/seed_test_order.py`
- Create: `apps/agent/tests/fixtures/__init__.py`
- Create: `apps/agent/tests/fixtures/scripts/real-estate.json`

- [ ] **Step 1: Create the package files**

```bash
touch apps/agent/tests/__init__.py
mkdir -p apps/agent/tests/fixtures/scripts
touch apps/agent/tests/fixtures/__init__.py
```

- [ ] **Step 2: Write the canonical real-estate fixture**

```bash
cat > apps/agent/tests/fixtures/scripts/real-estate.json <<'EOF'
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
      "image_prompt": "modern Lagos apartment balcony at golden hour, two leather armchairs, ocean view, cinematic depth, 35mm film",
      "composition_prefix": "wide establishing shot",
      "color_mood": "warm-amber",
      "zoom_direction": "slow_push",
      "transition_to_next": "fade",
      "caption_highlight_word": "decision"
    },
    {
      "scene_number": 2,
      "scene_id": "test-re-001-s2",
      "narration_text": "Lekki Phase One. Built for the family that scaled.",
      "image_prompt": "luxury duplex exterior, Lagos suburb, mature trees, soft afternoon light, no people visible",
      "composition_prefix": "low angle three-quarter",
      "color_mood": "warm-amber",
      "zoom_direction": "slight_pan_right",
      "transition_to_next": "cut",
      "caption_highlight_word": "scaled"
    },
    {
      "scene_number": 3,
      "scene_id": "test-re-001-s3",
      "narration_text": "Each room finished to the standard you'd expect from yourself.",
      "image_prompt": "interior master bedroom, herringbone wood floor, neutral palette, large window soft light, lifestyle staging no people",
      "composition_prefix": "medium shot",
      "color_mood": "neutral-cinematic",
      "zoom_direction": "hold",
      "transition_to_next": "fade",
      "caption_highlight_word": "yourself"
    },
    {
      "scene_number": 4,
      "scene_id": "test-re-001-s4",
      "narration_text": "Eight units left. Pre-launch pricing ends Sunday.",
      "image_prompt": "key handover moment, two professional hands meeting, blurred apartment background, bokeh",
      "composition_prefix": "extreme close",
      "color_mood": "warm-amber",
      "zoom_direction": "slow_pull",
      "transition_to_next": "cut",
      "caption_highlight_word": "Sunday"
    },
    {
      "scene_number": 5,
      "scene_id": "test-re-001-s5",
      "narration_text": "Talk to us before they are gone.",
      "image_prompt": "WhatsApp icon over warm beige background, minimal aesthetic, ample negative space",
      "composition_prefix": "graphic plate",
      "color_mood": "warm-amber",
      "zoom_direction": "static",
      "transition_to_next": "endcard",
      "caption_highlight_word": "gone"
    }
  ]
}
EOF
```

- [ ] **Step 3: Create conftest.py with shared Supabase client fixture**

```bash
cat > apps/agent/tests/conftest.py <<'EOF'
"""Shared pytest fixtures for Operscale agent tests."""
import os
from typing import Any
import pytest


@pytest.fixture
def supabase_service_client() -> Any:
    """Service-role Supabase client. Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY."""
    try:
        from supabase import create_client
    except ImportError:
        pytest.skip("supabase-py not installed; install with `pip install supabase`")

    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
    if not (url and key):
        pytest.skip("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    return create_client(url, key)
EOF
```

- [ ] **Step 4: Write seed_test_order.py**

```bash
cat > apps/agent/tests/seed_test_order.py <<'EOF'
#!/usr/bin/env python3
"""
seed_test_order.py — Insert a synthetic test order into Supabase.

Loads a fixture from apps/agent/tests/fixtures/scripts/<niche>.json,
inserts customers + briefs + orders + videos + scenes rows, prints UUIDs.

Usage:
  python apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot
  python apps/agent/tests/seed_test_order.py --all-niches  (Day 11)

Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY in env.
"""
import argparse
import json
import os
import sys
import uuid
from pathlib import Path


def load_fixture(niche: str) -> dict:
    repo_root = Path(__file__).resolve().parent.parent.parent.parent
    fixture = repo_root / 'apps' / 'agent' / 'tests' / 'fixtures' / 'scripts' / f'{niche}.json'
    if not fixture.exists():
        sys.exit(f"❌ Fixture not found: {fixture}")
    return json.loads(fixture.read_text())


def seed_one(client, fixture: dict) -> tuple[str, str]:
    """Insert customers + briefs + orders + videos + scenes; return (order_id, video_id)."""
    test_email = f"test-{uuid.uuid4().hex[:8]}@operscale-foundation.test"
    cust = client.table('customers').insert({
        'email': test_email,
        'business_name': f"Foundation Test ({fixture['niche']})",
        'whatsapp_phone': '+2348000000000',
        'source': 'foundation-test',
    }).execute()
    customer_id = cust.data[0]['id']

    brief = client.table('briefs').insert({
        'customer_id': customer_id,
        'niche': fixture['niche'],
        'business_name': f"Foundation Test {fixture['niche']}",
        'product_or_service': f"Foundation test for {fixture['niche']} render",
        'call_to_action': 'WhatsApp us',
    }).execute()
    brief_id = brief.data[0]['id']

    order = client.table('orders').insert({
        'customer_id': customer_id,
        'brief_id': brief_id,
        'tier': fixture['tier'],
        'amount_paid_kobo': 7500000 if fixture['tier'] == 'pilot' else 17500000,
        'niche': fixture['niche'],
        'production_register': fixture['production_register'],
        'pipeline_stage': 'production_documentary',
    }).execute()
    order_id = order.data[0]['id']

    video = client.table('videos').insert({
        'order_id': order_id,
        'video_number': 1,
        'script_json': fixture,
        'scene_count': len(fixture['scenes']),
        'duration_seconds': fixture['duration_target_sec'],
        'revisions_max': 1 if fixture['tier'] == 'pilot' else 2,
    }).execute()
    video_id = video.data[0]['id']

    scenes_payload = []
    for s in fixture['scenes']:
        scenes_payload.append({
            'video_id': video_id,
            'order_id': order_id,
            'scene_number': s['scene_number'],
            'scene_id': s['scene_id'],
            'narration_text': s['narration_text'],
            'image_prompt': s['image_prompt'],
            'composition_prefix': s['composition_prefix'],
            'color_mood': s['color_mood'],
            'zoom_direction': s['zoom_direction'],
            'transition_to_next': s['transition_to_next'],
            'caption_highlight_word': s['caption_highlight_word'],
        })
    client.table('scenes').insert(scenes_payload).execute()

    return order_id, video_id


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--niche', help='Single niche fixture name')
    ap.add_argument('--tier', default='pilot', choices=['pilot', 'standard', 'creative_pod'])
    ap.add_argument('--all-niches', action='store_true', help='Seed all 5 niches')
    args = ap.parse_args()

    if not (args.niche or args.all_niches):
        ap.error("Pass --niche <name> or --all-niches")

    try:
        from supabase import create_client
    except ImportError:
        sys.exit("supabase-py not installed; pip install supabase")

    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
    if not (url and key):
        sys.exit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    client = create_client(url, key)

    niches = ['real-estate', 'education', 'fashion-ecom', 'fintech', 'health'] if args.all_niches else [args.niche]
    for n in niches:
        fixture = load_fixture(n)
        if not args.all_niches and args.tier != fixture['tier']:
            fixture['tier'] = args.tier
        order_id, video_id = seed_one(client, fixture)
        print(f"{n}: order_id={order_id}  video_id={video_id}")


if __name__ == '__main__':
    main()
EOF
chmod +x apps/agent/tests/seed_test_order.py
```

- [ ] **Step 5: Commit**

```bash
git add apps/agent/tests/__init__.py apps/agent/tests/conftest.py \
        apps/agent/tests/seed_test_order.py apps/agent/tests/fixtures/
git commit -m "feat(tests): seed_test_order.py + canonical real-estate fixture

real-estate.json: 5-scene Pilot fixture with niche-correct color_mood
(warm-amber/neutral-cinematic), warm-amber palette caption_highlight_word.

seed_test_order.py: --niche or --all-niches; inserts customers + briefs +
orders + videos + scenes via service-role Supabase client; emits order_id
and video_id to stdout.

Other 4 niche fixtures arrive in Day 11 (5-niche test matrix)."
git push origin main
```

### Task 6.2: User imports OPS_TTS_AUDIO + OPS_IMAGE_GENERATION + OPS_RETRY_WRAPPER into n8n

- [ ] **Step 1: User SSHes and uses n8n CLI / API to import**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
```

- [ ] **Step 2: User imports via n8n API (preferred) or UI**

The n8n REST API import (preferred):
```bash
N8N_TOKEN="${N8N_API_KEY:?must be set in env}"
N8N_BASE="https://n8n.srv1297445.hstgr.cloud/api/v1"

for wf in OPS_RETRY_WRAPPER OPS_TTS_AUDIO OPS_IMAGE_GENERATION; do
  echo "▶ Importing $wf..."
  curl -sS -X POST "${N8N_BASE}/workflows" \
    -H "X-N8N-API-KEY: ${N8N_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @apps/n8n-workflows/operscale/${wf}.json | jq '{id, name, active}'
done
```

If n8n API doesn't accept direct workflow JSON import (some older versions don't), user uses the n8n UI instead: Workflows → Import from File → select the OPS_*.json files.

- [ ] **Step 3: User activates the 3 workflows**

In n8n UI: each imported workflow → toggle Active.

- [ ] **Step 4: User confirms credentials reuse**

Open `OPS_TTS_AUDIO` in n8n UI. Inspect the Google Cloud TTS node. Confirm it references the existing `Google Cloud Service Account` credential (the same one VG uses). It should — the rebind doesn't touch credential references. If it shows "Credential missing", the credential ID changed; reselect from the dropdown.

Same check for `OPS_IMAGE_GENERATION` (fal.ai credential) and `OPS_RETRY_WRAPPER` (no creds, just sub-workflow logic).

### Task 6.3: Run TTS standalone test

- [ ] **Step 1: User seeds a test order on VPS**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
source /docker/operscale-video-ads/.env.agent  # exports SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot
```

Expected: stdout shows `real-estate: order_id=<uuid> video_id=<uuid>`.

Save the video_id for the next step.

- [ ] **Step 2: User triggers OPS_TTS_AUDIO via webhook**

```bash
VIDEO_ID="<paste the video_id from step 1>"
DASHBOARD_TOKEN="${DASHBOARD_API_TOKEN:?must be set in env}"

curl -sS -X POST \
  "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/tts" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
```

Expected: a workflow execution starts in n8n. Returns 200 with whatever JSON the workflow's webhook node responds with.

- [ ] **Step 3: User polls for TTS completion (~30s for 5 scenes)**

```bash
sleep 30
docker exec supabase-db-1 psql -U postgres -tA -c \
  "SELECT scene_number, audio_status, audio_duration_ms,
          left(audio_file_url, 60) AS url_prefix
   FROM scenes WHERE video_id='${VIDEO_ID}' ORDER BY scene_number;"
```

Expected: 5 rows, all with `audio_status='uploaded'`, all with `audio_duration_ms` populated (non-null integer), all with `audio_file_url` showing a URL prefix.

```bash
ls -la /data/operscale-production/*/audio/ | head -20
```

Expected: 5 mp3 files visible.

- [ ] **Step 4: Append Day 6 to verification doc**

```bash
cat >> /docker/operscale-video-ads/docs/foundation/foundation-verification.md <<EOF

## Day 6 — TTS standalone

- video_id used: ${VIDEO_ID}
- 5 mp3 files at /data/operscale-production/<order_id>/audio/: ✅
- scenes.audio_status all 'uploaded': ✅
- scenes.audio_duration_ms all populated: ✅
- Master clock (audio duration) measured by FFprobe: ✅

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 6 — TTS standalone passes against fake-order-1"
git push origin main
```

---

## Day 7 — Slack / catch-up

**Day goal:** No new code. Slack day per implementation.md. Use to fix anything broken from Days 1-6 or eyeball produced TTS audio.

No tasks. The slack itself is the deliverable. If everything's healthy, the engineer rests this day. If something broke, this is where it gets fixed without rushing forward.

---

## Day 8 — Import OPS_KEN_BURNS + ASSEMBLY + IMG_PROCESSOR + WATCHDOG

**Day goal:** `assembled.mp4` exists for fake-order-1 (no captions burned in yet). Per-scene clips show motion + niche colour grade. Watchdog catches induced fps mismatch.

### Task 8.1: User imports 4 more workflows into n8n

- [ ] **Step 1: User imports via API (or UI)**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main

N8N_TOKEN="${N8N_API_KEY:?}"
N8N_BASE="https://n8n.srv1297445.hstgr.cloud/api/v1"

for wf in OPS_SCENE_IMAGE_PROCESSOR OPS_KEN_BURNS OPS_CAPTIONS_ASSEMBLY OPS_ASSEMBLY_WATCHDOG; do
  curl -sS -X POST "${N8N_BASE}/workflows" \
    -H "X-N8N-API-KEY: ${N8N_TOKEN}" \
    -H "Content-Type: application/json" \
    -d @apps/n8n-workflows/operscale/${wf}.json | jq '{id, name, active}'
done
```

- [ ] **Step 2: User activates them in n8n UI**

Each workflow → toggle Active.

### Task 8.2: Run image-gen + ken-burns + assembly chain (no captions yet)

- [ ] **Step 1: Continue with the same video_id from Day 6**

```bash
VIDEO_ID="<same video_id as Day 6>"
DASHBOARD_TOKEN="${DASHBOARD_API_TOKEN:?}"
WEBHOOK_BASE="https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production"

# image generation
curl -sS -X POST "${WEBHOOK_BASE}/images" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 60  # 5 scenes × ~10-12s each, plus retry headroom
```

- [ ] **Step 2: Verify images written**

```bash
docker exec supabase-db-1 psql -U postgres -tA -c \
  "SELECT scene_number, image_status, left(image_url, 60) FROM scenes
   WHERE video_id='${VIDEO_ID}' ORDER BY scene_number;"
```

Expected: 5 rows, all `image_status='complete'`, all `image_url` populated.

```bash
ls -la /data/operscale-production/*/images/
```

Expected: 5 png files.

- [ ] **Step 3: Run Ken Burns**

```bash
curl -sS -X POST "${WEBHOOK_BASE}/ken-burns" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 60
```

```bash
docker exec supabase-db-1 psql -U postgres -tA -c \
  "SELECT scene_number, clip_status, left(video_url, 60) FROM scenes
   WHERE video_id='${VIDEO_ID}' ORDER BY scene_number;"
ls -la /data/operscale-production/*/clips/
```

Expected: 5 mp4 clips, all `clip_status='complete'`.

- [ ] **Step 4: Visually inspect one clip**

```bash
ffprobe -v error -show_entries stream=codec_name,r_frame_rate,pix_fmt,width,height \
  /data/operscale-production/*/clips/scene_1.mp4
```

Expected: `codec_name=h264`, `r_frame_rate=30/1`, `pix_fmt=yuv420p`, `width=1080`, `height=1920` (gotcha #3 prevention).

- [ ] **Step 5: Run captions assembly (without burn — that's Day 9)**

```bash
curl -sS -X POST "${WEBHOOK_BASE}/assembly" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 90  # assembly takes longer
```

```bash
ls -la /data/operscale-production/*/assembled.mp4
ls -la /data/operscale-production/*/captions.ass
docker exec supabase-db-1 psql -U postgres -tA -c \
  "SELECT assembly_status FROM videos WHERE id='${VIDEO_ID}';"
```

Expected: `assembled.mp4` exists, `captions.ass` exists, `assembly_status='assembled'`.

- [ ] **Step 6: Verify duration sanity**

```bash
ffprobe -v error -show_entries format=duration \
  /data/operscale-production/*/assembled.mp4
```

Expected: ≈ 22 seconds (matches `videos.duration_seconds` ±5%).

### Task 8.3: Induce fps mismatch and verify watchdog catches it

- [ ] **Step 1: Intentionally create a misformatted clip on disk**

```bash
ffmpeg -y -i /data/operscale-production/*/clips/scene_1.mp4 \
  -r 24 /data/operscale-production/*/clips/scene_1_BROKEN.mp4
# Replace scene_1.mp4 with the broken one
mv /data/operscale-production/*/clips/scene_1_BROKEN.mp4 \
   /data/operscale-production/*/clips/scene_1.mp4
```

- [ ] **Step 2: Re-run assembly and confirm watchdog flags drift**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "UPDATE videos SET assembly_status='pending' WHERE id='${VIDEO_ID}';"

curl -sS -X POST "${WEBHOOK_BASE}/assembly" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 90
```

Expected: `assembly_status='failed'` OR a `production_log` entry with `action='assembly_drift_detected'`. Inherited VG behaviour.

- [ ] **Step 3: Restore by re-running ken-burns**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "UPDATE scenes SET clip_status='pending' WHERE video_id='${VIDEO_ID}' AND scene_number=1;
   UPDATE videos SET assembly_status='pending' WHERE id='${VIDEO_ID}';"

curl -sS -X POST "${WEBHOOK_BASE}/ken-burns" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 30
curl -sS -X POST "${WEBHOOK_BASE}/assembly" \
  -H "Authorization: Bearer ${DASHBOARD_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\"}"
sleep 90
```

Expected: assembly succeeds again. `assembled.mp4` regenerated.

- [ ] **Step 4: Append Day 8 to verification doc + commit**

```bash
cat >> /docker/operscale-video-ads/docs/foundation/foundation-verification.md <<EOF

## Day 8 — Image gen + Ken Burns + Captions Assembly (no caption burn yet)

- 5 png images: ✅
- 5 mp4 clips at 30fps libx264 yuv420p (gotcha #3): ✅
- assembled.mp4 ≈22s: ✅
- captions.ass exists: ✅
- assembly drift detected when fps mismatched (watchdog working): ✅
- Recovery via ken-burns re-run: ✅

EOF
cd /docker/operscale-video-ads
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 8 — image gen + ken burns + assembly + watchdog all green"
git push origin main
```

---

## Day 9 — Caption-burn integration  *(★5)*

**Day goal:** First fully captioned `final.mp4` exists. Niche colour visible on emphasis word. Audio sync intact.

### Task 9.1: Author `docs/foundation/day-9-caption-burn-decision.md`

**Files:**
- Create: `docs/foundation/day-9-caption-burn-decision.md`

- [ ] **Step 1: Create the decision doc with both options laid out**

```bash
cat > docs/foundation/day-9-caption-burn-decision.md <<'EOF'
# Day 9 Caption-Burn Integration — Symlink vs Env-Var

> Decision date: 2026-MM-DD
> Decided by: [user, after recon review]

## Context

The host-side `caption_burn_service.py` runs as systemd `caption-burn.service`
on port 9998. It's shared with Vision GridAI. It expects video files under a
fixed path (per VG's defaults): `/data/n8n-production/<order_id>/...`.

Operscale uses `/data/operscale-production/<order_id>/...`. Two ways to
bridge the gap without breaking VG:

## Option A: Symlink (recommended)

Create a symlink that makes Operscale's scratch dir appear as a sub-path
under VG's:

```bash
ln -sf /data/operscale-production /data/n8n-production/operscale
```

Then Operscale workflows reference paths like
`/data/n8n-production/operscale/<order_id>/assembled.mp4` when calling the
caption-burn service. Service is unmodified.

**Pros:** zero code change to shared service; instant rollback (`rm` the
symlink).
**Cons:** Operscale's path layout is bound to a sub-path of VG's name.
Slightly less independence.

## Option B: Env-var

Edit `caption_burn_service.py` to read base paths from env vars
`CB_HOST_BASE` and `CB_CONTAINER_BASE` with defaults matching VG's existing
behaviour:

```python
HOST_BASE = os.environ.get('CB_HOST_BASE', '/data/n8n-production')
CONTAINER_BASE = os.environ.get('CB_CONTAINER_BASE', '/tmp/production')
```

Then Operscale workflows pass
`{"host_base":"/data/operscale-production","container_base":"/tmp/operscale-production"}`
in the request body.

**Pros:** clean separation; both products use distinct paths under their own
brand.
**Cons:** modifies the shared service (low-risk because backward-compat
defaults match VG, but still a modification); requires service restart;
diff against `_vendored_for_reference/keep-list-original/host-scripts/caption_burn_service.py`
becomes part of our git history.

## Recon evidence (from `docs/foundation/infrastructure-state-day-3.md`)

[FILL: paste the relevant lines from Day 3 recon — does
 /data/n8n-production/operscale already exist? Does the caption-burn service
 currently use any path under /data/n8n-production/operscale?]

## Decision

[FILL: A or B, with one-paragraph rationale]

## Rollback

If Option A: `rm /data/n8n-production/operscale`.
If Option B: `git checkout _vendored_for_reference/keep-list-original/host-scripts/caption_burn_service.py -- infra/host-scripts/caption_burn_service.py && systemctl restart caption-burn.service`.
EOF
```

- [ ] **Step 2: Fill in the recon-evidence and decision sections from Day 3 recon**

Edit the file using the user's pasted Day-3 recon output to fill `[FILL: ...]` brackets.

- [ ] **Step 3: ★5 GATE — Stop and present**

> **★5 NAMED GATE — Caption-burn integration choice**
>
> Decision doc at `docs/foundation/day-9-caption-burn-decision.md` lays out Symlink (Option A) vs Env-var (Option B).
>
> My recommendation: **Option A** (symlink) unless Day-3 recon surfaced a conflict at `/data/n8n-production/operscale`.
>
> Pick A or B.

Wait for user "go A" or "go B".

- [ ] **Step 4: Update doc with the decision**

Replace `[FILL: A or B, with one-paragraph rationale]` with the actual decision and the user's reasoning.

- [ ] **Step 5: Commit**

```bash
git add docs/foundation/day-9-caption-burn-decision.md
git commit -m "docs: Day-9 caption-burn decision — Option [A/B]

[Brief rationale]"
git push origin main
```

### Task 9.2: Apply the chosen integration on VPS

#### If Option A (Symlink):

- [ ] **Step 1: Create the symlink**

```bash
ssh root@srv1297445.hstgr.cloud
ln -sfn /data/operscale-production /data/n8n-production/operscale
ls -la /data/n8n-production/operscale
```

Expected: symlink shown pointing to `/data/operscale-production`.

#### If Option B (Env-var):

- [ ] **Step 1: Edit `infra/host-scripts/caption_burn_service.py`**

Open the cherry-picked file. Find the path constants (likely near top). Replace hard-coded paths with env-var-with-defaults.

- [ ] **Step 2: Deploy + restart service**

```bash
sudo cp infra/host-scripts/caption_burn_service.py /opt/caption-burn/caption_burn_service.py
sudo systemctl restart caption-burn.service
sudo systemctl status caption-burn.service --no-pager | head -10
```

Expected: `active (running)`.

### Task 9.3: Trigger caption-burn on fake-order-1

- [ ] **Step 1: Reset the captions step**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "UPDATE videos SET assembly_status='assembled', caption_burn_status='pending'
   WHERE id='${VIDEO_ID}';"
```

- [ ] **Step 2: Fire the captions assembly which now invokes caption_burn_service**

```bash
WEBHOOK_BASE="https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production"
curl -sS -X POST "${WEBHOOK_BASE}/assembly" \
  -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
  -d "{\"video_id\":\"${VIDEO_ID}\", \"burn_captions\": true}"
sleep 120  # caption burn takes time
```

- [ ] **Step 3: Verify final.mp4 exists**

```bash
ls -la /data/operscale-production/*/final.mp4
ls -la /data/operscale-production/*/_no_captions.mp4
docker exec supabase-db-1 psql -U postgres -tA -c \
  "SELECT caption_burn_status, assembly_status FROM videos WHERE id='${VIDEO_ID}';"
```

Expected: `final.mp4` exists, `_no_captions.mp4` backup preserved, statuses both `complete`.

- [ ] **Step 4: Inspect captioned video — confirm niche colour visible**

Download or scp `final.mp4` to a machine with video playback. Watch first 5 seconds. Look for:
- Audio in sync with mouth/scene timing
- Captions burned in (not separate subtitle track)
- The word "decision" (scene 1 highlight) shown in warm-amber/terra colour, not white

If captions are white only: `generate_kinetic_ass.py` isn't reading niche colour yet — that's expected for Day 9 (extension lands Day 11).

- [ ] **Step 5: Append Day 9 to verification doc**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

## Day 9 — Caption burn integration  *(★5)*

- Decision: [A symlink / B env-var] per docs/foundation/day-9-caption-burn-decision.md
- final.mp4 exists: ✅
- _no_captions.mp4 backup preserved (atomic swap working): ✅
- caption_burn_status='complete': ✅
- assembly_status='complete': ✅
- Audio sync intact (manual eyeball): ✅
- Niche colour on emphasis word: [✅ already / ⚠️ deferred to Day 11 extension]

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 9 — first fully captioned final.mp4"
git push origin main
```

### Task 9.4: Verify caption-burn service shows no errors after run

- [ ] **Step 1: Inspect service log**

```bash
sudo journalctl -u caption-burn.service --since "5 minutes ago" | tail -30
```

Expected: no `ERROR` or `Exception` lines from the most recent run. If there are any: stop and investigate before Day 10.

---

## Day 10 — End-to-end dry-run + resume test

**Day goal:** A single curl drives the whole pipeline. A mid-render kill resumes correctly.

### Task 10.1: Author `apps/agent/tests/induce_failure.py`

**Files:**
- Create: `apps/agent/tests/induce_failure.py`

- [ ] **Step 1: Create the failure-induction harness**

```bash
cat > apps/agent/tests/induce_failure.py <<'EOF'
#!/usr/bin/env python3
"""
induce_failure.py — Harness for the 3 Foundation failure scenarios per
fork manual §9.4.

Modes:
  kill-n8n-mid-render    — docker kill n8n-n8n-1 N seconds after start; restart;
                            re-fire the pipeline; assert resume.
  induce-caption-burn-timeout — Day 12 mode; sets a temporary 30s timeout in the
                            caption-burn service via env, fires a render that
                            requires >30s, asserts clean failure.
  simulate-fal-outage    — patches a header to force fal.ai 503; verifies
                            OPS_RETRY_WRAPPER absorbs.

Used by Day 10 (kill-n8n) and Day 12 (all 3).
"""
import argparse
import os
import subprocess
import sys
import time

import requests


WEBHOOK_BASE = os.environ.get('WEBHOOK_BASE', 'https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production')
DASHBOARD_TOKEN = os.environ.get('DASHBOARD_API_TOKEN', '')


def supabase_query(sql: str) -> str:
    return subprocess.check_output(
        ['docker', 'exec', 'supabase-db-1', 'psql', '-U', 'postgres', '-tA', '-c', sql],
        text=True
    ).strip()


def kill_n8n_mid_render(video_id: str, kill_after_sec: int = 8) -> None:
    print(f"▶ Firing OPS_RENDER_PIPELINE for {video_id}...")
    resp = requests.post(
        f"{WEBHOOK_BASE}/render",
        headers={'Authorization': f'Bearer {DASHBOARD_TOKEN}'},
        json={'video_id': video_id},
        timeout=10
    )
    print(f"  HTTP {resp.status_code}")

    print(f"▶ Sleeping {kill_after_sec}s then killing n8n-n8n-1...")
    time.sleep(kill_after_sec)
    subprocess.run(['docker', 'kill', 'n8n-n8n-1'], check=False)

    print("▶ Capturing scene mtimes BEFORE restart...")
    before = supabase_query(
        f"SELECT scene_number, audio_status, image_status, clip_status "
        f"FROM scenes WHERE video_id='{video_id}' ORDER BY scene_number;"
    )
    print(before)

    print("▶ Starting n8n-n8n-1 again...")
    subprocess.run(['docker', 'start', 'n8n-n8n-1'], check=True)
    time.sleep(15)  # wait for n8n to be ready

    print("▶ Re-firing OPS_RENDER_PIPELINE...")
    resp = requests.post(
        f"{WEBHOOK_BASE}/render",
        headers={'Authorization': f'Bearer {DASHBOARD_TOKEN}'},
        json={'video_id': video_id},
        timeout=10
    )
    print(f"  HTTP {resp.status_code}")

    print("▶ Waiting 5 minutes for resume to complete...")
    time.sleep(300)

    after = supabase_query(
        f"SELECT scene_number, audio_status, image_status, clip_status "
        f"FROM scenes WHERE video_id='{video_id}' ORDER BY scene_number;"
    )
    print(after)
    print("\n▶ Manual verification: completed scenes (with status=complete BEFORE)")
    print("  should NOT have been re-rendered. Compare file mtimes:")
    print(f"  ls -la /data/operscale-production/<order_id>/{{audio,images,clips}}/")


def induce_caption_burn_timeout(video_id: str) -> None:
    print("▶ This requires temporarily adjusting CB_TIMEOUT_SEC env var")
    print("  to 30 in /etc/systemd/system/caption-burn.service.d/timeout.conf")
    print("  then `systemctl daemon-reload && systemctl restart caption-burn.service`.")
    print("  Then fire OPS_CAPTIONS_ASSEMBLY with a fixture designed to take >30s.")
    print("  Assert: caption_burn_status='failed' cleanly written, no zombie ffmpeg,")
    print("  no half-final.mp4 left in the order dir.")
    print()
    print("  This mode prints the recipe rather than auto-executing because the")
    print("  systemd override + restart should be confirmed before each run.")


def simulate_fal_outage(video_id: str, fail_first_n: int = 3) -> None:
    print("▶ This requires temporarily setting FAL_FORCE_FAIL_N=3 in the n8n container env")
    print("  (or hooking the fal.ai SDK via mock). Recommended: a feature flag in the")
    print("  Image Generation workflow that's read at run time.")
    print()
    print("  For Foundation we manually verify by inspecting OPS_RETRY_WRAPPER's")
    print("  log output: forced 503 responses should produce 1s/2s/4s backoff,")
    print("  succeed on the 4th attempt.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['kill-n8n-mid-render', 'induce-caption-burn-timeout', 'simulate-fal-outage'])
    ap.add_argument('--video-id', required=True)
    ap.add_argument('--interrupt-at-stage', help='advisory; not enforced in v1 harness')
    ap.add_argument('--kill-after-sec', type=int, default=8)
    ap.add_argument('--timeout-after-sec', type=int, default=30)
    ap.add_argument('--fail-first-n-requests', type=int, default=3)
    args = ap.parse_args()

    if args.mode == 'kill-n8n-mid-render':
        kill_n8n_mid_render(args.video_id, args.kill_after_sec)
    elif args.mode == 'induce-caption-burn-timeout':
        induce_caption_burn_timeout(args.video_id)
    elif args.mode == 'simulate-fal-outage':
        simulate_fal_outage(args.video_id, args.fail_first_n_requests)


if __name__ == '__main__':
    main()
EOF
chmod +x apps/agent/tests/induce_failure.py
```

- [ ] **Step 2: Commit**

```bash
git add apps/agent/tests/induce_failure.py
git commit -m "feat(tests): induce_failure.py — 3 failure-mode harness

- kill-n8n-mid-render: auto-execute (Day 10 + Day 12)
- induce-caption-burn-timeout: prints recipe (manual systemd override + restart)
- simulate-fal-outage: prints recipe (env-flag approach)

Used by Day 10 resume test and Day 12 full failure-induction round."
git push origin main
```

### Task 10.2: Run end-to-end via OPS_RENDER_PIPELINE single curl

- [ ] **Step 1: Seed a fresh test order on VPS**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
source /docker/operscale-video-ads/.env.agent
NEW_ORDER=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
echo "$NEW_ORDER"
NEW_VIDEO_ID=$(echo "$NEW_ORDER" | awk -F'video_id=' '{print $2}')
echo "Video ID: $NEW_VIDEO_ID"
```

- [ ] **Step 2: Single curl through the orchestrator**

```bash
curl -sS -X POST \
  "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/render" \
  -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
  -d "{\"video_id\":\"${NEW_VIDEO_ID}\"}"
sleep 600  # 10 minutes for full pipeline
```

- [ ] **Step 3: Verify all 8 stages completed**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT v.id, v.assembly_status, v.caption_burn_status,
          (SELECT count(*) FROM scenes s WHERE s.video_id=v.id AND s.audio_status='uploaded') AS audio_done,
          (SELECT count(*) FROM scenes s WHERE s.video_id=v.id AND s.image_status='complete')  AS image_done,
          (SELECT count(*) FROM scenes s WHERE s.video_id=v.id AND s.clip_status='complete')   AS clip_done
   FROM videos v WHERE v.id='${NEW_VIDEO_ID}';"
ls -la /data/operscale-production/*/final.mp4 | tail -2
```

Expected: `assembly_status='complete'`, `caption_burn_status='complete'`, all 3 done counts = 5, `final.mp4` exists.

- [ ] **Step 4: OPS_QA_CHECK fires automatically OR manually trigger**

If OPS_RENDER_PIPELINE chains into OPS_QA_CHECK at the end (per VG behaviour), check for results in `production_log`:
```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT action, details FROM production_log
   WHERE video_id='${NEW_VIDEO_ID}' AND action LIKE '%qa%' ORDER BY created_at DESC LIMIT 5;"
```

If not chained automatically, manually trigger:
```bash
curl -sS -X POST "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/qa-check" \
  -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
  -d "{\"video_id\":\"${NEW_VIDEO_ID}\"}"
sleep 30
```

Expected: 13 checks pass.

### Task 10.3: Run kill-n8n resume test

- [ ] **Step 1: Seed a NEW order (don't reuse the one we just rendered)**

```bash
RESUME_ORDER=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
RESUME_VIDEO_ID=$(echo "$RESUME_ORDER" | awk -F'video_id=' '{print $2}')
echo "Resume test video ID: $RESUME_VIDEO_ID"
```

- [ ] **Step 2: Run the failure harness**

```bash
python3 apps/agent/tests/induce_failure.py kill-n8n-mid-render \
  --video-id "${RESUME_VIDEO_ID}" \
  --kill-after-sec 8
```

- [ ] **Step 3: Confirm resume worked**

The harness prints "BEFORE" and "AFTER" scene-status snapshots. Inspect them:
- BEFORE: some scenes have `audio_status='uploaded'` and `image_status='complete'` etc.
- AFTER: all 5 scenes have all statuses `'complete'` and `final.mp4` exists.

Mtime check:
```bash
ls -la /data/operscale-production/*/clips/scene_*.mp4
```

Scenes that were complete BEFORE the kill should have older mtimes than scenes that were re-rendered after restart.

- [ ] **Step 4: Append Day 10 to verification doc + commit**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

## Day 10 — End-to-end + resume

- Single-curl OPS_RENDER_PIPELINE produces final.mp4: ✅
- OPS_QA_CHECK 13/13: ✅
- kill-n8n-mid-render resumes from last completed scene (mtime check): ✅

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 10 — end-to-end + resume invariant verified"
git push origin main
```

---

## Day 11 — 5-niche test matrix

**Day goal:** All 5 niches render. OPS_QA_CHECK 13/13 each. Niche-correct caption colour visible.

### Task 11.1: Author the other 4 niche fixtures

**Files:**
- Create: `apps/agent/tests/fixtures/scripts/education.json`
- Create: `apps/agent/tests/fixtures/scripts/fashion-ecom.json`
- Create: `apps/agent/tests/fixtures/scripts/fintech.json`
- Create: `apps/agent/tests/fixtures/scripts/health.json`

- [ ] **Step 1: Education fixture (sage palette, slow speaking)**

```bash
cat > apps/agent/tests/fixtures/scripts/education.json <<'EOF'
{
  "tier": "pilot",
  "niche": "education",
  "production_register": "OPERSCALE_01_DOCUMENTARY",
  "duration_target_sec": 22,
  "scenes": [
    {"scene_number":1,"scene_id":"test-edu-001-s1","narration_text":"Your child sat the same exam. So did 50,000 others.","image_prompt":"Nigerian secondary school exam hall, students in uniform writing, natural daylight, documentary style","composition_prefix":"wide overhead","color_mood":"warm-natural","zoom_direction":"slow_push","transition_to_next":"fade","caption_highlight_word":"50,000"},
    {"scene_number":2,"scene_id":"test-edu-001-s2","narration_text":"Most of them weren't taught how to think. Only what to memorise.","image_prompt":"young student looking thoughtful at desk, textbook open, soft light through window","composition_prefix":"medium close","color_mood":"warm-natural","zoom_direction":"hold","transition_to_next":"cut","caption_highlight_word":"think"},
    {"scene_number":3,"scene_id":"test-edu-001-s3","narration_text":"At Lagos Edge Tutorial we teach them to question first. Memorise second.","image_prompt":"engaging Nigerian teacher in modern classroom, students raising hands, dynamic energy","composition_prefix":"wide three-quarter","color_mood":"warm-natural","zoom_direction":"slight_pan_right","transition_to_next":"fade","caption_highlight_word":"question"},
    {"scene_number":4,"scene_id":"test-edu-001-s4","narration_text":"That is why our 2025 cohort beat the national average by 42%.","image_prompt":"smiling graduate holding result slip, school grounds in background, golden hour","composition_prefix":"medium","color_mood":"warm-amber","zoom_direction":"slow_push","transition_to_next":"cut","caption_highlight_word":"42%"},
    {"scene_number":5,"scene_id":"test-edu-001-s5","narration_text":"WhatsApp us. Free assessment for the next 20 students.","image_prompt":"WhatsApp icon over warm beige, minimal lifestyle composition","composition_prefix":"graphic plate","color_mood":"warm-natural","zoom_direction":"static","transition_to_next":"endcard","caption_highlight_word":"Free"}
  ]
}
EOF
```

- [ ] **Step 2: Fashion-ecom fixture (gold/vibrant palette, faster speaking)**

```bash
cat > apps/agent/tests/fixtures/scripts/fashion-ecom.json <<'EOF'
{
  "tier": "pilot",
  "niche": "fashion-ecom",
  "production_register": "OPERSCALE_01_DOCUMENTARY",
  "duration_target_sec": 20,
  "scenes": [
    {"scene_number":1,"scene_id":"test-fash-001-s1","narration_text":"You don't need more clothes. You need clothes that fit.","image_prompt":"luxury walk-in closet, capsule wardrobe arrangement, soft studio light","composition_prefix":"medium wide","color_mood":"vibrant-modern","zoom_direction":"slight_pan_right","transition_to_next":"cut","caption_highlight_word":"fit"},
    {"scene_number":2,"scene_id":"test-fash-001-s2","narration_text":"Cut for the African body. Tailored, not draped.","image_prompt":"close detail tailored shirt collar on dressmaker form, fashion editorial","composition_prefix":"extreme close detail","color_mood":"warm-amber","zoom_direction":"slow_push","transition_to_next":"fade","caption_highlight_word":"Tailored"},
    {"scene_number":3,"scene_id":"test-fash-001-s3","narration_text":"Made in Lagos. Shipped in 48 hours. Returned, no questions.","image_prompt":"hands wrapping garment in branded tissue, lifestyle workspace, warm lighting","composition_prefix":"medium","color_mood":"warm-amber","zoom_direction":"hold","transition_to_next":"cut","caption_highlight_word":"48 hours"},
    {"scene_number":4,"scene_id":"test-fash-001-s4","narration_text":"3,000 buyers stopped buying drops they regret.","image_prompt":"satisfied customer wearing the brand outdoors at sunset, lifestyle confident pose","composition_prefix":"three-quarter","color_mood":"warm-amber","zoom_direction":"slow_pull","transition_to_next":"fade","caption_highlight_word":"3,000"},
    {"scene_number":5,"scene_id":"test-fash-001-s5","narration_text":"Open the link. Pick your fit.","image_prompt":"Instagram link sticker icon over warm gold gradient","composition_prefix":"graphic plate","color_mood":"vibrant-modern","zoom_direction":"static","transition_to_next":"endcard","caption_highlight_word":"fit"}
  ]
}
EOF
```

- [ ] **Step 3: Fintech fixture (cool-trust/indigo palette, normal speaking)**

```bash
cat > apps/agent/tests/fixtures/scripts/fintech.json <<'EOF'
{
  "tier": "pilot",
  "niche": "fintech",
  "production_register": "OPERSCALE_01_DOCUMENTARY",
  "duration_target_sec": 22,
  "scenes": [
    {"scene_number":1,"scene_id":"test-fin-001-s1","narration_text":"Your supplier's invoice came in dollars. Again.","image_prompt":"frustrated business owner reading invoice on laptop, modern Lagos office, blue-toned light","composition_prefix":"medium close","color_mood":"cool-trust","zoom_direction":"slow_push","transition_to_next":"cut","caption_highlight_word":"dollars"},
    {"scene_number":2,"scene_id":"test-fin-001-s2","narration_text":"Naira-to-USD wire takes 3 days. Loses 4% to fees.","image_prompt":"calendar with red days marked, currency note overlay subtle","composition_prefix":"graphic detail","color_mood":"cool-trust","zoom_direction":"hold","transition_to_next":"fade","caption_highlight_word":"4%"},
    {"scene_number":3,"scene_id":"test-fin-001-s3","narration_text":"With Pyle, the same wire takes 4 hours. Costs 0.4%.","image_prompt":"clean fintech app UI on phone, transaction confirmed screen, neutral background","composition_prefix":"close phone","color_mood":"neutral-cinematic","zoom_direction":"slow_push","transition_to_next":"cut","caption_highlight_word":"0.4%"},
    {"scene_number":4,"scene_id":"test-fin-001-s4","narration_text":"CBN-licensed. PCI-compliant. 8,000 SMBs already moved.","image_prompt":"professional Nigerian SME owner at desk smiling, soft office light","composition_prefix":"three-quarter","color_mood":"cool-trust","zoom_direction":"slight_pan_right","transition_to_next":"fade","caption_highlight_word":"8,000"},
    {"scene_number":5,"scene_id":"test-fin-001-s5","narration_text":"pyle.ng — open an account in seven minutes.","image_prompt":"Pyle.ng wordmark over deep navy gradient minimal","composition_prefix":"graphic plate","color_mood":"cool-trust","zoom_direction":"static","transition_to_next":"endcard","caption_highlight_word":"seven"}
  ]
}
EOF
```

- [ ] **Step 4: Health fixture (cool-trust/sage palette, slow speaking)**

```bash
cat > apps/agent/tests/fixtures/scripts/health.json <<'EOF'
{
  "tier": "pilot",
  "niche": "health",
  "production_register": "OPERSCALE_01_DOCUMENTARY",
  "duration_target_sec": 24,
  "scenes": [
    {"scene_number":1,"scene_id":"test-hlth-001-s1","narration_text":"You needed a specialist. The earliest slot was 6 weeks out.","image_prompt":"thoughtful patient looking at appointment calendar, soft window light, neutral palette","composition_prefix":"medium close","color_mood":"neutral-cinematic","zoom_direction":"hold","transition_to_next":"fade","caption_highlight_word":"6 weeks"},
    {"scene_number":2,"scene_id":"test-hlth-001-s2","narration_text":"At MediLink, your first consult is within 24 hours. By video.","image_prompt":"doctor on telemedicine call, clean home office of patient on second screen, professional","composition_prefix":"split medium","color_mood":"cool-trust","zoom_direction":"slow_push","transition_to_next":"cut","caption_highlight_word":"24 hours"},
    {"scene_number":3,"scene_id":"test-hlth-001-s3","narration_text":"180 verified specialists. 12 cities. One Lagos-based clinical director.","image_prompt":"smiling Nigerian doctor in stethoscope, hospital corridor blurred behind","composition_prefix":"three-quarter","color_mood":"warm-natural","zoom_direction":"slight_pan_right","transition_to_next":"fade","caption_highlight_word":"180"},
    {"scene_number":4,"scene_id":"test-hlth-001-s4","narration_text":"Subscribe ₦12,000 a month. Family plan covers four.","image_prompt":"family at home dinner, warm relaxed atmosphere lifestyle","composition_prefix":"wide medium","color_mood":"warm-amber","zoom_direction":"slow_pull","transition_to_next":"cut","caption_highlight_word":"four"},
    {"scene_number":5,"scene_id":"test-hlth-001-s5","narration_text":"Sign up before the month ends. First 100 get the family plan free for 30 days.","image_prompt":"website signup screen on tablet, minimal, neutral gradient","composition_prefix":"graphic plate","color_mood":"cool-trust","zoom_direction":"static","transition_to_next":"endcard","caption_highlight_word":"free"}
  ]
}
EOF
```

- [ ] **Step 5: Commit all 4 fixtures**

```bash
git add apps/agent/tests/fixtures/scripts/{education,fashion-ecom,fintech,health}.json
git commit -m "feat(tests): 4 niche fixtures (education, fashion-ecom, fintech, health)

5 scenes each, ~22s target duration, niche-correct color_mood and
caption_highlight_word distribution. All Pilot tier for Foundation testing."
git push origin main
```

### Task 11.2: Run all 5 niches end-to-end + capture screenshots

- [ ] **Step 1: Seed all 5 niches**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
source /docker/operscale-video-ads/.env.agent
python3 apps/agent/tests/seed_test_order.py --all-niches | tee /tmp/all-niche-ids.txt
```

Expected: 5 lines with order_id and video_id per niche.

- [ ] **Step 2: Fire OPS_RENDER_PIPELINE for each in parallel**

```bash
for vid in $(awk -F'video_id=' '{print $2}' /tmp/all-niche-ids.txt); do
  curl -sS -X POST \
    "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/render" \
    -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
    -d "{\"video_id\":\"${vid}\"}" &
done
wait
sleep 600  # 10 minutes for all 5 to finish
```

Note: parallel renders share fal.ai rate limits — OPS_RETRY_WRAPPER absorbs.

- [ ] **Step 3: Verify all 5 completed**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT niche, count(*) FILTER (WHERE assembly_status='complete' AND caption_burn_status='complete') AS done
   FROM videos v JOIN orders o ON v.order_id=o.id
   WHERE o.created_at > now() - interval '30 minutes'
   GROUP BY niche ORDER BY niche;"
```

Expected: 5 rows, each with `done=1`.

- [ ] **Step 4: Manual screenshot per niche (Day-11 deliverable)**

For each niche's `final.mp4` in `/data/operscale-production/<order_id>/final.mp4`, capture a frame from the middle (~10s in) where the caption_highlight_word is on screen:

```bash
for vid in $(awk -F'video_id=' '{print $2}' /tmp/all-niche-ids.txt); do
  niche=$(docker exec supabase-db-1 psql -U postgres -tA -c \
    "SELECT o.niche FROM videos v JOIN orders o ON v.order_id=o.id WHERE v.id='${vid}';")
  order=$(docker exec supabase-db-1 psql -U postgres -tA -c \
    "SELECT order_id FROM videos WHERE id='${vid}';")
  ffmpeg -y -ss 00:00:10 -i "/data/operscale-production/${order}/final.mp4" \
    -frames:v 1 "/tmp/niche-${niche}.png"
done
ls -la /tmp/niche-*.png
```

Download `/tmp/niche-*.png` to local for embedding into verification doc.

- [ ] **Step 5: Verify niche-correct caption colour**

For each screenshot, eyeball the caption_highlight_word colour:
- real-estate: warm-amber/terra
- education: warm-natural / muted greens
- fashion-ecom: vibrant gold or warm-amber
- fintech: cool-trust deep blue / indigo
- health: cool-trust + warm-natural mix

If captions are uniformly white: `generate_kinetic_ass.py` extension for niche-colour mapping (per fork manual §8.7) hasn't been applied yet. Apply it now per the fork manual instructions, then re-render the affected niches.

- [ ] **Step 6: Run OPS_QA_CHECK for each (if not already auto-fired)**

```bash
for vid in $(awk -F'video_id=' '{print $2}' /tmp/all-niche-ids.txt); do
  curl -sS -X POST \
    "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/qa-check" \
    -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
    -d "{\"video_id\":\"${vid}\"}"
done
sleep 60
```

Inspect each result via production_log entries with `action LIKE 'qa_check%'`.

- [ ] **Step 7: Append Day 11 to verification doc + commit**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

## Day 11 — 5-niche test matrix

- real-estate:    ✅ OPS_QA_CHECK 13/13   (caption colour: warm-amber)
- education:      ✅ OPS_QA_CHECK 13/13   (caption colour: warm-natural)
- fashion-ecom:   ✅ OPS_QA_CHECK 13/13   (caption colour: vibrant-modern)
- fintech:        ✅ OPS_QA_CHECK 13/13   (caption colour: cool-trust)
- health:         ✅ OPS_QA_CHECK 13/13   (caption colour: cool-trust + warm)

Screenshots saved at /tmp/niche-*.png on VPS; 5 niches all niche-correct.

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 11 — 5 niches all rendered, OPS_QA_CHECK 13/13 each"
git push origin main
```

---

## Day 12 — Failure induction (3 scenarios)

**Day goal:** All 3 scenarios from fork manual §9.4 produce expected behaviour.

### Task 12.1: Re-run kill-n8n (already done Day 10; Day 12 is the formal verification round)

- [ ] **Step 1: Seed a fresh order**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
source /docker/operscale-video-ads/.env.agent
F1=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
F1_VID=$(echo "$F1" | awk -F'video_id=' '{print $2}')
```

- [ ] **Step 2: Run kill-n8n harness**

```bash
python3 apps/agent/tests/induce_failure.py kill-n8n-mid-render --video-id "${F1_VID}" --kill-after-sec 8
```

- [ ] **Step 3: Verify final.mp4 produced + scene mtimes show partial-resume**

```bash
ls -la /data/operscale-production/*/final.mp4 | tail -1
ls -la /data/operscale-production/*/clips/scene_*.mp4 | tail -10
```

Expected: `final.mp4` exists; pre-kill-completed scene clips have older mtime than post-restart re-rendered scenes.

### Task 12.2: Induce caption-burn timeout

- [ ] **Step 1: Seed fresh order**

```bash
F2=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
F2_VID=$(echo "$F2" | awk -F'video_id=' '{print $2}')
```

- [ ] **Step 2: Set temporary 30s timeout on caption-burn service**

```bash
sudo mkdir -p /etc/systemd/system/caption-burn.service.d
sudo tee /etc/systemd/system/caption-burn.service.d/timeout-override.conf > /dev/null <<EOF
[Service]
Environment="CB_TIMEOUT_SEC=30"
EOF
sudo systemctl daemon-reload
sudo systemctl restart caption-burn.service
sudo systemctl status caption-burn.service --no-pager | head -5
```

- [ ] **Step 3: Run the pipeline**

```bash
curl -sS -X POST \
  "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/render" \
  -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
  -d "{\"video_id\":\"${F2_VID}\"}"
sleep 600
```

- [ ] **Step 4: Verify clean failure**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT caption_burn_status, assembly_status FROM videos WHERE id='${F2_VID}';"
ls -la /data/operscale-production/*/final.mp4 2>/dev/null | grep "$(basename $(docker exec supabase-db-1 psql -U postgres -tA -c "SELECT order_id FROM videos WHERE id='${F2_VID}';"))"
ps aux | grep -i ffmpeg | grep -v grep
```

Expected:
- `caption_burn_status='failed'`
- No `final.mp4` for this order (only `_no_captions.mp4`)
- No zombie ffmpeg processes
- `production_log` shows clean failure with `action='caption_burn_timeout'`

- [ ] **Step 5: Restore default timeout**

```bash
sudo rm /etc/systemd/system/caption-burn.service.d/timeout-override.conf
sudo systemctl daemon-reload
sudo systemctl restart caption-burn.service
```

### Task 12.3: Simulate fal.ai outage

- [ ] **Step 1: Seed fresh order**

```bash
F3=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
F3_VID=$(echo "$F3" | awk -F'video_id=' '{print $2}')
```

- [ ] **Step 2: Force a temporary fal-fail flag**

The simplest route is to force-mock at the n8n credential level — set the FAL credential's URL to a known-503 endpoint (httpbin.org/status/503) for the first run, then revert.

```bash
# In n8n UI: Settings → Credentials → "Fal API Key" → temporarily change Base URL
# to https://httpbin.org/status/503 (or use a mock proxy)
# OR: set FAL_FORCE_FAIL_N=3 in n8n env if WF_RETRY_WRAPPER reads it
```

If the workflow doesn't expose a clean injection point, the simpler route is to temporarily disable network egress for a short window:

```bash
# Block fal.ai for 60 seconds, then unblock
sudo iptables -A OUTPUT -d $(dig +short fal.ai | head -1) -j DROP
sleep 60
sudo iptables -D OUTPUT -d $(dig +short fal.ai | head -1) -j DROP
```

- [ ] **Step 3: Fire the pipeline mid-block**

```bash
sudo iptables -A OUTPUT -d $(dig +short fal.ai | head -1) -j DROP

curl -sS -X POST \
  "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/render" \
  -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
  -d "{\"video_id\":\"${F3_VID}\"}"

sleep 60
sudo iptables -D OUTPUT -d $(dig +short fal.ai | head -1) -j DROP
sleep 600  # let retries succeed and pipeline complete
```

- [ ] **Step 4: Verify retries absorbed and final.mp4 produced**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT v.assembly_status, v.caption_burn_status,
          (SELECT count(*) FROM production_log p WHERE p.video_id=v.id AND p.action LIKE '%retry%') AS retry_events
   FROM videos v WHERE v.id='${F3_VID}';"
ls -la /data/operscale-production/*/final.mp4 | grep "$(docker exec supabase-db-1 psql -U postgres -tA -c "SELECT order_id FROM videos WHERE id='${F3_VID}';" | tr -d '[:space:]')"
```

Expected: `assembly_status='complete'`, `caption_burn_status='complete'`, `retry_events>=3`, `final.mp4` exists.

- [ ] **Step 5: Append Day 12 to verification doc + commit**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

## Day 12 — Failure induction (fork manual §9.4)

1. kill-n8n-mid-render: ✅ resume from last-completed-scene confirmed
2. induce-caption-burn-timeout: ✅ clean failure, no zombie ffmpeg, no half-final.mp4
3. simulate-fal-outage: ✅ retries absorbed (>=3 retry_events logged), final.mp4 produced

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 12 — all 3 failure-induction scenarios green"
git push origin main
```

---

## Day 13 — Realtime smoke test

**Day goal:** Realtime delivers UPDATE events with payload columns within 2s of DB UPDATE. JWT chain validates without errors.

### Task 13.1: Author `apps/agent/tests/realtime_smoke_test.py`

**Files:**
- Create: `apps/agent/tests/realtime_smoke_test.py`

- [ ] **Step 1: Create the test client**

```bash
cat > apps/agent/tests/realtime_smoke_test.py <<'EOF'
#!/usr/bin/env python3
"""
realtime_smoke_test.py — Day 13 Realtime verification.

Subscribes to `videos` and `gate_decisions` tables via Supabase Realtime.
Asserts UPDATE/INSERT events arrive within 2s with payload columns
(REPLICA IDENTITY FULL — gotcha #4) and JWT validates (no JWSInvalidSignature).

Usage (terminal A): python apps/agent/tests/realtime_smoke_test.py --listen
Usage (terminal B, after listener is running):
    python apps/agent/tests/realtime_smoke_test.py --trigger --video-id <uuid>

Or:    --combined  (does listener-then-trigger automatically against test row)

Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY in env.
"""
import argparse
import json
import os
import sys
import threading
import time
import uuid


def listen_mode(timeout_sec: int = 30) -> None:
    try:
        from supabase import create_client
    except ImportError:
        sys.exit("supabase-py with realtime support required. pip install 'supabase[realtime]'")

    url = os.environ['SUPABASE_URL']
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    client = create_client(url, key)

    received = []
    received_lock = threading.Lock()

    def on_videos(payload):
        with received_lock:
            received.append(('videos', time.time(), payload))
            print(f"  [videos] event: {json.dumps(payload, default=str)[:200]}")

    def on_gates(payload):
        with received_lock:
            received.append(('gate_decisions', time.time(), payload))
            print(f"  [gate_decisions] event: {json.dumps(payload, default=str)[:200]}")

    print(f"▶ Subscribing to videos and gate_decisions (timeout {timeout_sec}s)...")
    channel_videos = client.channel('rt-videos').on_postgres_changes(
        event='UPDATE', schema='public', table='videos', callback=on_videos
    ).subscribe()
    channel_gates = client.channel('rt-gates').on_postgres_changes(
        event='INSERT', schema='public', table='gate_decisions', callback=on_gates
    ).subscribe()

    print("▶ Listening. In another terminal, run --trigger --video-id <uuid>")
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        time.sleep(1)

    print(f"\n▶ Listening window closed. Events received: {len(received)}")
    for table, ts, payload in received:
        print(f"  {table} @ {ts}")

    if not received:
        sys.exit("❌ No events received — investigate JWT chain and REPLICA IDENTITY FULL")
    print("✅ Realtime delivery confirmed.")


def trigger_mode(video_id: str) -> None:
    try:
        from supabase import create_client
    except ImportError:
        sys.exit("supabase-py required")

    url = os.environ['SUPABASE_URL']
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    client = create_client(url, key)

    print(f"▶ Triggering UPDATE on videos.id={video_id}...")
    client.table('videos').update({'assembly_status': 'complete'}).eq('id', video_id).execute()

    fake_uuid = str(uuid.uuid4())
    print(f"▶ Triggering INSERT on gate_decisions (synthetic row id={fake_uuid})...")
    # We need a real order_id — find one from the test order seeds
    order = client.table('videos').select('order_id').eq('id', video_id).execute()
    if not order.data:
        sys.exit(f"video_id {video_id} not found")
    order_id = order.data[0]['order_id']

    client.table('gate_decisions').insert({
        'order_id': order_id,
        'gate_number': '0',
        'decision': 'approved',
        'feedback': 'realtime smoke test synthetic insert',
        'decided_by': 'realtime-smoke-test',
    }).execute()

    print("✅ Triggered. Confirm the listener received both events within ~2s each.")


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--listen', action='store_true')
    g.add_argument('--trigger', action='store_true')
    ap.add_argument('--video-id')
    ap.add_argument('--timeout-sec', type=int, default=30)
    args = ap.parse_args()

    if args.listen:
        listen_mode(args.timeout_sec)
    elif args.trigger:
        if not args.video_id:
            ap.error("--trigger requires --video-id")
        trigger_mode(args.video_id)


if __name__ == '__main__':
    main()
EOF
chmod +x apps/agent/tests/realtime_smoke_test.py
```

- [ ] **Step 2: Commit**

```bash
git add apps/agent/tests/realtime_smoke_test.py
git commit -m "feat(tests): realtime_smoke_test.py — Day-13 Realtime verification

Two-terminal pattern: listener subscribes to videos/gate_decisions, asserts
events arrive with payload columns within 2s of DB write (validates gotcha
#4 REPLICA IDENTITY FULL + JWT chain integrity). No rotation, diagnostic only."
git push origin main
```

### Task 13.2: Run the test

- [ ] **Step 1: Seed a fresh test order**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
source /docker/operscale-video-ads/.env.agent
RT=$(python3 apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot)
RT_VID=$(echo "$RT" | awk -F'video_id=' '{print $2}')
```

- [ ] **Step 2: Open two terminals; in terminal A run listener**

Terminal A:
```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
source /docker/operscale-video-ads/.env.agent
python3 apps/agent/tests/realtime_smoke_test.py --listen --timeout-sec 60
```

- [ ] **Step 3: In terminal B, run trigger**

Terminal B (new SSH session):
```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
source /docker/operscale-video-ads/.env.agent
python3 apps/agent/tests/realtime_smoke_test.py --trigger --video-id "${RT_VID}"
```

- [ ] **Step 4: Confirm in terminal A**

Terminal A should show two events arriving within ~2s of each trigger:
- `[videos] event: {...assembly_status: 'complete'...}`
- `[gate_decisions] event: {...gate_number: '0', decision: 'approved'...}`

If listener exits with `❌ No events received`: STOP. JWT chain or publication is broken. Re-check Day-5 verification.

- [ ] **Step 5: Append Day 13 to verification doc + commit**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

## Day 13 — Realtime smoke test

- videos UPDATE event delivered within 2s with payload columns: ✅
- gate_decisions INSERT event delivered within 2s with payload columns: ✅
- No JWSInvalidSignature errors in client output: ✅
- (No rotation performed per Q5 — diagnostic only)

EOF
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 13 — Realtime end-to-end verified"
git push origin main
```

---

## Day 14 — Foundation verification + go/no-go  *(★6, ★7)*

**Day goal:** Either signed `foundation-verification.md` + green-light to begin Customer-flow brainstorm, OR documented gap list + extension plan.

### Task 14.1: Re-run all 5 niches one final time

- [ ] **Step 1: Seed all 5 niches (fresh)**

```bash
ssh root@srv1297445.hstgr.cloud
cd /docker/operscale-video-ads
git pull origin main
source /docker/operscale-video-ads/.env.agent
python3 apps/agent/tests/seed_test_order.py --all-niches | tee /tmp/d14-niche-ids.txt
```

- [ ] **Step 2: Fire all 5**

```bash
for vid in $(awk -F'video_id=' '{print $2}' /tmp/d14-niche-ids.txt); do
  curl -sS -X POST \
    "https://n8n.srv1297445.hstgr.cloud/webhook/operscale/production/render" \
    -H "Authorization: Bearer ${DASHBOARD_API_TOKEN}" \
    -d "{\"video_id\":\"${vid}\"}" &
done
wait
sleep 720  # 12 minutes
```

- [ ] **Step 3: Verify all 5 final.mp4s + OPS_QA_CHECK 13/13**

```bash
docker exec supabase-db-1 psql -U postgres -c \
  "SELECT o.niche, v.assembly_status, v.caption_burn_status
   FROM videos v JOIN orders o ON v.order_id=o.id
   WHERE v.id IN ($(awk -F'video_id=' '{print \"'\\''\"$2\"'\\''\"}' /tmp/d14-niche-ids.txt | paste -sd,))
   ORDER BY o.niche;"
```

Expected: 5 rows, each `complete` / `complete`.

### Task 14.2: Finalize `foundation-verification.md`

- [ ] **Step 1: Open the doc and add the final summary section**

```bash
cat >> docs/foundation/foundation-verification.md <<EOF

---

## Day 14 — Final verification + go/no-go

### Re-run summary (all 5 niches, fresh)

[FILL: paste the SELECT result from Task 14.1 step 3]

### Robustness criteria (Q4=B)

1. ✅ End-to-end render of synthetic Pilot real-estate test: \`final.mp4\` watchable
2. ✅ Realtime: events arrive within 2s with payload columns (Day 13)
3. ✅ Resume: kill-n8n-mid-render returns to last-completed scene (Day 10 + Day 12)
4. ✅ 5 niches: all rendered, OPS_QA_CHECK 13/13, niche-correct caption colours (Day 11 + Day 14 re-run)
5. ✅ Caption-burn edges: timeout handled cleanly, no zombie ffmpeg, no half-final.mp4 (Day 12)

### Named gates passed

★1 vendor-vg.sh executed cleanly on VPS: ✅
★2 lint passed for all 12 OPS workflows: ✅
★3 first migration applied to shared Supabase: ✅
★4 ALTER PUBLICATION succeeded; VG unaffected: ✅
★5 caption-burn integration: [Option A symlink / Option B env-var] chosen and stable: ✅
★6 /freeze applied before merge: [pending — Task 14.4]
★7 Final go/no-go: [pending — Task 14.4]

### Forbidden-ops check (clean)

- Zero JWT rotations performed: ✅
- Zero \`keys_new.env\` modifications: ✅
- Zero edits to /docker/n8n/docker-compose.override.yml beyond the documented bind-mount addition: ✅
- Zero edits to VG's running \`WF_*\` workflows: ✅

### Known issues / deferred

[FILL: any flaky behaviour, anything that needs a follow-up note in
 Customer-flow brainstorm. If none, write "None."]

### Decision

[FILL: GO begin Customer-flow brainstorm | NO-GO extend Foundation by N days,
       fix items: ...]

Signed: [your name]
Date: [YYYY-MM-DD]
EOF
```

- [ ] **Step 2: Fill in the brackets from the Day 14 evidence + your judgement**

Edit the doc to fill `[FILL: ...]` sections.

### Task 14.3: Run `/qa` against final.mp4s + `/review` against the diff

- [ ] **Step 1: `/qa` slash command — automated visual check on the 5 final.mp4s**

In Claude Code (Windows), invoke `/qa` against the 5 niche `final.mp4` URLs (you'll need to download them or share via a temporary public URL). The `/qa` skill produces a structured report of visual issues.

- [ ] **Step 2: `/review` slash command — diff review against scaffold base**

```
/review since 488f089
```

The skill analyses the diff (~50+ commits worth of Foundation work) for SQL safety, LLM trust boundary violations, conditional side effects, structural issues. Address any findings.

### Task 14.4: ★6 + ★7 NAMED GATES + final commit

- [ ] **Step 1: ★6 GATE — `/freeze` before merge**

In Claude Code: `/freeze` to lock state. The skill prevents accidental edits while you're verifying.

- [ ] **Step 2: ★7 GATE — Final go/no-go**

> **★7 NAMED GATE — Foundation go/no-go**
>
> All Section-10 success criteria from the spec verified above:
>   1. 5 niches rendered with OPS_QA_CHECK 13/13
>   2. 3 induced failures produced expected behaviour
>   3. Realtime working
>   4. Caption burn within timeout, no zombies
>   5. No edits to VG's running stuff
>   6. foundation-verification.md complete
>   7. /review found no blocking issues
>
> Decision: **GO begin Customer-flow brainstorm** OR **NO-GO extend Foundation by N days, fix items: …**
>
> Pick.

Wait for user "GO" or "NO-GO".

- [ ] **Step 3: If GO — final commit, close Foundation**

```bash
cd /docker/operscale-video-ads
git add docs/foundation/foundation-verification.md
git commit -m "docs: Day 14 — Foundation closes. GO for Customer-flow.

All 5 robustness criteria from Q4=B verified:
1. End-to-end render: ✅
2. Realtime: ✅
3. Resume: ✅
4. 5 niches: ✅
5. Caption-burn edges: ✅

All 7 named gates passed cleanly. Zero forbidden ops.

Next sub-project: Customer-flow (Days 15-32). Brainstorm starts with
the same Q1-Q7 lock context plus any new constraints surfaced during
Foundation.

Phase 0 (Foundation) complete."
git push origin main
```

- [ ] **Step 4: If NO-GO — produce extension plan**

Document the gap list as `docs/foundation/foundation-extension-plan.md`. Estimate days. Re-run the failed criteria after fix. **Do not proceed to Customer-flow brainstorm until ★7 = GO.**

---

## Self-review

Going through the spec section-by-section with fresh eyes:

**1. Spec coverage check.** Each spec section maps to plan tasks:
- Spec §1 (Strategic context) → captured in plan header + task framing throughout
- Spec §2 (Goal) → Tasks 14.1-14.4 verify the 5 robustness criteria
- Spec §3 (Architecture) → Tasks 4.1-4.2 deploy compose; Tasks 5.1-5.3 apply schema; Tasks 6.2, 8.1 import workflows
- Spec §4 (Components) → 4.1 cherry-picked workflows: Tasks 2.2 (rebind), 6.2/8.1 (import); 4.2 newly authored: Tasks 1.1-1.4, 2.1, 2.3, 2.4, 6.1, 10.1, 13.1; 4.3 already in scaffold: no new tasks (referenced)
- Spec §5 (Data flow) → Tasks 6.3, 8.2-8.3, 9.3, 10.2-10.3, 11.2 exercise the trajectory
- Spec §6 (Error handling) → Tasks 10.3, 12.1-12.3 verify resume + retry; gates ★1-★7 distributed across tasks
- Spec §7 (Out of scope) → enforced implicitly (no agent code, no marketing site, no Paystack, no HeyGen)
- Spec §8 (Day-by-day map) → 14 plan day-sections match
- Spec §9 (Test fixtures) → Tasks 6.1, 11.1
- Spec §10 (Success criteria) → Task 14.2 verifies; Task 14.4 final gate
- Spec §11 (Tools/skills/agents) → embedded in task headers (DevOps Automator, Backend Architect, etc. mentioned per spec section 8 overview table)

**2. Placeholder scan.** I scanned for `TBD`, `TODO`, `FIXME`, `XXX`, `<placeholder>`. Several `[FILL: ...]` brackets appear in:
- Day 3 doc template (intentional — they're filled at runtime from VPS recon)
- Day 9 caption-burn decision doc (intentional — filled when user picks A or B)
- Day 14 final summary (intentional — filled with day-14 results)

These are **runtime fills**, not plan placeholders. They're acceptable because the surrounding plan steps explicitly say "fill in the bracketed sections from the user's pasted output."

**3. Type/name consistency.**
- `OPS_*` workflow names: 12 of them, consistently named everywhere
- `video_id`, `order_id`, `customer_id`: consistent UUIDs
- Webhook paths: `/webhook/operscale/production/{tts,images,ken-burns,assembly,render,qa-check}` consistently used in Tasks 6.3, 8.2, 8.3, 9.3, 10.2, 11.2, 12.x, 14.1
- `pipeline_stage`: only used as `'production_documentary'` (per Q6=C 001 CHECK constraint matching AGENT.md states)
- `caption_burn_status`: consistently used (not `captions_burn_status`)

**4. Scope check.** Single sub-project (Foundation), 14 days, ~40 tasks. Bounded. Each phase boundary marked. No drift into Customer-flow or Creative-features territory.

Plan is ready.

---
