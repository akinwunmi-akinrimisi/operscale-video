# Notion Gate Review Spec

> The implementation contract for the Notion-based gate review system.

**Read alongside:** `gates-and-approvals.md`, ADR 0016, `AGENT.md`.

---

## What this spec covers

The schema of the Notion gate-review database, the automation that POSTs decisions back to our webhook, and the operational details (founder UX, reviewer workflow).

---

## Notion workspace

For the first 90 days, we use Akinwunmi's personal Notion workspace. Founder is the only reviewer.

When we hire reviewer #2 (Day 90+), share the Gate Review database with them as Editor. Notion's permission model handles this transparently.

## Database schema

Database name: **"Gate Reviews"**

| Column | Type | Notes |
|---|---|---|
| Title | Title (auto) | Auto-generated: `"Gate {N} — Order {short_id} — {customer_name}"` |
| Order ID | Text | Stable identifier |
| Gate Number | Select | Options: `0`, `1`, `2`, `3-bis`, `3` |
| Tier | Select | `Pilot`, `Standard`, `Creative Pod` |
| Niche | Select | `Real Estate`, `Education`, `Fashion`, `Fintech`, `Health` |
| Customer Email | Email | |
| Customer WhatsApp | Phone | |
| Status | Select | `Pending`, `In Review`, `Approved`, `Rejected`, `Edit Requested`, `Refunded` |
| Decision | Select | `pending` (default), `approved`, `rejected`, `edit_requested`, `regenerate`, `refund` |
| Feedback | Text | Founder's notes (free-form) |
| Brief Summary | Text | Pre-computed at card creation |
| Angles JSON | Text | For Gate 1 — the 3 generated angles in human-readable format |
| Script JSON | Text | For Gate 2 — the full script |
| Render URLs | Files & media | For Gate 3 — embedded video player |
| Photo | Files & media | For Gate 3-bis — customer photo |
| Auto-Quality-Check Result | Text | For Gate 3-bis — pass/fail flags from auto-check |
| Created | Created time (auto) | |
| Last Edited | Last edited time (auto) | |
| SLA Deadline | Formula | Computed: Created + tier-rule SLA hours |
| Time to Decision | Formula | If(Decision != 'pending', LastEdited - Created, "—") |

### Brief Summary template

For Gate 0, the Brief Summary field contains a markdown-formatted dump of all 15 form questions:

```
**Customer:** {business_name}
**Niche:** {niche}
**Tier:** {tier} — ₦{amount_ngn}

**Q1-Q15:**
1. Business name: {business_name}
2. Website: {website_url}
3. Niche: {niche}
4. Product/service: {product_or_service}
... (all 15 questions, formatted)

**Internal red flags:** {auto_detected_flags}
```

### Angles JSON template

For Gate 1, three sub-headers per angle:

```
**Angle 1: {hook_headline}**
{90-word pitch}

**Angle 2: {hook_headline}**
{90-word pitch}

**Angle 3: {hook_headline}**
{90-word pitch}
```

### Script JSON template

For Gate 2, scene-by-scene breakdown:

```
**Approved Angle:** {angle_pitch_summary}
**Estimated Duration:** {duration_seconds}s

**Scene 1:** ({color_mood}, {zoom_direction})
Narration: "{narration_text}"
Image prompt: {image_prompt}
Caption highlight word: {caption_highlight_word}

**Scene 2:** ...
...

**CTA:** {cta_text}

**Auto-flagged for review:** {evaluator_concerns}
```

## Card creation flow

Triggered by agent when entering a `gate_*_review` state. The flow:

```
Agent state: brief_received → gate_0_review
  ↓
WF_OPS_GATE_NOTIFY (n8n)
  1. Fetch order + customer + brief from Supabase
  2. Compute brief summary (formatted)
  3. POST to Notion API:
     POST https://api.notion.com/v1/pages
     Headers: 
       Authorization: Bearer ={{ $env.NOTION_API_KEY }}
       Content-Type: application/json
       Notion-Version: "2022-06-28"
     Body: {
       parent: { database_id: NOTION_GATE_DB_ID },
       properties: {
         "Title": { title: [{ text: { content: title } }] },
         "Order ID": { rich_text: [{ text: { content: order.id } }] },
         "Gate Number": { select: { name: "0" } },
         "Tier": { select: { name: tier_label } },
         "Niche": { select: { name: niche_label } },
         "Customer Email": { email: customer.email },
         "Customer WhatsApp": { phone_number: customer.whatsapp_phone },
         "Status": { select: { name: "Pending" } },
         "Decision": { select: { name: "pending" } },
         "Brief Summary": { rich_text: [{ text: { content: brief_summary } }] }
       }
     }
  4. INSERT INTO production_log (...) for audit
```

## Notion automation → webhook flow

In Notion, configure an automation on the Gate Reviews database:

**Trigger:** When `Decision` field changes from `pending` to anything else

**Action:** Send webhook with the entire row's fields

**Webhook URL:** `https://n8n.srv1297445.hstgr.cloud/webhook/operscale/gate/resume`

**Payload:**
```json
{
  "page_id": "<notion-page-id>",
  "order_id": "<from Order ID column>",
  "gate_number": "<from Gate Number column>",
  "decision": "<from Decision column>",
  "feedback": "<from Feedback column>",
  "decided_by": "akinwunmi@operscale.ng"
}
```

## Webhook handler

```javascript
// WF_OPS_GATE_RESUME
1. Verify webhook is from Notion (HTTP_WEBHOOK_SHARED_SECRET header check)
2. INSERT INTO gate_decisions (
     order_id, video_id, gate_number, decision, feedback, decided_by, decided_at
   ) VALUES ($1, $2, $3, $4, $5, $6, NOW())
3. Update Notion card: 
   PATCH https://api.notion.com/v1/pages/{page_id}
   Body: { properties: { "Status": { select: { name: "Approved" }} } }  
   (or Rejected, Edit Requested, etc., based on decision)
4. INSERT INTO production_log (...)
```

The agent's Realtime subscription on `gate_decisions` table picks up the row insert and transitions the order's pipeline_stage accordingly.

## SLA monitoring

A cron in n8n (every 30 min) scans for SLA breach:

```sql
SELECT 
  o.id AS order_id,
  o.tier,
  o.pipeline_stage AS current_stage,
  EXTRACT(EPOCH FROM (NOW() - o.updated_at)) / 3600 AS hours_pending
FROM orders o
WHERE o.pipeline_stage IN ('gate_0_review', 'gate_1_review', 'gate_2_review', 'gate_3_review', 'avatar_quality_check')
  AND o.updated_at < NOW() - INTERVAL '4 hours' -- minimum SLA boundary
ORDER BY hours_pending DESC;
```

Threshold logic:
- Pending > 4h: WhatsApp ping to founder
- Pending > 8h: urgent WhatsApp to founder + email
- Pending > 24h: escalation alert (something is genuinely wrong)

## Founder UX

What founder sees on Notion mobile:

1. **Dashboard view** — Notion view filtered to `Status = Pending`, sorted by Created ascending
2. **Tap card** — see full Brief Summary / Angles / Script / Render
3. **Decision dropdown** — tap, choose option, save
4. **Optional Feedback field** — type notes in mobile keyboard

That's it. No app to install, no dashboard to log into. Just Notion.

For Gate 3 (final render): the embedded video plays directly in Notion mobile. Founder can play, scrub, watch fully, decide.

## Adding a Decision option

Founder can extend the Decision options as needed (e.g., adding `pause_for_clarification`). This is just a Notion select-field change. The webhook handler in `WF_OPS_GATE_RESUME` must be updated to handle new options.

## Operational notes

**Notion outage handling:** if Notion is down (rare), founder cannot review gates. Pipeline stalls. Workaround: founder POSTs decisions directly via curl from a phone shortcut to `/webhook/operscale/gate/resume/manual` — bypasses Notion entirely. Documented in `runbooks/notion-outage.md` (TBD).

**Privacy:** customer Brief Summary contains PII (email, business name, possibly more). Notion workspace is private; only founder has access. Do not duplicate to public workspaces.

**Cost:** Notion Free tier supports 1 user with no limits at our query volume. When team grows, upgrade to Plus ($8/mo) or Business ($15/mo per seat).

## Migration path to custom dashboard (post-Day 90)

When we replace Notion with a custom-built founder console:

1. Build the new dashboard at `dashboard.plovera.shop`
2. The dashboard reads from the same `gate_decisions` table
3. The dashboard writes back to `gate_decisions` directly (no Notion intermediary)
4. We deprecate the Notion automation by editing it to do nothing
5. Existing Notion cards become read-only audit trail; new cards stop being created

The schema doesn't change. The webhook handler doesn't change. Only the UI surface changes. Migration time: ~1 week with minimal risk.
