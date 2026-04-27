# AGENT.md

> The LangGraph orchestration agent for Operscale Video Ads.
> This file specifies the state machine, the nodes, the transitions, and the contract with the rest of the system.

**Read alongside:** `docs/VISION_GRIDAI_FORK_MANUAL.md` §11–§12, `gates-and-approvals.md`, `customer-journey.md`.

---

## What the agent does

The agent is a long-running Python 3.11 process (LangGraph) that orchestrates the entire order lifecycle from intake through delivery. It does not render videos itself — rendering is delegated to Vision GridAI's forked n8n workflows. The agent's job is the layer above: deciding when to call which workflow, holding state during waits, polling Supabase Realtime for human gate decisions, and resuming exactly where it left off if it crashes.

It runs in the `operscale-agent` Docker container (per `deployment.md`). It listens for new orders, listens for gate-decision row inserts via Supabase Realtime, and exposes a tiny HTTP API for n8n to call back into.

---

## The single mental model

> Customer fills out brief. Founder approves. Customer pays. Agent generates angles + script. Founder approves angles + script. Render core produces video. Founder approves render. Agent triggers delivery.

Three things to internalise:
1. **The agent never renders.** Rendering is n8n's job. The agent calls n8n webhook endpoints and waits for completion signals via Supabase Realtime updates on `videos.assembly_status`, etc.
2. **The agent never talks to the customer directly.** Customer comms go through `WF_OPS_QUOTE_DELIVER`, `WF_OPS_DELIVERY_FANOUT`, etc. — n8n owns transactional email + WhatsApp.
3. **Every gate is a wait.** Gates 0/1/2/3 are human-in-the-loop. The agent issues a Notion card, then suspends the state until a `gate_decisions` row appears in Supabase. No polling loops, no busy-waits — Realtime subscription only.

---

## State machine

The full state diagram is `docs/diagrams/order-lifecycle.mmd`. Summary:

```
brief_received
  → gate_0_review                         (Notion: brief sanity check)
       ├── approved      → generating_angles
       ├── rejected      → terminal (no money charged)
       └── edit          → wait for resubmit, then back to gate_0
generating_angles                          (Claude Opus 4.7 call)
  → quote_delivery                        (WF_OPS_QUOTE_DELIVER)
  → awaiting_payment                      (Paystack link sent)
       ├── paid          → generating_script
       ├── timeout (72h) → archived (auto-expire)
       └── declined      → terminal
generating_script                          (Claude Opus 4.7 call)
  → gate_1_review                         (Notion: angle approval)
       ├── approved      → continue with chosen angle
       └── regenerate    → back to generating_angles with feedback
  → gate_2_review                         (Notion: full script approval)
       ├── approved      → branch on tier:
       │                   - documentary  → production_documentary
       │                   - avatar_led   → avatar_consent_check
       └── regenerate    → back to generating_script with feedback
avatar_consent_check                       (Creative Pod + avatar-led only)
  → consent_pending                       (await customer photo upload + consent)
  → avatar_quality_check                  (auto-validate photo)
       ├── pass          → production_avatar
       ├── reject        → notify customer, request new photo
       └── override      → production_avatar (with documented warning)
production_documentary                     (n8n WF_TTS_AUDIO → ... → caption burn)
production_avatar                          (HeyGen render path, Creative Pod)
  → render_complete
  → gate_3_review                         (Notion: final render approval)
       ├── approved      → deliver
       ├── regenerate    → back to production with feedback
       └── refund        → trigger WF_OPS_REFUND
deliver                                    (WF_OPS_DELIVERY_FANOUT)
  → post_delivery_followup_scheduled      (7 days later)
  → terminal (delivered)
```

Each state corresponds to a value in `orders.pipeline_stage` (see `migrations/001_initial.sql` CHECK constraint). State persists in Postgres; the agent process can crash and restart and pick up exactly where it stopped.

---

## State definitions — what each state computes

### `brief_received`

**Trigger:** Insert into `briefs` table (via Next.js API route from intake form submit).

**Reads:** `briefs` row, `customers` row.

**Writes:** New row in `orders` with `pipeline_stage = 'brief_received'`. New row in `production_log`.

**Calls:** `WF_OPS_INTAKE_RECEIVE` (which fires the auto-acknowledgement email + WhatsApp).

**Transitions to:** `gate_0_review`.

### `gate_0_review`

**Purpose:** Founder sanity check. Is this brief workable? Is it in a niche we serve? Is it not in `niche-briefs/restricted.md`?

**Calls:** `WF_OPS_GATE_NOTIFY` to push a card to the Notion gate-review DB.

**Waits on:** `gate_decisions` row insert with `gate_number = 0`.

**Transitions to:**
- `decision = 'approved'` → `generating_angles`
- `decision = 'rejected'` → terminal
- `decision = 'edit_requested'` → suspend until brief resubmitted, then back to `gate_0_review`

### `generating_angles`

**Purpose:** Generate 3 niche-tailored ad angles for the customer to choose from.

**Reads:** `briefs` (full Q1-Q15), `prompt_configs` WHERE `niche = brief.niche AND prompt_type = 'angle_generator'`, `niche-briefs/<niche>.md` (loaded at agent startup).

**Calls:** Claude Opus 4.7 with the angle generator prompt + brief + niche brief context. ~1,500 input tokens, ~2,000 output tokens. Cost: ~$0.50 per call.

**Writes:** 3 `videos` rows (or 1 row with 3 candidate angles in JSON for Pilot/Standard; see schema). `llm_calls` audit row.

**Transitions to:** `quote_delivery`.

### `quote_delivery`

**Purpose:** Render and send the rich quote message with all 15 components.

**Calls:** `WF_OPS_QUOTE_DELIVER` (n8n) — handles email via Resend, WhatsApp via Evolution API.

**Transitions to:** `awaiting_payment`.

### `awaiting_payment`

**Purpose:** Wait up to 72 hours for the customer to pay via the Paystack link.

**Waits on:** `payments.status = 'paid'` row insert (signature-verified by `WF_OPS_PAYSTACK_WEBHOOK`).

**Transitions to:**
- Paid → `generating_script`
- 72h timeout → terminal (archived, no refund issue since no payment received)
- Customer declines → terminal

### `generating_script`

**Purpose:** Take the chosen angle and write the full ad script (5–12 scenes depending on tier).

**Reads:** Approved angle from `videos.approved_angle`, brief, niche brief, register config from `production_registers`.

**Calls:** Claude Opus 4.7. ~2,000 input tokens, ~3,000 output tokens. Cost: ~$0.75 per call.

**Writes:** `videos.script_json`, individual `scenes` rows with `narration_text`, `image_prompt`, `visual_type`, `composition_prefix`, `color_mood`, `zoom_direction`, `transition_to_next`, `caption_highlight_word`. `llm_calls` audit row.

**Transitions to:** `gate_1_review`.

### `gate_1_review`

**Purpose:** Founder confirms the angle choice and lightweight strategic direction.

(Note: We bundle Gate 1 and Gate 2 into one Notion review for Pilot tier to reduce founder load. Standard and Creative Pod keep both gates separate.)

**Transitions to:** `gate_2_review` for full script review.

### `gate_2_review`

**Purpose:** Founder reads every scene, every narration line, every image prompt. Approves, requests edits, or rejects.

**Calls:** `WF_OPS_GATE_NOTIFY` with full script payload.

**Waits on:** `gate_decisions` row with `gate_number = 2`.

**Transitions to:**
- Approved → branch on `orders.production_register`:
  - `documentary` → `production_documentary`
  - `avatar_led` → `avatar_consent_check` (Creative Pod only)
- Regenerate with feedback → `generating_script`

### `avatar_consent_check` *(Creative Pod + avatar-led only)*

**Purpose:** If the customer chose avatar-led production with their own face, we need a clear photo + signed consent.

**Calls:** Email + WhatsApp to customer requesting photo upload via secure link.

**Waits on:** `order_consent` row insert with `quality_check_status` set.

**Transitions to:** `avatar_quality_check`.

### `avatar_quality_check`

**Purpose:** Auto-validate the customer's photo (front-facing, well-lit, sharp focus, no obstructions).

**Calls:** HeyGen avatar pre-validation API (or our own simple check via Claude Vision).

**Writes:** `order_consent.quality_check_status` ∈ `{passed, rejected, overridden_with_warning}`.

**Transitions to:**
- Pass → `production_avatar`
- Reject → notify customer, request new photo, back to `avatar_consent_check`
- Override (founder approval despite low quality) → `production_avatar` with audit log entry

### `production_documentary`

**Purpose:** Trigger the inherited Vision GridAI render pipeline.

**Calls:** POST to `WF_OPS_PRODUCTION_TRIGGER` (which fires `WF_SCENE_CLASSIFY` → `WF_TTS_AUDIO` → `WF_IMAGE_GENERATION` → optional `WF_SEEDANCE_I2V` → `WF_KEN_BURNS` → `WF_CAPTIONS_ASSEMBLY` → caption burn service on `:9998`).

**Waits on:** `videos.assembly_status = 'complete'` AND `videos.caption_burn_status = 'complete'` for all videos in the order. Realtime subscription on `videos` table.

**Transitions to:** `gate_3_review`.

### `production_avatar`

**Purpose:** HeyGen-driven render path. Multi-character dialogue and/or custom avatar.

**Calls:** POST to `WF_HEYGEN_RENDER` (new workflow, see fork manual §6.4) which orchestrates per-segment HeyGen API calls for each speaker turn, then assembles via FFmpeg.

**Notes:**
- For multi-character dialogue: script must use turn-taking format with explicit `A:` / `B:` speaker tags. Camera cuts between speakers; never two mouths talking in the same frame.
- For 2 speakers max. Three or more speakers requires custom-quote and bypasses normal flow.
- Per-segment HeyGen render: ~3 min per segment. Parallelised across speakers where possible.
- Voice: customer can choose stock Chirp 3 HD voice OR upload 60s sample for fal.ai PlayHT v3 cloning.

**Waits on:** Same as `production_documentary` — `videos.assembly_status = 'complete'`.

**Transitions to:** `gate_3_review`.

### `gate_3_review`

**Purpose:** Founder watches the final render. Last sanity check before customer sees it.

**Calls:** `WF_OPS_GATE_NOTIFY` with the rendered video URL.

**Waits on:** `gate_decisions` row with `gate_number = 3`.

**Transitions to:**
- Approved → `deliver`
- Regenerate → back to `generating_script` with feedback
- Refund → `WF_OPS_REFUND` (Paystack refund API call), terminal

### `deliver`

**Purpose:** Send the customer their videos.

**Calls:** `WF_OPS_DELIVERY_FANOUT` which:
1. Generates a 7-day signed URL from Supabase Storage.
2. Sends Resend email with download link + receipt.
3. Sends Evolution API WhatsApp message with shorter copy + URL.
4. Marks `orders.delivered_email_sent_at` and `delivered_whatsapp_sent_at`.
5. Schedules a 7-day post-delivery follow-up email.

**Transitions to:** `post_delivery_followup_scheduled` (a logical state — agent is now done with this order, just a cron will fire the follow-up email).

---

## Tools the agent uses

The agent calls external services via these channels:

| Tool | Purpose | Called from state |
|---|---|---|
| Anthropic Claude Opus 4.7 | Angle generation, script generation, evaluator | `generating_angles`, `generating_script`, gate review summaries |
| Supabase REST (PostgREST) | Read/write all DB tables | All states |
| Supabase Realtime (WSS) | Listen for `gate_decisions` and `videos` updates | Gate review states + production states |
| n8n webhook endpoints | Trigger render workflows | `quote_delivery`, `production_*`, `deliver` |
| Notion API (via n8n) | Push gate-review cards | `gate_*_review` states |
| Paystack API (via n8n) | Verify payment, issue refund | `awaiting_payment`, refund branch |
| HeyGen API (via n8n) | Avatar generation + per-segment render | `avatar_*` states, `production_avatar` |
| fal.ai PlayHT v3 (via n8n) | Voice cloning | optional in `production_avatar` |

The agent does NOT call FFmpeg, Google Cloud TTS, Fal.ai Seedream/Seedance, or Vertex AI Lyria directly. Those are all reached via n8n workflows that the agent triggers.

---

## Resume guarantees

The agent process can be killed at any moment and the system stays consistent because:

1. **Every transition writes `orders.pipeline_stage` before any side effect.** If the agent crashes after writing the new stage but before the next side effect, restart picks up at that stage and idempotently re-fires the side effect.
2. **All n8n workflows are idempotent.** They check per-scene status columns (`audio_status`, `image_status`, etc.) and skip already-completed scenes. Re-firing a workflow for an order in mid-flight does not double-charge or double-render.
3. **Gate decision listeners are stateless.** On agent restart, the agent queries `gate_decisions` for any rows newer than the order's `last_processed_decision_at` and processes them in order.
4. **Paystack webhooks are idempotent.** `payments.paystack_tx_ref` has a UNIQUE constraint; duplicate webhook deliveries from Paystack are no-ops.

See `docs/VISION_GRIDAI_FORK_MANUAL.md` §9 for the resume/retry mechanics inherited from Vision GridAI's render core.

---

## Cost budgeting

The agent should refuse to start a new render if `orders.total_cost_usd_estimate` exceeds 15% of `orders.amount_paid_kobo / 100 / 1650` (rough NGN-to-USD margin guard).

Per-order COGS targets:
- Pilot: < $3 (Claude $2 + TTS $0.10 + images $0.24 + render $0)
- Standard: < $6 (Claude $4 + TTS $0.10 + images $0.36 + i2v ~$0.50 + music $0.02)
- Creative Pod: < $25 worst case (3 videos × Standard cost + optional HeyGen $0–15 + optional voice cloning $0–2)

`llm_calls` table tracks every Anthropic call with cost. `production_log` tracks every external service call. Cost reconciliation per order: `SELECT order_id, SUM(cost_usd) FROM llm_calls WHERE order_id = ? GROUP BY order_id`.

---

## Failure modes the agent handles

| Failure | Agent response |
|---|---|
| Anthropic returns rate-limit (429) | `WF_RETRY_WRAPPER` handles inside n8n; agent only sees retries via increased latency |
| Anthropic returns error after retries exhausted | Mark order `pipeline_stage = 'failed'`, `last_error = ...`. Notify founder via Notion. |
| Customer photo fails quality check | Notify customer, transition back to `avatar_consent_check`. After 3 failed photos, escalate to founder. |
| Render takes longer than tier SLA (Pilot 48h, Standard 36h, Creative Pod 72h) | At T-12h before SLA breach, push WhatsApp to founder. At T-2h, push urgent. |
| Customer refund request before delivery | Transition to refund branch, fire `WF_OPS_REFUND`. |
| HeyGen API outage | Fail open: pause `production_avatar` orders, founder is notified, customer gets proactive update with refund-or-wait choice. |
| `caption_burn_service.py` host service down | `videos.caption_burn_status = 'failed'`. Founder runs `systemctl restart caption-burn.service`, then re-fires `WF_CAPTIONS_ASSEMBLY` for the affected video. |

---

## What the agent does NOT do

- Customer support beyond automated transactional messages (founder handles via WhatsApp).
- Pricing decisions (locked per tier).
- Refund decisions (founder approves via Notion gate, agent only executes).
- Quality judgment on creative output (founder owns Gate 2 and Gate 3).
- Marketing-site content generation (separate concern).
- Analytics or post-publish tracking (out of scope; we deliver to the customer who then posts themselves).
