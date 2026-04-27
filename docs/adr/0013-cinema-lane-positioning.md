# 0013. Cinema-lane positioning — documentary is hero, avatar is option

Date: 2026-04-26
Status: Accepted

## Context

The Nigerian video ad market for SMBs has several positioning lanes:
- **UGC/avatar lane:** UGC Padi, Snitch.video, Pictory — talking-head style, fast turnaround, low ticket. Differentiator: "feels authentic, like a real person."
- **Production-house lane:** Traditional ad agencies — high ticket (₦2-10M), 4-8 week turnaround, real videography. Differentiator: "professional cinematography, custom shoots."
- **Cinema lane (where we're positioning):** AI-generated documentary aesthetic — golden-hour exteriors, lifestyle interiors, cinematic colour grading, 36-72h turnaround. Mid-ticket (₦75K-350K). Differentiator: "looks like a movie trailer, not a TikTok."

The vast majority of competitors (UGC Padi, Snitch.video, etc.) lean on avatar/UGC aesthetic. Production-house lane is undifferentiated by AI. The cinema lane is largely empty in the AI-SMB space.

Vision GridAI's render core is tuned for documentary aesthetic — the Ken Burns motion, FFmpeg colour grading, Inter font kinetic captions, all evoke long-form documentary content. We inherit that taste.

## Decision

**Operscale Video Ads competes in the cinema lane.** Documentary-grade aesthetic is the brand promise. Avatar-led production is a Creative Pod option for customers who specifically need it; it is NOT our hero positioning.

This decision shapes:
- **Marketing site copy:** lead with "ads that look like trailers" not "AI avatars for your business"
- **Content bank styling:** all 90 pre-launch videos are documentary register (per `content-bank-playbook.md`)
- **Default register:** `OPERSCALE_01_DOCUMENTARY` is the default for all tiers
- **Sales conversation:** founder positions us against UGC Padi by quality-of-look, not by feature parity
- **Visual brand:** marketing-site imagery, case-study OG images, all reflect documentary aesthetic

## Consequences

**Differentiation:** we look different from every other AI-ad agency in Nigeria. Customers choosing us know they're choosing the documentary look.

**Customer self-selection:** customers wanting UGC/avatar style will go to UGC Padi. We're OK losing those leads — they'd be a poor fit for our cinematic register anyway.

**Avatar customers:** for the Creative Pod customer who specifically wants avatar-led, we offer it (per ADR 0011) but they discover this only after engaging with our cinematic brand — not as a top-of-funnel positioning.

**Margin protection:** documentary aesthetic is what VG's render core does best. We're not stretching the platform into territory where it underperforms (e.g., trying to make avatars look as good as HeyGen's hero use cases without the customisation overhead).

**Risk:** if the market overwhelmingly wants UGC-style and we keep losing pitches because of positioning, we'd revisit. Day 90 retro will surface this signal.

## Reference

`ad-creative-playbook.md` §cinema-lane-positioning.
`ugc-padi-analysis.html` — competitive positioning.
ADR 0011: HeyGen Creative Pod only.
