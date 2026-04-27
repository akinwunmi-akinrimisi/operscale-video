# 0009. Google Cloud Chirp 3 HD as TTS across all tiers

Date: 2026-04-26
Status: Accepted

## Context

We need a text-to-speech provider for narration audio across all three tiers (Pilot, Standard, Creative Pod). Three options were considered:

1. **ElevenLabs.** Industry-leading naturalness, strong Nigerian English voice options. Costs $0.30/1K characters at the production tier (~$0.05-0.15 per Pilot video, ~$0.15-0.30 per Standard video).
2. **Google Cloud Chirp 3 HD.** New as of late 2025, comparable quality to ElevenLabs for narration, $0.016/1K characters Standard voice (~$0.005-0.01 per Pilot, $0.01-0.025 per Standard).
3. **Google Cloud Standard TTS (legacy).** Cheap but lower quality; rejected on quality grounds.

Vision GridAI currently uses Chirp 3 HD (post-Session 12 migration from ElevenLabs for ~95% cost savings). Their `WF_TTS_AUDIO` workflow is built around it.

## Decision

**Google Cloud Chirp 3 HD across ALL tiers** for the synthetic-voice baseline. Voice clone for Creative Pod is a SEPARATE addition (see ADR 0010).

Default voice: `en-NG-Standard-A` (Nigerian English).

Per-niche speaking rate adjustments:
- Real estate: 0.95×
- Education: 0.95×
- Fashion/beauty: 1.05×
- Fintech: 1.00×
- Health: 0.95×

Operator can override per-order via `production_registers.config.tts_voice` and `tts_speaking_rate`.

## Consequences

**Saved:** ~$0.04-0.27 per video relative to ElevenLabs. At 5 orders/day target: ~$200-1,300/month savings. Material at our scale.

**Inherits VG's WF_TTS_AUDIO untouched.** Same workflow we copy from VG handles Chirp 3 HD; no n8n changes needed.

**Quality ceiling.** Chirp 3 HD is excellent but not always indistinguishable from real human narration. For brand-conscious customers requesting "human voice", we offer voice clone via fal.ai PlayHT in Creative Pod (ADR 0010).

**No fallback to ElevenLabs.** Even if Chirp 3 HD has a regional outage, we don't auto-fallback. Outages are rare; a 1-2 hour delay is preferable to inconsistent voice quality across our renders.

**No premium voice tier within Chirp 3 HD.** All tiers get the same base voice. Customer differentiation is in production register, image generation quality, music selection — not TTS.

## Reference

VG cost-economics doc: https://akinwunmi-akinrimisi.github.io/vision-gridai-platform/operations/cost-economics/
ADR 0010: voice cloning for Creative Pod.
