# 0002. LangGraph (code-first) for the intake agent, not n8n

Date: 2026-04-21
Status: Accepted

## Context

We need an orchestration layer that drives the order lifecycle from `brief_received` through `deliver`: calls Anthropic for angle and script generation, listens for human gate decisions, fires production workflows in n8n, holds state during waits, and resumes correctly after a process crash.

Two natural options:

1. **n8n as the orchestrator.** Vision GridAI uses n8n for everything including its render pipeline. Continuing in n8n would mean one tool to learn, one runtime to deploy, single observability surface.
2. **LangGraph (Python) as a separate orchestrator.** A code-first state machine with explicit waits and checkpointing. n8n stays purely for render-pipeline and webhook glue.

n8n's strengths are visible workflows, fast credential reuse, and the existing VG investment. Its weakness for our use case is the agent's logic shape: long-running waits (12+ hours for a Gate 2 decision), complex branching on tier and register, structured LLM calls with token-count auditing, and resume guarantees that span multiple LLM calls. n8n can do all of this, but each piece is awkward — sub-workflows for waits, JS functions for token math, careful idempotency by hand on every node.

LangGraph models this naturally: each state is a function with an explicit `pipeline_stage` write and a Realtime subscription wait. Crash recovery is a single line (read `pipeline_stage` from Postgres on startup). Tests are pytest, not n8n's manual test panel.

## Decision

**LangGraph (Python 3.11) is the agent orchestrator.** n8n remains the render-pipeline runner and the webhook gateway for external services (Paystack, Notion, Resend, Evolution API).

Concretely:
- `apps/agent/` is a Python 3.11 + LangGraph project deployed in the `operscale-agent` Docker container
- The agent listens to Supabase Realtime on `gate_decisions` and `videos` tables
- The agent triggers n8n via HTTP POST to webhook endpoints (`/webhook/operscale/...`)
- n8n owns the rendering chain (`OPS_TTS_AUDIO` → `OPS_IMAGE_GENERATION` → … → caption burn) and never makes orchestration decisions itself
- The contract between agent and n8n is a typed JSON payload posted to a webhook with a Bearer token

## Consequences

**Resume guarantees are explicit.** Every state writes `orders.pipeline_stage` before any side effect. On agent restart, `SELECT pipeline_stage FROM orders WHERE id = ?` is the entire recovery story.

**LLM cost auditing is straightforward.** Anthropic SDK calls are wrapped in a helper that writes to `llm_calls`. n8n nodes wrapping the same calls are awkward to instrument equivalently.

**Two runtimes to operate.** Cost: one more container, one more set of logs, one more thing to monitor. Mitigated because both run on the same VPS and share Postgres.

**Clear separation of concerns.** "Agent decides what to do; n8n executes how to render." The boundary is the webhook. Reasoning bugs land in Python; rendering bugs land in n8n.

**Why we rejected option 1 (n8n-only):** Long-running waits in n8n (12-hour Gate 2 SLA) require either polling sub-workflows or external schedulers. Both are awkward. LangGraph's first-class waits via Realtime subscriptions are simpler.

## Reference

- [AGENT.md](../../AGENT.md): full state machine and node contracts.
- [0003](0003-opus-47-default-llm.md): LLM choice for the agent.
- [0008](0008-fork-vision-gridai.md): why n8n still owns the render core.
