# Pricing and Packages

> The canonical reference for all tier definitions, pricing, deliverables, and payment terms.

**Read alongside:** `customer-journey.md`, `tier-spec-v2.html`, `launch-budget.html`.

---

## The tier matrix

| Feature | Pilot | Standard | Creative Pod |
|---|---|---|---|
| **Price (NGN)** | ₦75,000 | ₦175,000 | ₦350,000 |
| **Price (~USD)** | ~$50 | ~$115 | ~$230 |
| **Videos per order** | 1 | 1 | 3 |
| **Length per video** | 15-30 seconds | 15-45 seconds | 15-60 seconds |
| **Production styles** | Documentary | Documentary | Documentary OR Avatar-led |
| **TTS voice** | Google Cloud Chirp 3 HD | Google Cloud Chirp 3 HD | Google Cloud Chirp 3 HD |
| **Voice cloning option** | — | — | Optional (fal.ai PlayHT v3) |
| **Multi-character dialogue** | — | — | Up to 2 speakers (cap at 2 per ADR 0012) |
| **Custom avatar from photo** | — | — | Optional (HeyGen) |
| **Visual mix** | All static images + Ken Burns | Mostly static + ~20% I2V motion | Mixed: static + I2V; if avatar-led, HeyGen-rendered |
| **Music** | Royalty-free curated | Artlist licensed | Artlist + scene-specific selection |
| **Captions** | White kinetic with red emphasis | Niche-styled with emphasis colour | Custom typography per video |
| **Output formats** | 9:16 only (1080×1920) | 9:16 + 1:1 + 16:9 (all 1080p) | All formats + 4K master |
| **End card** | — | Branded end card | Branded end card per video |
| **Revisions included** | 1 round | 2 rounds | 2 per video (6 total) |
| **Additional revision cost** | ₦25,000/round | ₦25,000/round | ₦25,000/round |
| **Turnaround SLA** | 48 hours | 36 hours | 72 hours |
| **Payment terms** | 100% upfront | 100% upfront | 50% upfront, 50% at Gate 2 approval |
| **Currency** | NGN (Paystack) | NGN (Paystack) | NGN (Paystack) |
| **Best for** | First-time test, low-budget SMBs | Active marketers running ads | Agencies, complex campaigns, retainer pre-cursors |

---

## Tier deep-dive

### Pilot — ₦75,000

**The "let's see if this works" tier.** Built for an SMB owner who has never paid for a video ad before. Low ticket, fast turnaround, low risk.

**Workflow:**
1. Customer fills brief (7 minutes)
2. Quote with 3 angles delivered (≤ 4 hours)
3. Customer pays ₦75K via Paystack
4. Gate 1 + Gate 2 bundled (founder picks angle + approves script in one Notion review)
5. Render fires (~2-4 hours of compute time)
6. Gate 3 final render approval
7. Customer receives 1 × 9:16 MP4

**Deliverable specs:**
- 1 video, 9:16 aspect ratio
- 1080×1920 resolution, 30fps, h264 codec, AAC audio
- 15-30 seconds duration
- Royalty-free background music (selected from curated library by tone)
- White kinetic captions with red emphasis words
- No end card
- Master file delivered via 7-day signed Supabase Storage URL

**Why this price:** Below ₦100K is the psychological "test purchase" range for Nigerian SMBs. Margin is thin (~₦70K after costs at COGS ~$3) but volume justifies it as the pipeline-builder.

**Customer expectations:** "I want to try it without committing big money." We deliver: legible, professional, posting-ready.

### Standard — ₦175,000

**The "I am running ads and want consistent supply" tier.** Built for the marketer-owner with a real budget who is testing creative.

**Workflow:**
1. Customer fills brief
2. Quote with 3 angles delivered
3. Customer pays ₦175K via Paystack
4. Gate 1 — angle approval
5. Gate 2 — script approval
6. Render fires
7. Gate 3 — final render approval
8. Customer receives 3 video files (9:16, 1:1, 16:9)

**Deliverable specs:**
- 1 video rendered in 3 formats:
  - 9:16 (Reels, TikTok, Shorts) — 1080×1920
  - 1:1 (Feed) — 1080×1080
  - 16:9 (YouTube, web) — 1920×1080
- 30fps, h264, AAC
- 15-45 seconds duration
- Artlist-licensed music (specific track selected for niche/tone)
- Niche-styled captions:
  - Real estate: gold emphasis, Inter
  - Education: indigo emphasis, Inter
  - Fashion/beauty: red emphasis, Inter (default)
  - Fintech: cyan emphasis, JetBrains Mono
  - Health: sage emphasis, Inter
- Branded end card with customer's logo + CTA
- Master file delivered via 7-day signed URLs

**Why this price:** Standard is the volume tier — this is what most repeat customers settle into. ₦175K is enough margin for proper review depth (~₦150K after costs at COGS ~$6) and supports our 36h SLA.

**Customer expectations:** "I want a video that looks good across platforms and shows my brand professionally." We deliver: multi-format, music-matched, end-card-branded, niche-tuned.

### Creative Pod — ₦350,000

**The "I want a campaign, not just a video" tier.** Built for agencies, brand teams, or established SMBs running multi-asset campaigns.

**Workflow:**
1. Customer fills brief, indicates which 3 angles they want explored OR lets us recommend
2. Quote with detailed campaign concept (3 angle directions)
3. Customer pays ₦175K (50%) via Paystack
4. Gate 1 — multi-angle approval (3 angles each get script-direction)
5. Gate 2 — full script approval for all 3 videos. Customer pays ₦175K (50%) on approval.
6. **If avatar-led chosen:** photo upload + Gate 3-bis avatar quality check
7. Render fires (HeyGen path for avatar-led, normal path for documentary)
8. Gate 3 — final render approval (per video)
9. Customer receives 3 videos in all formats + 4K masters

**Deliverable specs:**
- 3 videos, each rendered in 4 formats:
  - 9:16 — 1080×1920
  - 1:1 — 1080×1080
  - 16:9 — 1920×1080
  - 4K master — 3840×2160 (h265 ProRes)
- 30fps, AAC audio
- 15-60 seconds each
- Artlist-licensed music with scene-specific selection per video
- Custom typography (font + emphasis colour set per video, can match brand guide)
- Branded end card per video

**Optional Creative Pod features:**

- **Voice cloning (fal.ai PlayHT v3):** Customer uploads 60s of clean voice audio (no background music, single speaker, well-lit recording). We clone into the platform; their voice narrates one or more of the 3 videos. Adds ~$2 to COGS, no charge to customer (included in tier price).

- **Custom avatar from photo (HeyGen):** Customer uploads their photo, signs consent, photo passes Gate 3-bis quality check. HeyGen renders an avatar that lip-syncs to the script. Used for one or more of the 3 videos. Adds ~$5-15 to COGS depending on video length, no charge to customer.

- **Multi-character dialogue:** Up to 2 speakers per video. Camera cuts between them at speaker turns. Hard cap at 2 — 3+ speakers requires a custom quote (see ADR 0012).

**Why this price:** Creative Pod is positioned at the agency-buyer price point. ₦350K with 50/50 payment terms reduces perceived risk. The 72h SLA reflects the higher production complexity. Margin is healthier (~₦325K after costs at COGS ~$25 worst case) and supports the bonus features without per-feature upcharges.

**Customer expectations:** "I want a campaign-quality output that I'd be proud to put on a billboard." We deliver: 3 videos, 4 formats each, music-matched, brand-typography-matched, optionally avatar-rendered, with founder review depth at each gate.

---

## Retainers (post-Phase-1, mentioned but not v1 scope)

Two retainer tiers planned for post-90-day launch:

| Retainer | Monthly | Deliverables |
|---|---|---|
| Momentum | ₦600,000/month | 4 Standard-equivalent videos per month (1/week), priority queue |
| Velocity | ₦1,200,000/month | 8 Standard-equivalent + 2 Creative-Pod-equivalent per month, dedicated reviewer slot, 24h SLA |

Retainers replace the per-order Paystack flow with monthly invoicing (NGN business invoice, paid by bank transfer with 7-day terms). Customer email signature updates to reflect retainer-tier customer status.

For retainer SLA breach handling, see `docs/specs/retainer-tier.md` (TBD post-launch).

---

## NGN business invoice for retainers

Retainer customers receive a proper Nigerian business invoice (not a Paystack receipt). Invoice format:

- Issuer: `plovera` (a registered Nigerian business — TBD on incorporation)
- Customer business name + RC number (if registered company)
- Invoice number (sequential)
- Issue date + due date (7 days)
- Line items: month + retainer tier + deliverables summary
- VAT: handled per Nigeria FIRS requirements (currently 7.5%, applied to NGN amount)
- Bank transfer details: GTBank or Access account number, BVN-verified

Invoice is generated on the 1st of each month for the upcoming month. Late payment after due date triggers polite reminder email; sustained delinquency past 14 days triggers founder phone call.

---

## What's NOT in any tier

- Audio narration recorded by a real human (we use AI TTS)
- Live-action footage (we generate everything)
- Logo design or brand identity work
- Marketing strategy consulting (separate offering, post-Phase-2)
- Ad campaign management (out of scope; customer posts videos themselves)
- Multi-language localisation (English only at v1; Yoruba/Igbo/Hausa post-Phase-3)
- Dedicated account manager (founder is the only point of contact during the first 90 days)
- White-label re-branding for agencies buying on our behalf (post-Phase-2)

If a customer asks for any of these, founder responds with a polite "we don't offer that today, but here's what we do offer" plus the v1 tier matrix.

---

## Pricing change protocol

These prices are committed to for at least the first 90 days. Within those 90 days, the only changes allowed are:

- **Discounts at founder discretion** (e.g., first-customer-of-the-niche discount, referral discount)
- **Refunds at founder discretion** (above and beyond the standard refund flow)

Material price changes (the ₦75K/₦175K/₦350K base prices) are NOT made within the 90 days. After the 90-day mark, a pricing review includes:

- Cost trends (Anthropic, fal.ai, HeyGen pricing changes)
- Competitive positioning (UGC Padi, Snitch.video, others)
- Demand signal (waitlist depth, conversion rate, NPS)
- Capacity (founder review-time saturation)

If prices change, all in-flight orders are honoured at their original quote price. New customers see the new prices.

---

## Why these specific numbers

Quick justification for the curious:

- **₦75K (Pilot):** Below the ₦100K psychological threshold for "test purchase". Above ₦50K so not perceived as cheap-and-fast. Sweet spot.
- **₦175K (Standard):** Anchors at 2.3× Pilot. Gives meaningful upgrade signal. Below the ₦200K threshold where customers want to "talk to sales".
- **₦350K (Creative Pod):** 2× Standard. Positions at "agency-grade" pricing. Above the ₦300K threshold where customers expect deep customisation, which we deliver via the optional features.
- **50/50 on Creative Pod:** Reduces perceived risk for a bigger ticket. Common Nigerian SMB practice.
- **₦25K/revision beyond included:** Below the per-video tier price (so it's not painful), above the per-revision marginal cost to us (so we don't lose money on a high-revision customer).

For full pricing analysis vs competitors, see `ugc-padi-analysis.html`.
