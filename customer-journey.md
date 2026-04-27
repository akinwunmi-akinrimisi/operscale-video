# Customer Journey

> What the customer experiences from the moment they click an ad to the moment they receive their video files.

**Read alongside:** `gates-and-approvals.md`, `pricing-and-packages.md`, `AGENT.md`, `docs/specs/intake-form.md`, `docs/specs/auto-acknowledgement.md`.

---

## The journey at a glance

```
1. SEE AD (Meta or TikTok)
2. LAND ON SITE (plovera.shop)
3. PICK A TIER (Pilot / Standard / Creative Pod)
4. FILL OUT INTAKE FORM (15 questions, ~7 minutes, save-token resume)
5. RECEIVE INSTANT ACKNOWLEDGEMENT (email + WhatsApp, < 60 seconds)
6. WAIT FOR QUOTE (≤ 4 hours business time, includes 3 angles)
7. PAY VIA PAYSTACK LINK (in email + WhatsApp)
8. PHOTO UPLOAD if Creative Pod custom avatar — bonus step (24h grace)
9. WAIT FOR DELIVERY (Pilot 48h, Standard 36h, Creative Pod 72h, all from payment confirmed)
10. RECEIVE VIDEOS (signed download URL via email + WhatsApp)
11. POST-DELIVERY FOLLOW-UP (7 days later — feedback request)
```

---

## Stage 1 — SEE AD

Customer encounters our ad on Meta or TikTok. The hook is niche-specific (real-estate ad differs from fintech ad). The CTA is "Get a custom video for your business in 48 hours" with a button to `plovera.shop`.

The ad creative itself is one of the 90 videos from our content bank — we eat our own dog food.

## Stage 2 — LAND ON SITE

Customer lands on `plovera.shop`. The page communicates four things in 15 seconds:
- What we do (custom video ads for SMBs in 48h)
- Who it's for (their niche, recognised in the hero copy and imagery)
- How it works (3-step: brief → review → delivered)
- Pricing transparency (₦75K to ₦350K, no quote-by-email-only)

Above-the-fold has a "Start your video" CTA leading to `/start`.

For specific marketing-site requirements, see `docs/specs/marketing-site.md`.

## Stage 3 — PICK A TIER

Three pricing cards. Each shows: deliverables, turnaround, revisions, payment terms. The Creative Pod card has a small "+ avatar option" badge.

Customer clicks one. The selected tier becomes part of the URL (`/start?tier=standard`) and is locked in the form's first hidden field.

For canonical tier definitions, see `pricing-and-packages.md` and `tier-spec-v2.html`.

## Stage 4 — FILL OUT INTAKE FORM

A 15-question multi-step form. Five steps, 3 questions each. Estimated time: 7 minutes.

**The 15 questions** (canonical reference: `docs/specs/intake-form.md`):

1. Business name
2. Website or social handle
3. Niche (auto-locked if from `/start?niche=…` link, otherwise picker)
4. Product or service in one sentence
5. Ideal customer (one line)
6. What problem do you solve for them?
7. Your unique value proposition
8. What does your current marketing look like?
9. Monthly ad budget (NGN, optional but useful for our targeting)
10. Preferred tone (warm / authoritative / energetic / playful)
11. Must include in the video (offer details, phone number, etc.)
12. Must avoid (competitor names, regulated claims, etc.)
13. An example competitor or reference you admire
14. Call-to-action you want viewers to take
15. Niche-specific follow-up (varies — for real estate it asks about property type; for fintech it asks about regulatory certifications)

**Save-token resume:** every step transition saves to the `briefs` table. If the customer abandons mid-form, an email lands 30 minutes later: "Want to continue your video order? [resume link]". Tokens expire in 7 days.

## Stage 5 — RECEIVE INSTANT ACKNOWLEDGEMENT

Within 60 seconds of submit, the customer receives:

- **Email** (Resend): "We got your brief. Here's what happens next." Sets expectation: human review within 4 business hours, then quote with 3 angles.
- **WhatsApp** (Evolution API): Shorter version of the same message with a link to view the full email.

The instant ack is non-negotiable. It's the difference between "this site feels alive" and "did my form even submit?" — and the gap from intake to quote is up to 4 hours, which is too long for silence.

For exact copy, see `docs/specs/auto-acknowledgement.md`.

## Stage 6 — WAIT FOR QUOTE

Behind the scenes: Gate 0 (founder reviews brief in Notion, takes 5-10 min). On approval, agent generates 3 niche-tailored ad angles via Claude Opus 4.7. `WF_OPS_QUOTE_DELIVER` renders the rich quote message.

**SLA:** ≤ 4 hours during business hours (8am–8pm WAT). Outside business hours, ≤ first 4 business hours of the next day.

The quote message contains:
- Confirmation of tier and price
- 3 angle options with mini-pitch (90 words each)
- Estimated delivery date (calculated from current time + tier SLA)
- Paystack pay-now button
- "Reply with questions" affordance — customer can ask anything

## Stage 7 — PAY VIA PAYSTACK LINK

Customer clicks the Paystack pay-now link. Standard Paystack-hosted checkout (cards, bank transfer, USSD). Currency is NGN.

**Payment terms by tier:**
- Pilot (₦75K) — 100% upfront
- Standard (₦175K) — 100% upfront
- Creative Pod (₦350K) — 50/50 (₦175K now, ₦175K after Gate 2 script approval)

On successful payment, Paystack POSTs to our webhook. We verify the HMAC-SHA512 signature, write to `payments`, transition `orders.pipeline_stage = 'paid'`. The agent picks this up via Realtime and proceeds.

If payment fails, customer sees Paystack's error page. We don't auto-retry — they click the link again when ready.

If 72 hours pass with no payment, the order auto-archives (no money charged anyway). Customer receives a friendly "your quote expired but here's a fresh link" follow-up.

## Stage 8 — PHOTO UPLOAD (Creative Pod custom avatar only)

This stage exists ONLY for Creative Pod orders where the customer chose avatar-led production with their own face.

**The flow:**
1. After Gate 2 (script approval), agent transitions to `avatar_consent_check` state
2. Customer receives email + WhatsApp with a secure photo-upload link
3. Photo requirements clearly stated: front-facing, well-lit, sharp focus, no obstructions, single subject, no background distractions
4. Customer uploads + signs the consent text on the upload page
5. `order_consent` row is written with `consent_text_signed`, `signed_at`, `ip_address`
6. Auto-quality check runs (HeyGen pre-validation API or Claude Vision)
7. **Pass** → production_avatar starts
8. **Reject** → customer notified, given specific guidance ("photo too dark, please retake near a window"), can re-upload up to 3 times
9. **3 failed attempts** → escalation to founder; founder may approve override-with-warning, downgrade order to documentary tier with refund of avatar premium, or refund fully

**Grace period:** 24 hours from request to upload. After 24h, agent pings via WhatsApp. After 48h, founder pings personally. After 72h, order pauses with founder discretion to refund.

**Consent obligations:** the customer's checkbox text reads (for the canonical wording, see `security.md` §customer-photo-consent and Terms of Service `/legal/terms`):

> "I confirm I own the rights to this image and have permission from any person depicted, and I authorise plovera to render derivative video using this image for the purposes of fulfilling my order."

**Photo retention:** 90 days post-delivery. After 90 days, deleted from Supabase Storage. Customer is informed of this in the consent text.

For technical handling, see `security.md` §customer-photo-consent.

## Stage 9 — WAIT FOR DELIVERY

Behind the scenes:

- Pilot (48h SLA from payment): documentary path, ~5-8 scenes, single render
- Standard (36h SLA): documentary path, ~8-12 scenes, single render with end card + music
- Creative Pod (72h SLA): 3 videos, mixed documentary + optional avatar-led, mixed I2V

Founder reviews at Gate 1 (angle), Gate 2 (script), Gate 3 (final render). Each gate has its own SLA contribution to the total turnaround.

**Customer experience during this wait:** ONE proactive update at the midpoint. WhatsApp message: "Your videos are 60% done — final review tomorrow." We do not over-communicate; the customer trusts the SLA we promised in stage 6.

If we slip the SLA: at T-12h to deadline, founder is paged. Customer is notified at T-1h with apology + revised time + 10% credit toward next order. Slippages above 6h trigger a refund decision.

## Stage 10 — RECEIVE VIDEOS

Once Gate 3 is approved, `WF_OPS_DELIVERY_FANOUT` fires:

1. Generates 7-day signed Supabase Storage URL for each video
2. Sends Resend email containing:
   - Direct download link(s)
   - Receipt summary (paid amount, tier, date)
   - Deliverable summary (formats included for the tier)
   - Usage rights statement: "You own the videos, use them in any paid ads on any platform you wish"
   - Quick-tips footer for posting effectively
   - Reply-with-feedback affordance
3. Sends Evolution API WhatsApp message: shorter copy, same download link, "videos coming through email shortly if not already there"
4. Marks `orders.delivered_email_sent_at` and `delivered_whatsapp_sent_at`
5. Schedules the 7-day follow-up

**File specs by tier:**
- Pilot: 1 × 9:16 MP4 (1080×1920, 30fps, h264, AAC)
- Standard: 1 × 9:16 + 1 × 1:1 + 1 × 16:9 MP4 (each at 1080p, 30fps, h264, AAC)
- Creative Pod: 3 × 9:16 + 3 × 1:1 + 3 × 16:9 + 3 × 4K masters (3840×2160, 30fps, h265 ProRes for masters)

## Stage 11 — POST-DELIVERY FOLLOW-UP

Seven days after delivery, an email lands:

- "How are the videos performing?" (1 question, optional reply)
- A nudge toward the next tier or a retainer ("If these are working, consider Momentum retainer for monthly content")
- Direct ask for testimonial/case-study permission
- Reply-with-issues affordance

Response rate target: 30%. Conversion to retainer target: 15% of responders.

---

## Branch: customer requests revisions during a gate

If founder rejects at Gate 2 or Gate 3 with "regenerate" decision:
- Pilot has 1 free revision
- Standard has 2 free revisions  
- Creative Pod has 2 per video (6 total)

Beyond the included revisions, customer pays ₦25K/round.

When a revision is triggered: agent transitions back to `generating_script` (for Gate 2 regen) or `production_*` (for Gate 3 regen) with the founder's feedback as additional context. Customer is informed via email + WhatsApp: "Your video is being refined — fresh delivery in 24h."

## Branch: customer requests refund

Two refund paths:

**Pre-Gate 3 refund** (rare, but possible):
- Customer emails or WhatsApps asking to cancel
- Founder approves via Notion gate review with `decision = 'refund'`
- `WF_OPS_REFUND` fires, calls Paystack refund API
- Customer notified: "Refund processed, returned to original payment method, 5-10 business days"

**Post-delivery refund** (very rare):
- Customer is unhappy with delivered videos
- Founder responds personally; offers free additional revisions or refund
- If refund: same flow as above, plus video files become unavailable (signed URLs invalidated)

**Refund SLA:** initiated within 24 hours of approved decision. Paystack settlement typically 5-10 business days.

## Branch: order escalation

If anything in the journey trips a red flag (founder concern, customer dissatisfaction, technical failure, SLA breach), the agent transitions the order to a `paused` state and creates an "escalation" Notion card. Founder picks up, communicates with customer directly (founder-to-founder calls if needed), then unblocks via Notion approval or refund.

For the gate-level decision tree, see `gates-and-approvals.md`.
