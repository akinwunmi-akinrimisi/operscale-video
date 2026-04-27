# 0014. Codebase name `operscale-video-ads` separate from customer-facing brand

Date: 2026-04-26
Status: Accepted

## Context

We need names for two distinct things:
- **The repository, Docker containers, env-var prefixes, internal documentation:** these are stable infrastructure-level identifiers that change rarely.
- **The customer-facing brand:** the `.com` domain, marketing-site copy, email signatures, WhatsApp message templates. This is consumer-facing and evolves with positioning.

Locking both names early is risky — pre-launch positioning often shifts after the first 30 days of customer feedback. But leaving everything as `<placeholder>` makes the codebase clinical and harder to read.

Three options:

1. **Single name everywhere.** Pick one, use it for repo + brand + everything.
2. **`<brand-name>` placeholder until we lock.** Keep all docs neutral, search-and-replace later.
3. **Two-name pattern:** working codebase name now, brand placeholder for customer-facing strings until locked.

## Decision

**Adopt the two-name pattern.**

| Surface | Name |
|---|---|
| GitHub repo | `operscale-video-ads-platform` |
| Docker containers | `operscale-web`, `operscale-agent` |
| Internal docs | "Operscale Video Ads" or "the platform" |
| Env var prefixes (where needed) | `OPERSCALE_*` |
| Local dirs (e.g. `/data/operscale-production/`) | `operscale-*` |
| Workflow prefix in n8n | `OPS_*` |
| Customer-facing brand name | `<brand-name>` placeholder |
| Customer-facing domain | `<brand-name>.com` placeholder |
| Email/WA template variables | `${BRAND_NAME}`, `${BRAND_DOMAIN}` |

The customer-facing `<brand-name>` will be locked before Day 15 of the implementation plan (when the marketing site goes live).

## Consequences

**Stability:** repo + container names are intentionally low-poetry, descriptive of function. They survive re-positioning. They don't show up in customer-facing UX.

**Flexibility:** brand name decision is deferrable up to Day 15 without rewriting code. Search-and-replace `<brand-name>` is trivially scoped to a small handful of customer-facing files.

**Search-replace safety:** we use the literal string `<brand-name>` (with angle brackets) so accidental matches are zero. `operscale-` prefix is stable; `<brand-name>` is a placeholder marker.

**Brand candidates short-list:** at the time of this ADR, candidates being considered:
- Sello (Yoruba "to thrive" connotations)
- Layi (Yoruba "lay-out", short and pronounceable)
- Reelcraft (English-descriptive, available .com)

Final decision will be a separate ADR (TBD).

**Why not lock now:** founder taste and customer-feedback signal matter for brand. We'd rather decide after our first 5-10 customer conversations.

**Why not all-placeholder:** internal-language fatigue. Reading "the `<product-name>` codebase has `<product-name>` containers" is harder than "the `operscale-video-ads` codebase has `operscale-*` containers."

## Reference

`CLAUDE.md` §what-this-codebase-is — placeholder convention.
ADR 0015: new domain (separate from this name decision).
