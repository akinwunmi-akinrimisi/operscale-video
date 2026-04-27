# 0016. Skip VG's React dashboard; use Notion-based gate review for v1

Date: 2026-04-26
Status: Accepted

## Context

Vision GridAI has a 4-page React dashboard at `/opt/dashboard/` on the VPS. It's used by Akinwunmi to monitor VG's video production pipeline. It would be straightforward to fork it: clone the React app, adapt to our schema, deploy at `dashboard.<brand-name>.com`.

The dashboard handles:
- Project / topic / scene status views
- Real-time pipeline stage updates via Supabase Realtime
- Approval gates (Gate 1 angle, Gate 2 script, Gate 3 video, Gate 4 shorts)
- Cost monitoring per project

Three options for our gate-review surface:

1. **Fork VG's dashboard.** Adapt to our schema, deploy at `dashboard.<brand-name>.com`. Maintenance burden: one more app to keep working.
2. **Build a custom founder console.** Native React, custom-fit to our needs (4 gates, 5 niches, our SLA semantics). Build cost: 1-2 weeks.
3. **Use Notion as the gate-review UI.** Notion DB with one row per pending gate. Notion automation POSTs decisions back to our webhook. Build cost: ~1 day.

Founder-only ops for the first 90 days. The founder reviews gates from phone (between meetings, during commutes, late at night).

## Decision

**Notion-based gate review for v1.** Defer custom-built founder console until at least Day 90.

Concretely:
- Notion DB with the schema in `docs/specs/notion-gate-review.md`
- `WF_OPS_GATE_NOTIFY` (n8n) creates rows
- Notion automation POSTs decisions to `WF_OPS_GATE_RESUME` webhook
- Webhook updates our `gate_decisions` table; agent picks up via Realtime

## Consequences

**Mobile-first by default.** Notion mobile app is usable; founder can approve gates from anywhere.

**Zero build cost.** Day 22-23 of implementation plan covers Notion setup. No app to maintain.

**Audit trail built in.** Notion preserves row history per change. We don't need to build versioning.

**Collaboration ready.** When we hire reviewer #2, sharing a Notion DB takes 30 seconds.

**Limitations:**
- Cannot do live video preview within Notion (we link out to the signed Supabase URL — adds 1 click for Gate 3 review)
- Notion API rate limits (~3/s per integration) are fine at our scale but a concern if we 10× orders
- Notion's automation engine has occasional latency (~30s) — acceptable for asynchronous gates, would be a problem for real-time UI

**Defer custom dashboard:** revisit at Day 90 retro if any of:
- Founder review time on Notion exceeds 30 min/day sustained
- Multiple reviewers need different views (founder vs. junior reviewer)
- Notion automation latency or reliability becomes a customer-experience issue
- We need analytics across many orders that Notion doesn't surface well

**Why we rejected option 1 (fork VG dashboard):** the dashboard's data model assumes long-form 2-hour topics with 172 scenes — the UX optimisations (chapter views, scene-by-scene Realtime updates, cost-calc preview) are all wrong for our 5-12 scene ad format. Forking would require ~50% rewrite for a tool we use 25-50 times/day.

**Why we rejected option 2 (custom build):** 1-2 weeks of build time at the most foundation-critical period of the launch. Notion gives us the same product outcome for that period for one day of setup.

## Reference

`docs/specs/notion-gate-review.md` — implementation details.
`gates-and-approvals.md` — gate semantics.
