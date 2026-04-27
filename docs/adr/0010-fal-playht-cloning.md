# 0010. Voice cloning via fal.ai PlayHT v3 (Creative Pod only)

Date: 2026-04-26
Status: Accepted

## Context

Creative Pod tier offers an optional feature where the customer uploads 60 seconds of their own voice audio and we render the videos using a clone of that voice. The use case: founder-led content where the customer wants their actual voice narrating their own ads.

Three voice cloning options were considered:

1. **ElevenLabs Professional Voice Cloning.** Industry-leading clone quality, $99/month + $0.30/1K characters at Pro tier. Customer's voice would live in our ElevenLabs account.
2. **fal.ai PlayHT v3.** Same model architecture, $0.30 per voice clone (one-time), then ~$0.005/1K characters at use time. Significantly cheaper per-clone, comparable quality for narration use case.
3. **Open-source clone (Tortoise, XTTS, etc.).** Self-hostable, no per-clone cost, but quality lags behind hosted options and our VPS doesn't have GPUs.

The voice clone is a single-customer-per-order feature. We don't reuse customer voices across orders (per consent) and we don't build a voice library.

## Decision

**fal.ai PlayHT v3** for Creative Pod voice cloning.

Workflow:
1. Customer uploads 60s clean audio sample at intake (or after Gate 2 if they opt in mid-flow)
2. Customer signs voice-clone consent (separate from photo consent for HeyGen avatar)
3. Agent calls fal.ai PlayHT v3 to create clone, gets a voice_id
4. WF_TTS_AUDIO uses the voice_id for that order's renders
5. Voice_id is deleted from fal.ai after order delivery + 90 days (matches photo retention policy)

Voice sample requirements:
- 60 seconds minimum
- Single speaker, no overlap
- No background music or noise
- Clear pronunciation
- WAV or MP3 format

## Consequences

**Cost:** ~$2 per Creative Pod order using voice cloning. No upcharge to customer (included in tier).

**Why fal.ai over ElevenLabs:** we already have a fal.ai account for image generation (Seedream 4.5) and motion (Seedance 2.0 Fast) inherited from VG. Adding voice cloning under the same vendor reduces auth surface, reduces billing complexity, simplifies the n8n credential store.

**Cap at Creative Pod tier:** voice cloning at Pilot or Standard would inflate the price per order significantly. Pilot ₦75K can't support a $2-3 marginal cost without margin compression. Creative Pod ₦350K absorbs it.

**Consent and retention:**
- Customer signs explicit voice-clone consent at upload
- Audio sample stored encrypted in Supabase Storage `customer-voice-samples` bucket (RLS-locked)
- Retention: 90 days post-delivery, then deleted
- fal.ai PlayHT side: voice_id deleted after order completion (no long-term storage on their side)

**Quality acceptance:** voice clones from 60s samples are imperfect on rare phonemes. Founder reviews the first 3 seconds of each scene's TTS at Gate 3 to catch mispronunciations.

**Brand-name pronunciation:** if the customer's brand name is unusual, we generate a phonetic spelling at Gate 2 ("Adeyemi → Ah-day-yeh-me") that's used in the script narration text. This is independent of voice cloning — it's needed for Chirp 3 HD too.

## Reference

ADR 0009: Chirp 3 HD as base TTS.
ADR 0011: HeyGen for avatar features (paired with voice cloning for full avatar-led content).
`docs/specs/voice-cloning.md` — implementation details.
