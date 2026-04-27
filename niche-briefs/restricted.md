---
niche: restricted
status: stub
last_updated: 2026-04-27
canonical_register: n/a
restricted: true
---

# Restricted Niches — Niche Brief

> Loaded by the agent at startup. Briefs whose niche or content matches any rule
> here trigger an automatic `restricted-niche` flag at Gate 0. The founder must
> explicitly override (with documented reason) before the order proceeds. See
> `gates-and-approvals.md` §gate-0.

## Hard-restricted (Gate 0 auto-reject by default)

- **Gambling, betting, lotteries** — Nigerian advertising standards + platform
  policies (Meta, TikTok) restrict; we don't serve.
- **Adult content, escort services** — out of scope, brand-incompatible.
- **MLM / pyramid-shaped income claims** — high refund risk + regulatory exposure.
- **Unregistered financial instruments** — see fintech niche brief.
- **Prescription pharmaceuticals direct-to-consumer** — restricted in Nigeria
  outside professional channels.
- **Tobacco, vaping, nicotine products** — platform-banned, legal grey-area in NG.
- **Crypto: any "guaranteed return" or "unregulated investment" copy** — SEC
  cease-and-desist exposure.
- **Political campaigns / candidate advertising** — out of scope at v1.
- **Religious solicitation / tithing campaigns** — too high a complaint risk.

## Soft-restricted (Gate 0 founder review with `restricted-niche` flag)

- Health niche claims involving NAFDAC-registered products
- Crypto educational content (no return claims)
- Alcohol brand advertising (legal but platform-dependent)
- Weight-loss / cosmetic / aesthetic claims (high disclaimer surface)
- Insurance products (CBN/NAICOM disclosure rules)

## What the agent does at intake

When a brief's `niche` or copy matches any rule above:

1. The Gate 0 Notion card is created with a red `restricted-niche` tag.
2. The agent does NOT proceed past Gate 0 until the founder explicitly clicks
   `approve` (with a written reason in `gate_decisions.feedback`).
3. If the founder rejects, the order terminates with `pipeline_stage = 'failed'`
   and a templated rejection email goes out via `WF_OPS_DELIVERY_FANOUT`.

## Operational note

This file is the **deny-list** of niches/copy. The five primary niche briefs
(`real-estate`, `education`, `fashion-ecom`, `fintech`, `health`) are the
**allow-list** with operational context. A brief that matches neither falls
through to Gate 0 with a `niche-unknown` tag and waits for founder triage.
