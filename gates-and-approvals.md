# Gates and Approvals

> The four gates (plus one branch gate) where a human approves the order moving forward.
> Founder-only ops for the first 90 days.

**Read alongside:** `customer-journey.md`, `AGENT.md`, `docs/specs/notion-gate-review.md`.

---

## Why gates exist

A video ad agency cannot operate at acceptable quality without human review. AI-generated angles drift off-brand; AI-generated scripts hallucinate factual claims; AI-generated visuals occasionally produce uncanny output; AI-generated voice can mispronounce brand names. Each gate catches one class of error.

The gates also create a customer-experience benefit: the customer knows a human is between them and the AI. This is more durable trust than "AI does it all" claims, especially in our market where "AI ads" still carries a slight whiff of cheap-and-fast.

The cost is founder time. Five gate reviews per order × 5–10 orders/day at peak = 25–50 reviews/day. Each review takes 3–10 minutes. Total: 1.5–8 hours/day of founder review work. This is sustainable for ~90 days, after which we hire reviewer #2.

---

## The five gates

### Gate 0 — Brief sanity check
Founder reads the customer's intake form and decides: workable or not.

### Gate 1 — Angle approval
Founder reads the 3 generated ad angles and decides: which one (or regenerate).

### Gate 2 — Script approval
Founder reads the full script (every scene's narration, image prompt, CTA) and decides: approve, request edits, or reject.

### Gate 3-bis — Avatar quality check (BRANCH GATE)
**Creative Pod with custom avatar only.** Founder reviews customer-supplied photo and the auto-quality-check result. Decides: pass, reject, or override-with-warning.

### Gate 3 — Final render approval
Founder watches the rendered video(s) and decides: approve, regenerate, or refund.

---

## Gate 0 — Brief sanity check

**When it fires:** Immediately after intake form submission.

**SLA:** First business hours of the customer's submission day. (Submitted at 9am? Reviewed by 1pm. Submitted at 10pm? Reviewed by noon next day.)

**Founder reviews in Notion:**
- Customer's full brief (all 15 questions)
- Niche selection
- Tier selected
- Any red-flag content (restricted niche, regulated claim, abusive language, etc.)

**Decision tree:**

| Decision | What happens |
|---|---|
| Approved | Agent transitions to `generating_angles`. Customer waits for quote. |
| Rejected — out of scope | Customer receives a polite "we don't serve this niche" email with refund/no-charge confirmation. Examples: alcohol marketing in conservative-state customer, MLM/Ponzi scheme requests, cryptocurrency unregulated-yield claims. |
| Rejected — abusive | Customer receives a brief "we're declining this order" email. Logged for follow-up if pattern emerges. |
| Edit requested | Customer receives an email with specific gaps ("can you elaborate on Q7?"). Form resume link. |

**Notion card fields:**
- `customer_email`, `business_name`, `niche`, `tier`
- Brief content rendered as readable paragraphs
- Three decision buttons: Approve / Reject / Request Edit
- Optional comment field for founder notes

Restricted niches are documented in `niche-briefs/restricted.md`. If the brief touches a restricted niche, the agent auto-flags Gate 0 with a "restricted-niche detected" warning.

---

## Gate 1 — Angle approval

**When it fires:** After Gate 0 approval and successful angle generation.

**SLA:** Bundled with the quote-delivery time (≤ 4 business hours of Gate 0 approval).

**Note on bundling:** For Pilot tier, Gate 1 and Gate 2 are bundled into a single Notion card to reduce founder review load. For Standard and Creative Pod, they remain separate.

**Founder reviews in Notion:**
- The 3 generated angles, side by side
- Brief summary (collapsed by default, expandable)
- Niche brief context (which talking points the angles do/don't hit)

**Decision tree:**

| Decision | What happens |
|---|---|
| Approved (pick angle 1, 2, or 3) | Agent records the chosen angle in `videos.approved_angle`, transitions to `generating_script`. Customer doesn't see this gate explicitly — the chosen angle is what appears in the quote message. |
| Regenerate with feedback | Agent re-calls Claude Opus 4.7 with the founder's feedback as additional context. Costs ~$0.50 per regen. |
| Reject all three | Order pauses; founder writes the angles by hand, OR the order is escalated for a refund decision. |

**Bundle behaviour for Pilot:** the Notion card shows angles AND the script (once generated). Founder approves both at once, or sends back. This saves one founder cycle per Pilot order.

---

## Gate 2 — Script approval

**When it fires:** After angle approval (or angle pick at Gate 1 bundle).

**SLA:** ≤ 12 business hours from angle pick.

**Founder reviews in Notion:**
- The chosen angle (header)
- The full script:
  - Scene 1: narration text, image prompt, visual_type, color_mood, zoom_direction, caption_highlight_word, transition_to_next
  - Scene 2: ...
  - ...
- The CTA at the end
- Estimated total duration (sum of TTS estimates)
- Any factual claims flagged by an evaluator pass (e.g., "claims '40% return' — verify this is in customer's brief")

**Decision tree:**

| Decision | What happens |
|---|---|
| Approved | Agent transitions to `production_documentary` OR `avatar_consent_check` (if Creative Pod + avatar-led). |
| Edit and re-approve | Founder writes specific corrections in Notion. Agent re-calls Claude Opus 4.7 with corrections. Costs ~$0.75 per regen. |
| Reject — start over | Agent transitions back to `generating_angles` with feedback. Costs angle regen + script regen. |
| Pause for clarification | Founder messages customer directly to clarify a brief detail. Notion card stays open until resolved. |

**Per-tier revision counts** (revisions trigger via this gate's "edit" decision):
- Pilot: 1 free revision included
- Standard: 2 free revisions included
- Creative Pod: 2 per video (6 total) free revisions included

Beyond the included count, customer pays ₦25K/round for additional revisions. Founder warns customer before accepting that round.

---

## Gate 3-bis — Avatar quality check *(branch gate)*

**When it fires:** ONLY for Creative Pod orders where customer chose avatar-led production with their own face. After Gate 2 (script approval) and customer photo upload.

**SLA:** ≤ 4 hours from customer photo upload.

**Founder reviews in Notion:**
- Customer-supplied photo
- Auto-quality-check result (pass/concern flags)
- Consent checkbox confirmation
- IP address of consent
- Photo metadata (resolution, format)

**Auto-quality-check considerations:**
- Front-facing? (face detection)
- Sharpness adequate? (Laplacian variance threshold)
- Brightness adequate? (mean luminance window)
- Single subject? (no other faces detected)
- No obstructions? (sunglasses/mask flag)
- Consent text actually signed?

**Decision tree:**

| Decision | What happens |
|---|---|
| Pass | Agent transitions to `production_avatar`. HeyGen render proceeds. |
| Reject | Customer notified with specific guidance. Up to 3 re-uploads allowed. |
| Override-with-warning | Quality is borderline but founder accepts the risk. Agent transitions to `production_avatar`, with audit log entry that founder accepted lower quality. Customer NOT notified. |

**3-failed-uploads escalation:**
- Founder gets paged
- Options: founder approves anyway (override), downgrade to documentary tier (refund avatar premium), or full refund

**Why this gate is NOT in the auto-pipeline:** the legal exposure of using a customer's likeness without proper consent is real. Even with a checkbox, founder review is the second gate that catches "this isn't actually the customer — this is their CEO without permission" or similar issues.

---

## Gate 3 — Final render approval

**When it fires:** After all production stages complete and final captioned MP4 lands in Supabase Storage.

**SLA:** ≤ 6 hours from render completion.

**Founder reviews in Notion:**
- Embedded video player (for each video in the order — 1 for Pilot/Standard, 3 for Creative Pod)
- Side-by-side comparison: approved script vs delivered render (does narration match?)
- Auto-flagged issues:
  - Audio levels (clipping, too quiet)
  - Caption sync (Whisper alignment confidence score)
  - Scene transition smoothness (visual_type changes detected)
  - Brand-claim accuracy (cross-reference with brief's "must-include")
  - Profanity/restricted-content scan (caption text + script text)

**Decision tree:**

| Decision | What happens |
|---|---|
| Approved | Agent transitions to `deliver`. `WF_OPS_DELIVERY_FANOUT` fires. Customer receives signed URLs. |
| Regenerate scene N | Agent regenerates only the flagged scene(s), then re-runs caption assembly + caption burn. Costs marginal. |
| Regenerate from script | Agent transitions back to `generating_script` with feedback. Full re-render. Costs ~$5-25 depending on tier. |
| Refund | Agent transitions to refund branch. `WF_OPS_REFUND` fires. Customer receives refund notification. |

**Multi-character review (Creative Pod multi-speaker):** for orders with 2 speakers, founder reviews each speaker segment for:
- Speaker assignment correct (A's lines voiced by A's voice)
- Camera cuts at speaker turns
- No overlap between speakers
- Both speaker voices distinguishable (cap is hard at 2 — see ADR 0012)

**Custom-avatar review (Creative Pod custom avatar):** founder additionally reviews:
- Avatar facial accuracy (does it look like the customer?)
- No uncanny-valley artefacts
- Lip sync acceptable
- Backgrounds match brand style

---

## Gate decision audit log

Every gate decision writes a row to `gate_decisions`:

```sql
INSERT INTO gate_decisions (
  order_id, video_id, gate_number, decision, feedback,
  decided_by, decided_at
) VALUES (
  $1, $2, 0|1|2|3, 'approved'|'rejected'|'edit_requested'|'refund',
  $3,  -- founder's notes
  $4,  -- approver email
  NOW()
);
```

This table is queryable for analytics: average review time per gate, regen rate by tier, rejection causes by niche. Useful for prompt iteration and tier improvement.

---

## Notion DB structure

The Notion gate-review database has one row per pending gate. Schema (see `docs/specs/notion-gate-review.md` for full detail):

| Column | Type | Notes |
|---|---|---|
| Title | Text | Auto-generated: "Gate N — Order {id} — {customer_name}" |
| Order ID | Text | Stable identifier |
| Gate Number | Select | 0 / 1 / 2 / 3 / 3-bis |
| Tier | Select | Pilot / Standard / Creative Pod |
| Niche | Select | One of 5 |
| Customer Email | Email | |
| Customer WhatsApp | Phone | |
| Status | Select | Pending / Approved / Rejected / Edit Requested / Refunded |
| Decision | Select | Same as status, but locked-in once chosen |
| Feedback | Text | Founder's notes |
| Artefacts | Files | Brief PDF, angle JSONs, script JSON, render MP4 |
| Embedded Player | Files | For Gate 3 only — playable video |
| Created | Date | |
| Decided | Date | Auto-set when Decision changes |
| SLA Deadline | Formula | Computed from Created + tier rules |
| Time to Decision | Formula | Decided - Created |

Notion automation: when `Decision` field changes from "Pending" to anything else, the automation engine POSTs the row contents to `WF_OPS_GATE_RESUME` webhook. Webhook updates `gate_decisions` table and the agent picks up via Realtime.

---

## SLA monitoring

Each gate has an SLA. Aggregate breach detection:

- **Per-order:** if any gate sits in pending state longer than its SLA, founder gets a WhatsApp ping.
- **Daily aggregate:** at 8pm WAT, summary message: "X gates pending, Y approved today, Z rejected, longest pending: Gate N for Order {id} ({hours}h overdue)."

If founder is travelling/unavailable, the system does NOT auto-approve. Orders pile up. Customer experience degrades. The on-call substitute (eventually a hired reviewer) is the answer; for the first 90 days, the founder answers their own phone.

---

## What happens when a gate is wrong

Gates are human, humans make mistakes. The 3 rare but real failure modes:

1. **Approved a bad script that produces a bad render.** Caught at Gate 3. Regenerate from script, customer absorbs the time cost; we absorb the regeneration $ cost.

2. **Approved a render that customer hates.** Customer requests revision via email. Founder accepts (within tier revision count) and re-fires Gate 3 cycle. If customer hate is truly unjustified (rare), founder explains the constraints and offers credit toward next order.

3. **Approved a render that contains an unintended factual error or rights issue.** Discovered post-delivery. Apology email, full refund regardless of tier, full removal of customer's photo if avatar-led.

The post-mortem for any of these failures lands in `docs/incidents/YYYY-MM-DD-<short>.md`. We update the auto-flagged-issues list in Gate 3 to catch the same class next time.
