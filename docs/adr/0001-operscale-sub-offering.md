# 0001. Operate as Operscale sub-offering, not a new brand

Date: 2026-04-21
Status: **Superseded by [0014](0014-codebase-name-vs-brand.md) and [0015](0015-new-domain-not-subdirectory.md)**

## Context

When the productised AI video ad agency idea was first scoped, we needed to decide whether it should:

1. Launch under the existing `Operscale` parent brand as a sub-offering (e.g. `operscale.ng/video-ads` or "Operscale Video Ads")
2. Launch as a fully independent brand with its own domain and identity

At the time of this ADR, Operscale Systems was the founder's parent AI-automation consultancy with established positioning around bespoke enterprise automation. A sub-offering would inherit that brand equity and avoid the cost of launching a second identity.

## Decision

**Operate as an Operscale sub-offering for v1.**

Concretely:
- Marketing copy, domain, email signatures, customer-facing messaging all reference "Operscale Video Ads"
- Hosted at `operscale.ng/video-ads` or as a subdomain
- Same email infrastructure, same payment processor account, same legal entity

## Consequences

**Saved:** brand-build cost (logo, identity work, domain registration). Inherited any existing Operscale brand equity in the Nigerian SMB market.

**Risk:** brand confusion at customer touch surfaces. The parent positioning ("bespoke enterprise automation, ₦5M+ engagements") could conflict with the productised positioning ("₦75K-350K productised ad agency").

## Why this was superseded

After the post-fork strategy session on 2026-04-26, we recognised:

1. **Brand confusion is a real cost,** not a hypothetical one. SMB customers shopping for ad services do not parse "this enterprise automation agency that also does video" naturally.
2. **SEO independence matters.** Operscale Video Ads needs to rank for "AI video ads Nigeria" without diluting (or being diluted by) Operscale Systems' enterprise SEO.
3. **Future flexibility.** If video-ads spins out as a separate company, having its own domain from day one removes a migration cost.
4. **A `.com` domain costs ~$15/year.** The supposed cost saving of staying under the parent brand is trivial.

[0014](0014-codebase-name-vs-brand.md) introduced the working pattern: codebase name `operscale-video-ads` (stable, internal), customer-facing brand `<brand-name>` (placeholder, locked by Day 15). [0015](0015-new-domain-not-subdirectory.md) committed us to a separate `.com` for the brand.

## Reference

- [0014](0014-codebase-name-vs-brand.md): Codebase name vs customer-facing brand separation.
- [0015](0015-new-domain-not-subdirectory.md): Buy a separate `.com` domain.
- [0017](0017-shop-tld-over-com.md): `.shop` over `.com` for the locked brand `plovera`.
