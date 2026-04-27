# Architecture Decision Records (ADRs)

This directory captures significant architectural decisions, their context, trade-offs, and revisit conditions. Every non-obvious choice that would be hard to explain to a new contributor belongs here.

## Index

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-operscale-sub-offering.md) | Operate as Operscale sub-offering, not a new brand | **Superseded by [0014](0014-codebase-name-vs-brand.md) and [0015](0015-new-domain-not-subdirectory.md)** | 2026-04-21 |
| [0002](0002-langgraph-not-n8n.md) | LangGraph (code-first) for the intake agent, not n8n | Accepted | 2026-04-21 |
| [0003](0003-opus-47-default-llm.md) | Claude Opus 4.7 as the default agent LLM | Accepted | 2026-04-21 |
| [0004](0004-shared-vps.md) | Share the Vision GridAI VPS at launch | Accepted (supplemented by [0008](0008-fork-vision-gridai.md)) | 2026-04-21 |
| [0005](0005-email-whatsapp-no-portal.md) | Email and WhatsApp only; no customer portal in v1 | Accepted | 2026-04-21 |
| [0006](0006-all-gates-on-at-launch.md) | All four approval gates active at launch | Accepted (extended by [0011](0011-heygen-creative-pod-only.md) Gate 3-bis) | 2026-04-21 |
| [0007](0007-paystack-only.md) | Paystack as the sole payment provider in v1 | Accepted | 2026-04-21 |
| [0008](0008-fork-vision-gridai.md) | Fork the Vision GridAI render core, don't build from scratch | Accepted | 2026-04-26 |
| [0009](0009-chirp-3-hd-only.md) | Google Cloud Chirp 3 HD as the sole TTS engine | Accepted | 2026-04-26 |
| [0010](0010-fal-playht-cloning.md) | fal.ai PlayHT v3 for voice cloning (not ElevenLabs) | Accepted | 2026-04-26 |
| [0011](0011-heygen-creative-pod-only.md) | HeyGen avatar features locked to Creative Pod tier; introduces Gate 3-bis | Accepted | 2026-04-26 |
| [0012](0012-cap-multichar-at-2.md) | Cap multi-character (multi-speaker) videos at 2 speakers | Accepted | 2026-04-26 |
| [0013](0013-cinema-lane-positioning.md) | Position on documentary cinema aesthetic, not avatar-led | Accepted | 2026-04-26 |
| [0014](0014-codebase-name-vs-brand.md) | Codebase name `operscale-video-ads` separate from customer-facing brand | Accepted | 2026-04-26 |
| [0015](0015-new-domain-not-subdirectory.md) | Buy a new `.com` for the brand; don't host on `operscale.ng/video-ads` | **Superseded by [0017](0017-shop-tld-over-com.md)** | 2026-04-26 |
| [0016](0016-skip-vg-dashboard-for-v1.md) | Skip the Vision GridAI React dashboard; gate review goes through Notion | Accepted | 2026-04-26 |
| [0017](0017-shop-tld-over-com.md) | Use `plovera.shop` (`.shop` TLD) — supersede the `.com` mandate from 0015 | Accepted | 2026-04-27 |

## Reading order for new contributors

If you're new to this repo, ADRs to read **first**, in this order, are:

1. **[0008](0008-fork-vision-gridai.md)** — sets the foundational architectural shape: we forked Vision GridAI rather than building greenfield. Without this, the rest of the ADRs and the `VISION_GRIDAI_FORK_MANUAL.md` make no sense.
2. **[0014](0014-codebase-name-vs-brand.md)** — explains why the codebase says `operscale-video-ads` everywhere but customer-facing copy says `<brand-name>` placeholder.
3. **[0013](0013-cinema-lane-positioning.md)** — the strategic positioning that drives every production-quality decision downstream.
4. **[0011](0011-heygen-creative-pod-only.md)** — explains why Creative Pod is the only tier with avatar features and why Gate 3-bis exists.
5. **[0002](0002-langgraph-not-n8n.md)** + **[0003](0003-opus-47-default-llm.md)** — the agent-side stack choices.

Everything else can be read on demand when you encounter the related code or doc reference.

## Supersession map

| ADR | Superseded by | Supplemented / extended by |
|---|---|---|
| 0001 | 0014, 0015 | — |
| 0004 | — | 0008 |
| 0006 | — | 0011 (Gate 3-bis) |
| 0015 | 0017 | — |

Superseded ADRs **stay in the repo** as historical record. Don't delete them. The `Status` field at the top of the file should read `Superseded by NNNN` and reference the replacing ADR.

## Writing a new ADR

1. **Number sequentially:** next would be 0018.
2. **Use the template below.**
3. **States:** `Proposed` → `Accepted` / `Rejected`. Once accepted, an ADR can later become `Superseded by NNNN` but its content is **never edited post-hoc**.
4. **If context changed,** write a new ADR that supersedes the old one and cross-link both directions. The old ADR's status changes; its body stays.
5. **Keep ADRs short** (1-2 pages). Long explanations go into the docs they reference, not into the ADR itself.

## ADR template

```markdown
# ADR NNNN — <Title in one line>

- **Status:** Proposed
- **Date:** YYYY-MM-DD
- **Deciders:** <names>

## Context

What situation does this decision respond to? What constraints, conflicts, or
new information triggered the decision? Stick to facts; reasoning goes below.

## Decision

One clear statement of what was decided. Should fit in 1-3 sentences.

## Rationale

Numbered reasons. Each reason should be a self-contained argument.

1. ...
2. ...
3. ...

## Consequences

### Positive
- ...

### Negative
- ...

## Revisit conditions

What specific triggers would cause us to re-examine this decision? Examples:
- "If monthly cost exceeds $X"
- "If customer count exceeds Y"
- "If <metric> changes by Z%"

## Related

- Affected docs: ...
- Affected code: ...
- Other ADRs: ...
```

## Where ADRs come from

Most ADRs in this repo emerged from:

- **Architecture elicitation rounds** during planning (0001-0007, late April 2026)
- **Post-fork-decision strategy session** when we chose to fork Vision GridAI rather than build greenfield (0008-0016, April 26 2026)

Future ADRs will emerge from:
- New service integrations (a new payment provider, a new render engine)
- Significant cost or scale inflection points (e.g., migrating off Hostinger when we hit KVM 8 ceiling)
- New tier introductions or pricing model changes
- Regulatory pressure (NDPC interpretation changes, advertising standards changes)

When in doubt: **if you're going to have to explain this decision to a new hire in 6 months, write the ADR now.**
