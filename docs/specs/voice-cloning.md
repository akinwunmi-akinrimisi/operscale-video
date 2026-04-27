# Voice Cloning Spec

> The implementation contract for optional voice cloning in Creative Pod tier via fal.ai PlayHT v3.

**Read alongside:** ADR 0010, `gates-and-approvals.md`, `security.md` §customer-photo-consent.

---

## What this spec covers

- When voice cloning is offered
- Voice sample upload UX
- Consent + retention
- fal.ai PlayHT v3 integration mechanics
- Edge cases and quality acceptance

---

## When voice cloning is offered

**Tier:** Creative Pod only (₦350K).

**Stage in customer journey:** customer can opt in at two points:
1. **At intake** — checkbox on the form: "I want my voice in the videos (optional, free, takes ~5 extra minutes)"
2. **After Gate 2** — if the customer didn't opt in at intake, founder can suggest it during Gate 2 review if the script would benefit from a personal voice

If selected, the agent transitions to a `voice_clone_request` state after Gate 2 approval. Customer receives email + WhatsApp asking for voice sample.

## Voice sample requirements

Customer is asked to record (via their phone) a 60-second clip:
- Single speaker (the customer themselves)
- Clear, natural pronunciation — they read a provided sample script (~120 words covering common sounds/phonemes)
- No background music
- Quiet environment (not a car, not a coffee shop)
- Format: WAV or MP3
- Recommended: phone's voice memo app, AirPods/headphones with mic, or a USB mic

The provided sample script (English):

> "My name is [your name] and I'm the founder of [your business]. We help [your customers] with [the problem you solve]. The reason I started this is [your motivation in one sentence]. What I love about my work is [one specific thing]. The hardest part is [one specific challenge]. If you're working with us, I want you to feel [emotion you want them to feel]. We've been doing this for [duration], and the most rewarding moment was [specific story or moment]. I believe that [one strong belief about your industry]. Thanks for trusting us, and I'll talk with you soon."

This script is deliberately diverse phonetically and emotionally. Customer reads it once, no rehearsal needed.

## Upload UX

Secure upload page at `plovera.shop/voice-upload/[token]`:

```
Header: "Upload your voice sample"
Body:
  - "We'll use this 60-second clip to create a voice clone that narrates your videos."
  - "Hit record below. Read the script we sent in the email. Don't worry if you stumble — that's natural."
  - [Embedded recording widget — uses Web Audio API for in-browser recording]
  - [File upload alternative for those who prefer to record on their phone]
Consent box (must be checked):
  ☐ "I consent to fal.ai PlayHT v3 creating a voice clone from this sample. The clone will be used only for my Operscale Video Ads order and deleted from fal.ai's system within 90 days post-delivery. I confirm this is my own voice and I have all rights to it."
[Submit button — disabled until consent box is checked AND audio is uploaded]
```

On submit:
1. Audio uploaded to Supabase Storage `customer-voice-samples` bucket (RLS-locked)
2. `order_consent` row written with `consent_text_signed`, `signed_at`, `ip_address`
3. `WF_VOICE_CLONE_INGEST` fires

## fal.ai PlayHT v3 integration

```javascript
// WF_VOICE_CLONE_INGEST
1. Read audio from Supabase Storage
2. POST to fal.ai PlayHT clone endpoint:
   POST https://fal.run/fal-ai/playht-v3-voice-clone
   Headers:
     Authorization: Key ={{ $env.FAL_KEY }}
     Content-Type: application/json
   Body: {
     "voice_sample_url": "<supabase-storage-signed-url>",
     "voice_name": "operscale-{order_id}"
   }
3. fal.ai returns voice_id (e.g., "v_pf5h8s9b3...")
4. UPDATE orders SET 
     production_register = 'OPERSCALE_02_AVATAR_LED',
     cloned_voice_id = $1
   WHERE id = $2
5. Transition agent state to production_avatar (or production_documentary if customer chose voice clone but documentary visuals)
```

For TTS calls during render:

```javascript
// WF_TTS_AUDIO (modified for cloned voice)
1. Check orders.cloned_voice_id
2. If NULL: use Google Cloud Chirp 3 HD (default flow)
3. If NOT NULL: 
   POST https://fal.run/fal-ai/playht-v3-tts
   Headers:
     Authorization: Key ={{ $env.FAL_KEY }}
   Body: {
     "voice": "{{ $('Get Order').item.json.cloned_voice_id }}",
     "text": "{{ $('Get Scene').item.json.narration_text }}",
     "speed": 0.95
   }
4. Save returned audio URL/blob to /tmp/operscale-production/<order_id>/audio/scene_<n>.mp3
```

## Cost

Per order using voice clone:
- One-time clone: $0.30 (fal.ai PlayHT v3 clone fee)
- Per video: ~$0.005-0.015 per scene × 8-10 scenes = ~$0.04-0.15 TTS cost (vs Chirp 3 HD's $0.005-0.025 per video)

Net: ~$1-2 per Creative Pod order with voice clone. Within Creative Pod margin.

## Quality acceptance

Voice clones from 60s samples have quality variance:
- 90% of orders: indistinguishable from real customer voice in conversational delivery
- 10% of orders: noticeable artefacts on rare phonemes (foreign words, brand names with unusual spellings)

**At Gate 3:** founder reviews the first 5 seconds of each scene's TTS audio for clone quality. If issues:
- **Single mispronunciation in script:** add phonetic spelling to script (e.g., "Adeyemi" → "ah-day-yeh-me"), regenerate that scene's TTS
- **Systematic clone quality issues:** offer customer choice — "we can use your stock TTS instead, or you can record a new sample"

## Retention and deletion

| Asset | Retention | Deletion |
|---|---|---|
| Original voice sample audio | 90 days post-delivery in `customer-voice-samples` bucket | Auto-delete via cron after 90 days |
| fal.ai voice clone (server-side) | Until order delivered + 90 days | DELETE call to fal.ai API |
| Cloned voice TTS outputs (per-scene MP3s) | Same as render artefacts | Cleaned with order's render directory |

## Consent text canonical version

The consent text customer signs at upload (logged verbatim in `order_consent.consent_text_signed`):

> "I consent to fal.ai PlayHT v3 creating a voice clone from the audio sample I am uploading. I understand the clone will be used only for my Operscale Video Ads order [order_id] and that fal.ai will delete the clone from their system within 90 days post-delivery. I confirm this is my own voice or I have full legal rights to use it for this purpose. I authorise plovera to render derivative video content using this cloned voice for the purposes of fulfilling my order."

If customer is uploading a voice sample that is NOT their own (e.g., a colleague, a hired voice actor), they must additionally provide written confirmation from the person whose voice it is. This is rare and handled via founder escalation.

## Failure modes

| Failure | Handling |
|---|---|
| fal.ai PlayHT clone API returns error | Retry via WF_RETRY_WRAPPER (1s/2s/4s/8s, 4 attempts max) |
| Customer audio fails fal.ai's automated quality check (too noisy, too short, too long) | Customer notified with specific guidance, asked to re-upload (up to 3 attempts) |
| 3 failed re-uploads | Founder escalation. Options: founder approves a marginal sample, downgrade to stock Chirp 3 HD voice (refund of cloning premium = $0 since included in tier), customer waits and tries another time |
| Cloned voice outputs in production show systematic artefacts | Founder regenerates affected scenes with phonetic spelling, OR switches to Chirp 3 HD for the affected videos |

## What this spec does NOT cover

- Voice cloning for non-Creative-Pod tiers (out of scope for v1)
- Multilingual voice cloning (English only at v1; Yoruba/Igbo/Hausa post-Phase-3)
- Voice transformation beyond cloning (e.g., aging the voice up/down — not supported)
- Reusing a customer's clone across multiple orders without re-consent (not allowed; each order gets fresh consent + clone)
