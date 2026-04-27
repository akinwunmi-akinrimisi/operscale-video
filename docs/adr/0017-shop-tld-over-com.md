# 0017. Use `plovera.shop` (`.shop` TLD) — supersede 0015 `.com` mandate

Date: 2026-04-27
Status: Accepted (supersedes [0015](0015-new-domain-not-subdirectory.md))

## Context

[0015](0015-new-domain-not-subdirectory.md) committed us to buying the customer-facing brand domain on the `.com` TLD (with `.ng` and `.co` defensively). At the time the brand was still placeholder-only.

In the brand-lock decision on 2026-04-27, we chose **plovera** as the customer-facing brand. When we went to register the domain, the natural commerce-signalling option emerged: `plovera.shop`.

Three TLD options were re-evaluated:

1. **`plovera.com`** — broadest brand recognition, conventional choice. Status: availability and pricing being verified at time of decision.
2. **`plovera.shop`** — explicit commerce intent in the TLD itself. Modern, lower competition for "shop"-suffixed brand searches. Lower domain cost.
3. **`plovera.ng`** — Nigeria-local TLD, signals geographic focus, useful for SEO targeting Nigerian SMBs.

`.shop` has matured as a generic TLD: search engines treat it as a normal TLD, and the commerce-intent signal is now well understood by both algorithms and consumers. For a productised commerce-shaped brand (we sell discrete packages at fixed prices via a checkout link), `.shop` is positioning-aligned.

## Decision

**Customer-facing brand domain is `plovera.shop`.**

Concretely:
- All customer-facing copy references `plovera.shop`
- Marketing site hosted at `https://plovera.shop` (and `www.plovera.shop`)
- Email infrastructure: Resend sender domain `mail.plovera.shop`
- Anonymous case study pages at `plovera.shop/o/[order_id]`
- Traefik labels in `infra/traefik/operscale-labels.yml` route both apex and `www` to the `operscale-web` container
- All `<brand-name>` placeholders across the codebase are replaced with `plovera`; all `<brand-name>.com` placeholders with `plovera.shop`
- `plovera.ng` may still be acquired defensively (low cost) but is not the primary domain

## Rationale

1. **Commerce signalling.** The `.shop` TLD telegraphs "this is a place to buy something" before the user even processes the brand name. For a productised tier-priced offering (Pilot/Standard/Creative Pod), that's an honest and useful signal.
2. **Differentiation in a `.com`-saturated market.** Most AI agency competitors (UGC Padi, Snitch.video) use `.com`. `.shop` reads as deliberately modern.
3. **Cost.** `.shop` registration is meaningfully cheaper than `.com` for premium-feel brand names like "plovera".
4. **SEO neutrality confirmed.** Modern Google treats new gTLDs as equivalent to legacy TLDs for ranking. The historical "`.com` is mandatory" intuition no longer holds.

## Consequences

**Brand identity is locked.** The Day 15 deadline in [implementation.md](../../implementation.md) is met early.

**Search-replace pass needed across the codebase.** All `<brand-name>` → `plovera`, `<brand-name>.com` → `plovera.shop`. This was done as part of the initial scaffolding pass on 2026-04-27.

**Email reputation must be built fresh.** Resend sender `mail.plovera.shop` starts with no warm reputation. Mitigation: SPF, DKIM, DMARC records configured at Hostinger DNS before the first transactional email goes out.

**Defensive registrations open.** `plovera.com` and `plovera.ng` should be acquired defensively if available and inexpensive, and 301-redirected to `plovera.shop`. Not a launch blocker.

**`<brand-name>` placeholder convention from [0014](0014-codebase-name-vs-brand.md) is now resolved.** The codebase keeps using `operscale-video-ads` for repo / containers / internal docs. `plovera` is the customer-facing identity.

## Why this supersedes 0015

[0015](0015-new-domain-not-subdirectory.md)'s core decision — *use a separate brand domain, not a subdirectory of `operscale.ng`* — remains correct and is preserved by this ADR. What changes is only the TLD choice (`.com` → `.shop`), driven by:
- Brand selection (`plovera`) being made after 0015 was written
- Re-evaluation of TLD signalling and cost
- Search-engine TLD neutrality being confirmed

[0015](0015-new-domain-not-subdirectory.md)'s body remains intact as historical record per the ADR rule "ADR content is never edited post-hoc."

## Reference

- [0014](0014-codebase-name-vs-brand.md): codebase vs brand-name separation.
- [0015](0015-new-domain-not-subdirectory.md): the superseded decision.
- [infra/traefik/operscale-labels.yml](../../infra/traefik/operscale-labels.yml): Traefik routing.
