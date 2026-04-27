# 0011. HeyGen avatar features locked to Creative Pod tier

Date: 2026-04-26
Status: Accepted

## Context

Avatar-driven video (talking head, lip-sync to script) is a viable production style for some niches (founder-led content, fintech CEO trust-building, education tutors). Two delivery routes:

1. **Documentary register only.** No avatar offering. We compete purely on cinematic storytelling.
2. **Avatar option on all tiers.** Avatar production is offered for Pilot, Standard, AND Creative Pod.
3. **Avatar option Creative Pod only.** Avatar is the differentiating feature for the highest tier.

HeyGen API supports both stock avatars (their library) and custom avatars from photo uploads. Multi-character (up to 2 speakers) is supported. Per-segment render time is ~3 minutes; quality is industry-leading.

Cost: ~$5-15 per Creative Pod video depending on length and avatar complexity.

## Decision

**HeyGen avatar features are Creative Pod tier only.** Pilot and Standard remain documentary-only.

The Creative Pod customer chooses at intake (or shifts to it via Gate 2 conversation):
- Documentary register (default — same as Pilot/Standard quality, just 3 videos)
- Avatar-led register with stock HeyGen avatar
- Avatar-led register with custom avatar from customer's photo

## Consequences

**Tier differentiation:** Creative Pod becomes meaningfully different, not just "3× Standard." The avatar option is the salient upgrade reason.

**Margin compression risk capped:** by limiting HeyGen to Creative Pod (₦350K), we can absorb the $5-15 marginal cost without breaking margin. Pilot at ₦75K could not absorb it.

**Founder review burden:** avatar-led orders require Gate 3-bis (photo quality check). This adds founder time per Creative Pod order, but Creative Pod volume is lower than Pilot.

**Consent obligations:** custom avatars require explicit photo consent + retention policy + IP address logging. See `security.md` §customer-photo-consent.

**Hard cap on speakers:** see ADR 0012. Multi-character HeyGen rendering is capped at 2 speakers. 3+ requires custom quote.

**Why we rejected option 1 (no avatar offering):** we'd cede the founder-led-content niche entirely to UGC Padi and competitors. Creative Pod customers explicitly want this as a differentiator.

**Why we rejected option 2 (avatar on all tiers):** Pilot can't absorb the cost without margin compression. Standard could but at the price of muddying tier differentiation.

**Documentary remains the hero positioning** per ADR 0013. Avatar is a Creative Pod addition, not our brand identity.

## Reference

`docs/specs/heygen-integration.md` — implementation details.
ADR 0012: cap multi-character at 2 speakers.
ADR 0013: cinema-lane positioning (documentary is the hero).
`gates-and-approvals.md` §gate-3-bis.
