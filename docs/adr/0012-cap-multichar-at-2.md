# 0012. Cap multi-character dialogue at 2 speakers

Date: 2026-04-26
Status: Accepted

## Context

HeyGen API supports multi-character dialogue (multiple avatars in the same video, with camera cuts between speakers at speaker turns). Customers requesting multi-character ads vary widely in ambition: some want 2 speakers (founder + customer testimonial), some want 3+ (group conversations, panel discussions).

Cost and complexity scale non-linearly with speaker count:
- 2 speakers: ~$15-25 per video (within Creative Pod budget)
- 3 speakers: ~$25-40 per video (margin pressure)
- 4+ speakers: orchestration becomes complex (per-segment HeyGen renders sum up significantly; FFmpeg assembly with multi-camera-cut logic gets fragile)

Quality also suffers at 3+ speakers — visual cut-rate becomes overwhelming for a 60-second ad format.

## Decision

**Hard cap: 2 speakers maximum per video for the Creative Pod tier multi-character feature.** 3+ speakers requires a custom quote and bypasses the standard tier flow.

Mechanically:
- Script generator detects speaker count at Gate 2; if > 2, founder either rewrites to fit ≤ 2 OR escalates to custom-quote
- HeyGen integration code expects `Array<Speaker>` of length 1 or 2
- Custom quote flow: founder discusses 3+ speaker scope with customer directly, prices ad-hoc, manual workflow (not standard pipeline)

## Consequences

**Tier predictability:** Creative Pod stays a fixed-price tier. Custom-quote 3+ speaker orders are explicitly outside Creative Pod, billed separately.

**Visual quality preserved:** 2-speaker camera cuts are well-paced for 15-60 second ads. 3+ becomes a montage-of-faces, which works against our cinematic positioning (ADR 0013).

**Customer expectation management:** marketing site clearly states "2 speakers max for multi-character ads" on the Creative Pod tier description. No surprise at intake.

**Workaround for true 3+ scenarios:** if customer needs 3+ speakers (e.g., group testimonial), founder offers:
- "We can do this as 3 separate Creative Pod orders, each with a different speaker focus" → standard tier flow
- "We can do this as a custom-quote ad" → manual scope + price negotiation
- "We can use a documentary register without avatars" → narrator voice covers all 3 perspectives

**Why not negotiate per order:** negotiated tier pricing is a slippery slope. Once we say yes to 3 speakers for one customer, the next customer wants 4. Hard cap with explicit escape valve (custom quote) is cleaner.

## Reference

ADR 0011: HeyGen creative-pod-only.
`pricing-and-packages.md` §creative-pod.
`gates-and-approvals.md` §gate-3 multi-character review.
