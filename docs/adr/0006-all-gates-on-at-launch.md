# 0006. All four approval gates active at launch

Date: 2026-04-21
Status: Accepted (extended by [0011](0011-heygen-creative-pod-only.md) Gate 3-bis)

## Context

The order lifecycle has natural human-in-the-loop checkpoints:

- **Gate 0:** Brief sanity check. Is this niche workable, is it not in `niche-briefs/restricted.md`, is the ask achievable with our register?
- **Gate 1:** Angle approval. Founder picks 1 of the 3 angles the agent proposed (or asks for a regenerate).
- **Gate 2:** Full script approval. Every scene, every line, every image prompt. The most expensive review per order.
- **Gate 3:** Final render review. Last sanity check before customer sees the file.

Two options for v1:

1. **All four gates active from day one.** Slower ops, safer customer outcomes. Founder reviews 4 times per order.
2. **Defer Gate 0 and Gate 3.** Trust the agent on intake (no Gate 0); trust the render on output (no Gate 3). Founder reviews only Gate 1 and Gate 2. Halves founder time per order.

Option 2 is appealing for ops capacity. The argument against: the cost of a bad output reaching a customer (refund, reputation, NDPC complaint risk) is much higher than the cost of one extra founder review.

For Pilot tier specifically, Gate 1 + Gate 2 are reviewed in a single bundled Notion card to reduce founder load by half — but the gates themselves are still active.

## Decision

**All four approval gates are active from launch.** Gate 1 and Gate 2 are bundled for Pilot tier; separate for Standard and Creative Pod.

Concretely:
- Every order passes through Gate 0 → Gate 1 → Gate 2 → Gate 3 (with 3-bis branch for Creative Pod custom-avatar orders, see [0011](0011-heygen-creative-pod-only.md))
- All gates surface in Notion (per [0016](0016-skip-vg-dashboard-for-v1.md))
- Per-tier SLAs:
  - Gate 0: first business hours
  - Gate 1: ≤ 4 business hours (or bundled with 2 for Pilot)
  - Gate 2: ≤ 12 business hours
  - Gate 3-bis (Creative Pod custom avatar): ≤ 4 hours
  - Gate 3: ≤ 6 hours
- Agent suspends order at each gate via Supabase Realtime subscription on `gate_decisions`

## Consequences

**Customer outcome variance is bounded.** No render reaches a customer without a founder eyeballing it. The "AI sent something embarrassing to my customer" failure mode is closed.

**Founder time is the binding capacity constraint.** At 8 hours/day available for review, ceiling is ~8 Pilot/day OR 5 Standard/day OR 3 Creative Pod/day. Hire reviewer #2 when sustained 5+ orders/day.

**Per-order founder time:**
- Pilot: 30 min total (15-20 min Gate 1+2 bundled, 10 min Gate 3, ~5 min Gate 0)
- Standard: 60 min total
- Creative Pod: 90 min total (plus Gate 3-bis if custom avatar)

**Compute cost of regeneration is non-trivial** when Gate 2 rejects a script. Per [AGENT.md](../../AGENT.md), regeneration consumes another Opus 4.7 script call (~$0.75) plus another founder review. Bias the Gate 1 angle pick toward the safest direction to reduce Gate 2 regenerate rate.

**Bundled Gate 1+2 for Pilot is a deliberate quality compromise.** Pilot's tighter margin doesn't support 90-min/order founder time. The bundled gate is a single review pass with both angle and script in one Notion card.

## Revisit conditions

Defer or auto-approve a gate if:
- Gate 0 false-positive rate (briefs that pass Gate 0 but get refunded later) is < 1% over 30 orders → consider auto-approving Gate 0 for known-good niches
- Gate 1 regenerate rate is < 5% over 30 orders → consider auto-picking the agent's recommended angle for Pilot tier
- Gate 3 rejection rate is < 2% over 30 orders → consider auto-approving Gate 3 for Pilot tier and flagging only structural failures

Each of these would require explicit founder sign-off and a fresh ADR — not silently deferred.

## Extension

[0011](0011-heygen-creative-pod-only.md) introduced **Gate 3-bis** — a photo-quality auto-check + founder override gate that fires when a Creative Pod customer chooses custom-avatar production. This is a branch gate, not a fifth main gate.

## Reference

- [gates-and-approvals.md](../../gates-and-approvals.md): full per-gate review checklists.
- [AGENT.md](../../AGENT.md) state machine.
- [0011](0011-heygen-creative-pod-only.md): Gate 3-bis.
- [0016](0016-skip-vg-dashboard-for-v1.md): Notion as the gate surface.
