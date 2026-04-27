# Day 1 — VG workflow naming correction

> Discovered during ★1 named gate execution on 2026-04-27.

## What happened

The `vendor-vg.sh` script (per the original spec section 4.1 and the inherited
fork manual) listed the keep-list orchestrator workflow as **`WF_SHORTS_PRODUCE.json`**.

Running the script on the VPS produced 10 successful workflow copies, then halted at:

```
❌ NOT FOUND: WF_SHORTS_PRODUCE.json — investigate
```

A read-only inspection of the live VG repo at
`https://github.com/akinwunmi-akinrimisi/vision-gridai-platform.git` (SHA
`345b90aecf9c0e5497706d4a3b32e76561f9f96c`) showed:

- `WF_SHORTS_PRODUCE.json` does **not** exist in the workflow inventory.
- `WF_MASTER.json` exists at `workflows/WF_MASTER.json` and is an 18-node n8n
  workflow that begins with `Webhook Trigger → Check Auth → Validate →
  Respond 202 → Read Topic → Determine Start Stage → Trigger Script ...`
- Several hash-suffixed `WF_MASTER__<random>.json` variants also exist; these
  are older n8n auto-exports of the same workflow. The canonical un-suffixed
  `WF_MASTER.json` is the one to vendor.

## Correction applied

The keep-list slot for the top-level orchestrator was renamed
**`WF_SHORTS_PRODUCE` → `WF_MASTER`** in:

- `infra/scripts/vendor-vg.sh`
- `docs/superpowers/specs/2026-04-27-foundation-design.md`
- `docs/superpowers/plans/2026-04-27-foundation-plan.md`
- `implementation.md`

The Operscale rebound name remains `OPS_RENDER_PIPELINE` (no change to our naming).

## Files NOT modified

Per the ADR rule "ADR content is never edited post-hoc":

- `docs/adr/0008-fork-vision-gridai.md` — historical
- `docs/VISION_GRIDAI_FORK_MANUAL.md` — inherited; modifying it would distort the
  upstream fork-manual reference

If anyone reads those documents in the future and sees `WF_SHORTS_PRODUCE`, the
intended referent is `WF_MASTER` per this note.

## Future-VG-rename mitigation

The `find ... -name "$wf" -type f | head -1` pattern in `vendor-vg.sh` is brittle
to upstream renames. Two ways to harden it (deferred to Customer-flow-phase
hygiene, not Foundation):

1. Match on the workflow's internal `name` field (read each `*.json` and check
   `json.load(...)['name']`) rather than file name — survives file renames.
2. Pin to a specific VG SHA via `git checkout <sha>` after clone — survives
   upstream evolution but loses upstream improvements.

For Foundation we accept the brittleness; the rename was caught by the script's
fail-fast behaviour on Day 1, exactly when it should be.
