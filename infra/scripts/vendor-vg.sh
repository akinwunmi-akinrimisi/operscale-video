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
