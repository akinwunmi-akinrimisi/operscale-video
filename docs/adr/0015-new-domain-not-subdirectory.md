# 0015. Buy a new `.com` domain; do not host on `operscale.ng/video-ads`

Date: 2026-04-26
Status: Accepted

## Context

Akinwunmi already owns `operscale.ng` for Operscale Systems (the parent AI automation agency). Two options for hosting Operscale Video Ads:

1. **Subdirectory:** `operscale.ng/video-ads/` — reuse existing domain, no new domain purchase, brand-association with Operscale Systems.
2. **Subdomain:** `videoads.operscale.ng` — same effect as subdirectory, slightly different SEO posture.
3. **Separate `.com` domain** under the locked `<brand-name>`: `<brand-name>.com` — full brand independence.

## Decision

**Buy a separate `.com` domain.** Operscale Video Ads is a productised offering distinct from Operscale Systems' bespoke automation work. The customer experience, pricing, target market, sales motion, and content strategy are all different from the parent company.

Concretely:
- Buy `<brand-name>.com` (and `.ng` defensively, plus `.co` if available)
- Set up Hostinger DNS pointing at the same VPS as Vision GridAI/Operscale shared infrastructure
- Marketing site, intake form, customer email/WhatsApp templates all reference `<brand-name>.com`
- Operscale Systems retains `operscale.ng` for its own positioning
- Customer-facing email comes from a `<brand-name>.com` address (to be set up via Resend)

## Consequences

**Brand clarity:** Nigerian SMB customers see a focused video-ads-only brand. They don't have to navigate "is this an automation agency that also does video?" confusion.

**Marketing independence:** ad copy, content bank social handles, and case-study pages all live on `<brand-name>.com`. We can position Operscale Video Ads aggressively without affecting Operscale Systems' enterprise positioning.

**SEO independence:** building search authority for "AI video ads Nigeria" doesn't dilute or get diluted by Operscale Systems' enterprise-automation SEO.

**Cost:** ~$15/year per domain. Trivial.

**Coordination overhead:** founder must keep two brand-positioning narratives straight in their own marketing. Mitigation: clear separation in mind ("Operscale Systems = bespoke AI automation for ₦5M+ contracts; Operscale Video Ads = productised ad agency at ₦75K-350K").

**Future flexibility:** if Operscale Video Ads spins out as a separate company, the brand and domain are already independent.

**Email infrastructure:** Resend accounts can be brand-segregated. Sender domain `mail.<brand-name>.com` distinct from `operscale.ng` mail.

**Why we rejected subdirectory/subdomain options:** brand confusion at customer-touch surfaces is the bigger cost than $15 of domain registration.

## Reference

ADR 0014: codebase vs brand name separation.
