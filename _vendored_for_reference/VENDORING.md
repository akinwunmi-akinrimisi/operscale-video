# Vendored Vision GridAI snapshot

This directory will hold a **read-only vendored snapshot** of the Vision GridAI platform.
The snapshot is the source of truth for what the fork inherits unchanged
(per ADR 0008 and `docs/VISION_GRIDAI_FORK_MANUAL.md`).

> **Status at scaffold time (2026-04-27):** placeholder only. The actual snapshot
> is dropped in during Day 1 of the implementation plan (per `implementation.md` §Day-1).

---

## Vendoring procedure (Day 1)

```bash
# 1. Clone the upstream Vision GridAI repo at a known SHA
git clone https://github.com/akinwunmi-akinrimisi/vision-gridai-platform.git /tmp/vg-snapshot

# 2. Note the SHA we're vendoring
cd /tmp/vg-snapshot
VG_SHA=$(git rev-parse HEAD)
echo "Vendored from VG @ $VG_SHA on $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "C:/Users/DELL/Documents/Antigravity/operscale-video/_vendored_for_reference/SNAPSHOT_INFO.txt"

# 3. Copy contents (no .git)
cd "C:/Users/DELL/Documents/Antigravity/operscale-video/_vendored_for_reference"
rsync -a --exclude='.git' /tmp/vg-snapshot/ ./vision-gridai-platform/

# 4. Commit (single commit, full snapshot — no trickle imports)
git add _vendored_for_reference/
git commit -m "Vendor Vision GridAI @ ${VG_SHA:0:12} for fork reference"
```

After vendoring, run the Day-2 Prune Commit per `VISION_GRIDAI_FORK_MANUAL.md` §3.1
to delete YouTube/social/long-form/intelligence-layer files in **one commit**.
Trickle-deletion is forbidden by the `prune-commit` skill — see `skills.md`.

---

## What we keep from the snapshot (the keep-list)

The render core is inherited unchanged:

- `WF_TTS_AUDIO` (Google Cloud Chirp 3 HD per-scene TTS, master clock)
- `WF_IMAGE_GENERATION` (fal.ai Seedream 4.5)
- `WF_SCENE_*_PROCESSOR` (single-scene workers for retries)
- `WF_SEEDANCE_I2V` (fal.ai Seedance 2.0 Fast — Creative Pod only)
- `WF_KEN_BURNS` (FFmpeg zoompan + 7 colour-mood filter chains)
- `WF_CAPTIONS_ASSEMBLY` (47-node concat workflow with 3-layer crash prevention)
- `WF_RETRY_WRAPPER` (exponential backoff sub-workflow)
- `WF_ASSEMBLY_WATCHDOG` (cron monitoring stuck FFmpeg renders)
- `WF_ENDCARD` + `WF_MUSIC_GENERATE` (Standard+ tier extensions)
- The host-side `caption_burn_service.py` (port 9998), `generate_kinetic_ass.py`,
  `whisper_align.py`, `burn_captions.sh`

These are imported into our n8n with the `OPS_*` prefix and `/webhook/operscale/...`
path namespace. See the `vg-workflow-rebind` skill for the rebind procedure.

---

## What gets pruned

See `VISION_GRIDAI_FORK_MANUAL.md` §3.1 for the full deletion list.
Brief summary: YouTube uploaders, social-media schedulers, long-form 2-hour
topic generation, niche research crawlers, intelligence-layer analytics,
the Australian-overlay metadata. Approximately 60% of VG's surface area.

---

## License + attribution

Vision GridAI's license headers (where present) are preserved on every
inherited workflow JSON and host-side script. Attribution to the original
authors lives both in this `VENDORING.md` and in the per-file headers
of the kept workflows.

---

## Why this directory is gitignored except for `VENDORING.md`

The vendored snapshot is large and contains files we do not want re-versioned
in our git history (third-party deps, generated artefacts, large binaries).
We commit `VENDORING.md` and `SNAPSHOT_INFO.txt` so anyone reading the repo
knows where the snapshot came from and how to re-vendor it locally.

The actual snapshot lives on disk in this directory but is excluded from git
via `.gitignore`'s `_vendored_for_reference/*` rule.
