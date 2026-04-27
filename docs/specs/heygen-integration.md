# HeyGen Integration Spec

> The implementation contract for avatar-led video features in Creative Pod tier via HeyGen's Avatar API.

**Read alongside:** ADR 0011 (heygen-creative-pod-only), ADR 0012 (cap-multichar-at-2), `gates-and-approvals.md` §gate-3-bis, `security.md` §customer-photo-consent, `customer-journey.md` §creative-pod-avatar-branch.

---

## What this spec covers

- When avatar features are offered (and when they are explicitly NOT)
- Custom avatar creation from a customer photo
- Multi-character scene rendering and the 2-speaker cap
- Per-segment FFmpeg assembly back into the documentary render core
- Gate 3-bis quality check
- Consent, retention, NDPC alignment
- API mechanics, error handling, cost ceiling
- Edge cases and explicit non-goals

This spec is intentionally narrow. HeyGen has a large feature surface (templates, photo avatars, video translation, interactive avatars). We use a **small, well-defined slice**: custom photo avatar + scripted speech.

---

## When avatar features are offered

**Tier:** Creative Pod only (₦350K).

Avatar features are not available in Spark (₦75K), Cinematic (₦175K), or any retainer below Creative Pod equivalence. See ADR 0011 for the full reasoning. The short version: the operating cost, consent risk, and quality-control overhead of avatar work all need to live in a tier whose price absorbs them.

**Stage in customer journey:** customer chooses at intake. The intake form asks:

> Should the videos include an on-camera presenter?
>
> - No, documentary style only (default; recommended for most products)
> - Yes, my custom avatar (free with Creative Pod, requires a clear photo + voice consent)
> - Yes, two speakers (e.g., interview format — capped at 2, please describe in the brief)

If the customer selects either avatar option, the agent transitions to `avatar_consent_check` after intake, before any production starts. See AGENT.md for the state machine.

**Stage in customer journey, late opt-in:** if the customer didn't opt in at intake but the founder believes during Gate 2 (script review) that an avatar lead-in would lift conversion, the founder can offer it. The agent has a `late_avatar_opt_in` transition for this. The customer must still pass `avatar_consent_check`.

---

## Custom avatar creation from a customer photo

### Photo requirements

The customer uploads **one** photo via WhatsApp or email. Requirements communicated to the customer up-front:

- Front-facing, head and shoulders visible
- Eyes open, neutral or natural expression
- Even lighting — no harsh shadow on half the face
- Plain or simple background (HeyGen separates the subject, but a busy background increases failure rate)
- At least 1024x1024 resolution
- The customer must be the person in the photo, OR have explicit written permission from the person in the photo

We accept JPG, PNG, HEIC. We reject anything else (no AI-generated photos, no photos of minors, no photos that include other identifiable people in the frame).

### Consent capture (NDPC alignment)

Before the photo touches the HeyGen API, the customer signs a consent record. This is a Notion form that produces a row in the `order_consent` table (see `migrations/002_orderconsent.sql`).

The consent record captures:

- `order_id` — FK to orders
- `customer_email` — the email on the order
- `consent_type` — enum: `voice_clone`, `face_avatar`, `both`
- `consent_text_version` — semver of the consent paragraph the customer was shown
- `consent_text_hash` — SHA-256 of the exact text shown
- `signed_at` — timestamp when the customer ticked the box
- `signed_via` — `notion_form` (the only channel for v1)
- `ip_address` — captured via Notion form metadata
- `revocation_at` — null until revoked; if set, the avatar must be deleted from HeyGen and from our `customer_assets` bucket within 24 hours

Consent text v1.0 is in `apps/agent/src/consent/v1_face_avatar.txt`. **Do not edit it without bumping the version.** ADR 0014 covers why.

### HeyGen avatar creation flow

Once consent is signed:

1. Photo uploaded to Supabase Storage at `customer_assets/{order_id}/source_photo.{ext}`.
2. `apps/agent/src/heygen/create_avatar.py` calls `POST /v2/photo_avatar/photo/generate` with the photo URL.
3. HeyGen returns `generation_id`. We poll `GET /v2/photo_avatar/{generation_id}` every 30 seconds, max 30 attempts (15 minutes).
4. On success, HeyGen returns `photo_avatar_id`. We persist this in `orders.heygen_avatar_id`.
5. On failure or timeout, the agent transitions to `avatar_quality_check_failed` and the order routes to founder for manual review or fallback to documentary style.

The avatar generation typically takes 3-7 minutes. We allocate 15 minutes before timing out.

---

## Multi-character cap at 2

ADR 0012 locks the cap. **Two speakers maximum per video.** This applies to:

- Two custom avatars (e.g., founder + co-founder talking)
- One custom avatar + one stock HeyGen avatar
- Two stock HeyGen avatars (rare in practice — most Creative Pod customers want their own face)

Any request for 3+ speakers triggers a custom quote, not a Creative Pod order. The intake form rejects 3+ in validation.

**Why the cap.** Each additional speaker doubles the production-style review burden, multiplies the failure modes (lip-sync drift, scene transitions between speakers, audio leveling), and changes the cost envelope past what the Creative Pod price absorbs. See ADR 0012 for the full math.

---

## Per-segment FFmpeg assembly

This is the one piece of the integration that is **not** off-the-shelf HeyGen.

HeyGen produces avatar-led video segments. The Vision GridAI render core produces documentary-style B-roll, captions, music, and pacing. Creative Pod videos blend both: avatar-led intro, documentary-style middle (product/service shots, captions, music), avatar-led outro.

The segment plan is decided at script generation (Gate 2). The script gets segmented into:

- `segment_type='avatar'` — the avatar speaks; HeyGen renders this segment
- `segment_type='documentary'` — Vision GridAI renders this segment via the existing render core (TTS + image generation + Ken Burns + captions + music)

The agent fan-outs both render paths in parallel:

```
            ┌──── HeyGen API ──── avatar segments (mp4 + audio) ────┐
script ─→ │                                                          ├─→ FFmpeg concat ─→ final.mp4
            └──── VG render core ── documentary segments (mp4) ─────┘
```

The FFmpeg concat is in `apps/agent/src/render/segment_concat.py`. It uses the FFmpeg concat demuxer, **not** the concat protocol — concat protocol does not handle differing audio sample rates between HeyGen output (24kHz) and Chirp 3 HD output (24kHz, but encoded differently). The demuxer with explicit re-encode (`-c:v libx264 -c:a aac -ar 48000`) avoids the audio glitch at segment boundaries.

**Gotcha inherited from VG fork manual:** the FFmpeg fps mismatch silent truncation bug. HeyGen outputs at 30fps, VG renders at 30fps, so this is fine **in practice**, but the segment concat script asserts `ffprobe`'d fps on every input file before concat and aborts loudly if there's a mismatch. Don't trust it silently.

---

## Gate 3-bis quality check

Standard documentary orders go through Gate 3 (final video review by founder before delivery). Avatar orders go through Gate 3-bis, which adds two specific checks on top of Gate 3:

1. **Lip-sync drift check.** Founder watches the avatar segments at full speed and confirms no visible lip-sync drift. This is the failure mode HeyGen most often produces in noisy or accented voice cloning (which Creative Pod can stack via fal.ai PlayHT — see voice-cloning.md). If drift is visible, the order routes back to the agent's `production_avatar_retry` state with a flag to regenerate the avatar segments only.
2. **Avatar realism check.** Founder confirms the avatar doesn't look "uncanny." HeyGen's photo avatars are good but can produce rare artifacts (mouth tearing on hard consonants, eye dart, rigid neck). If the avatar looks wrong, founder can reject and the order routes to `documentary_fallback` — the same script gets re-rendered as documentary-style and the customer is notified that their avatar didn't pass quality review (with a brief explanation).

Documentary fallback is **always** offered as a graceful degrade. The Creative Pod price stays the same (the customer paid for the script + production quality, not specifically for the avatar feature).

See `gates-and-approvals.md` §gate-3-bis for the full checklist.

---

## API mechanics

### Authentication

HeyGen API key lives in `HEYGEN_API_KEY` environment variable on the agent VPS. See `.env.agent.example`. The key is per-organization and rate-limited; we use the **Pro plan** (Creative Pod volumes don't justify Enterprise yet).

### Endpoints we use

| Endpoint | Purpose |
|---|---|
| `POST /v2/photo_avatar/photo/generate` | Generate custom photo avatar from uploaded image |
| `GET /v2/photo_avatar/{id}` | Poll avatar generation status |
| `POST /v2/video/generate` | Generate avatar speaking the script segment |
| `GET /v2/video_status.get` | Poll video generation status |
| `DELETE /v2/photo_avatar/{id}` | Delete avatar on consent revocation or order completion + retention period |
| `GET /v2/voices` | List available voices (for voice selection if customer doesn't clone their own) |

### Endpoints we explicitly do NOT use

- Video translation
- Interactive avatars / streaming avatars
- Templates
- Brand voice
- Webhooks (we poll instead — see error handling)

If a future ADR opens this surface, that's a new spec, not a change to this one.

### Error handling

HeyGen webhooks are not used in v1. We poll status endpoints with exponential backoff. Reasoning:

- Webhooks require a public ingress on the agent VPS, which adds attack surface for an integration we use a few times per Creative Pod order.
- Polling is simple, idempotent, and produces clean retry semantics.
- The latency cost of polling vs webhook is ~30 seconds per status check, which is negligible against avatar generation times of 3-7 minutes.

Polling cadence:
- Avatar creation: every 30s, max 30 attempts (15 minutes)
- Video generation: every 60s, max 20 attempts (20 minutes)

If the agent crashes mid-poll, the resume-and-retry pattern (see VG fork manual §resume-retry) re-reads the `heygen_generation_id` from `production_log` and resumes polling.

### Cost ceiling

A Creative Pod order with avatar can hit the HeyGen API up to:
- 1 avatar creation (~$1.50 in HeyGen credits)
- 6 avatar segments × 30 seconds each (~$0.40 per segment, $2.40 total)
- Worst case with one full retry cycle: $7.80

The Creative Pod price (₦350K ≈ $230) absorbs this comfortably even with retries. The overall cost-per-order envelope is calculated in `cost-calculator.html`.

---

## Edge cases

**Customer uploads a photo with another identifiable person in the frame.**
Reject at intake review (Gate 1). Ask for a new photo. Don't crop — cropping doesn't remove the consent issue.

**Customer revokes consent after avatar is created.**
Within 24 hours: delete avatar via `DELETE /v2/photo_avatar/{id}`, delete photo from Supabase Storage, set `order_consent.revocation_at`, refund per refund policy (see paystack-integration.md). The order is marked `cancelled_consent_revoked`.

**HeyGen generates an avatar that fails the avatar quality check at Gate 3-bis.**
Two strikes → documentary fallback. We don't burn through 3+ retries; if HeyGen can't produce a clean avatar from the customer's photo on attempt 2, the photo isn't usable and we deliver documentary instead.

**The customer wants their avatar to use a cloned voice (stacked with voice-cloning.md).**
This is supported in Creative Pod. The flow becomes: photo + voice sample at intake → both consents signed → HeyGen creates the avatar → fal.ai PlayHT clones the voice → HeyGen takes the cloned voice as the audio input for video generation (HeyGen accepts audio file input on `POST /v2/video/generate`, bypassing HeyGen's TTS). This is the highest-quality output we offer and the most operationally sensitive. Gate 3-bis applies.

**HeyGen API outage.**
The agent transitions to `production_avatar_blocked` and notifies the founder. If the outage exceeds 4 hours, the founder can opt to fallback to documentary for that order, with the customer's consent, at no price reduction (Creative Pod includes documentary as a graceful degrade).

**Customer is a minor.**
Reject at intake. Creative Pod is for adult business owners or with verified guardian consent (which we don't process — we refer to a human consultation instead).

---

## Explicit non-goals

The following are **not** in scope for v1 of this integration. Each is a separate ADR / spec if we ever add them:

- HeyGen Templates (we generate from photo, not from template avatars)
- HeyGen Interactive Avatars / streaming
- HeyGen Video Translation
- Avatar lip-sync to non-English (Pidgin, Yoruba, Igbo, Hausa) — this is on the v2 roadmap and is genuinely hard; HeyGen's training data skews English
- Multi-language avatars (one avatar speaking multiple languages in one video)
- Avatar emotion / gesture controls (HeyGen supports these in beta; we don't expose them)

---

## Implementation checklist

Before the first Creative Pod order with avatar:

- [ ] HeyGen Pro account active, API key in `.env.agent`
- [ ] Consent text v1.0 reviewed by founder and locked
- [ ] `apps/agent/src/heygen/create_avatar.py` implemented and tested with a test photo
- [ ] `apps/agent/src/heygen/generate_video.py` implemented and tested with a test segment
- [ ] `apps/agent/src/render/segment_concat.py` implemented and tested with a 2-segment test (1 avatar + 1 documentary)
- [ ] Notion consent form built and connected to `order_consent` table
- [ ] Gate 3-bis checklist added to founder review template
- [ ] Documentary fallback path verified end-to-end
- [ ] Cost ceiling verified against Creative Pod margin

---

## References

- HeyGen API docs: https://docs.heygen.com/
- ADR 0011: heygen-creative-pod-only
- ADR 0012: cap-multichar-at-2
- voice-cloning.md (the sister spec for fal.ai PlayHT)
- gates-and-approvals.md §gate-3-bis
- security.md §customer-photo-consent
- VISION_GRIDAI_FORK_MANUAL.md §inherited-gotchas (FFmpeg fps mismatch trap)
