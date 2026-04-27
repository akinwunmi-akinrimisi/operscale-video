# 0003. Claude Opus 4.7 as the default agent LLM

Date: 2026-04-21
Status: Accepted

## Context

The agent calls an LLM at three load-bearing points:

1. **Angle generation** — 3 niche-tailored ad angles per order. Quality directly drives Gate 1 outcomes and customer perception of the quote.
2. **Script generation** — 5-12 scenes per video, with `narration_text`, `image_prompt`, `composition_prefix`, `color_mood`, `zoom_direction`, `transition_to_next`, `caption_highlight_word`, etc. This is the most demanding generation step.
3. **Gate evaluator summaries** — quick, cheap summaries that compress brief + render context into something a founder can scan in 30 seconds.

Three model tiers were on the table:

1. **Opus 4.7 across the board.** Highest quality, ~$15/M input + ~$75/M output. Per-order cost: ~$2-4 depending on tier.
2. **Sonnet 4.6 across the board.** Mid quality, ~$3/M input + ~$15/M output. Per-order cost: ~$0.40-0.80.
3. **Mixed: Opus 4.7 for generation, Haiku 4.5 for evaluators.** Best per-task quality at controlled cost.

Quality at Gate 2 is non-negotiable. A bad script triggers regeneration, which doubles or triples the LLM cost, doubles founder review time, and damages customer perception. Spending one full Opus call to avoid two regenerations is a clear win.

## Decision

**Claude Opus 4.7 is the default for angle and script generation. Haiku 4.5 is used for evaluators (gate review summaries, niche detection, quick classifications).**

Concretely:
- `apps/agent/src/states/generating_angles.py` calls Opus 4.7 with the angle generator prompt + brief + niche brief context
- `apps/agent/src/states/generating_script.py` calls Opus 4.7 with the script generator prompt
- Gate 0 niche-detection and Gate 3 render summary use Haiku 4.5
- All calls log to `llm_calls` with model, input_tokens, output_tokens, cost_usd, duration_ms
- The cost-monitor skill (`~/.claude/skills/operscale-video-ads/cost-monitor.md`) enforces tier COGS targets via a supervisor cron

## Consequences

**Per-order COGS targets remain achievable:**
- Pilot ₦75K → ~$3 COGS (Claude $2 + TTS $0.10 + images $0.24)
- Standard ₦175K → ~$6 COGS (Claude $4 + TTS $0.10 + images $0.36 + i2v $0.50)
- Creative Pod ₦350K → ~$15-25 (3 videos × Standard + optional HeyGen + optional voice clone)

Gross margins remain >90% across all tiers.

**Quality matches positioning.** "Looks like a movie trailer" (the cinema-lane positioning per ADR 0013) is defended at the model level — Opus 4.7's prose for narration and its image-prompt construction are the difference between "AI ad" and "AI ad you'd actually run."

**Per-tier model differentiation considered, rejected.** We could have used Sonnet for Pilot and Opus for Standard/Creative Pod. Rejected on operational complexity: switching models mid-pipeline complicates prompt-config versioning and makes regression testing harder. All tiers get Opus 4.7 generation; tier differentiation comes from production register, image quality, music, and post-production register choices.

**Migration path.** When Claude 4.8+ ships, default model is changed in one config file (`apps/agent/src/llm/config.py`) and the migration is rolled out per-niche to validate quality before global cutover.

**Token budget guardrails:** the agent refuses to start a render if `orders.total_cost_usd_estimate > 0.15 * (amount_paid_kobo / 100 / 1650)` (the 15% margin guard).

## Reference

- [AGENT.md](../../AGENT.md) §cost-budgeting.
- [0002](0002-langgraph-not-n8n.md): the agent runtime that calls these models.
- [skills.md](../../skills.md) §cost-monitor.
