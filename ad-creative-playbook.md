# Ad Creative Playbook

> The creative direction guide for our paid ad campaigns and the content bank.
> Defines what "good" looks like, niche by niche, register by register.

**Read alongside:** `content-bank-playbook.md`, `niche-briefs/*.md`, `pricing-and-packages.md`.

---

## Two production registers

Per ADR 0008's inheritance from Vision GridAI, we have two configured registers in our Supabase `production_registers` table:

### `OPERSCALE_01_DOCUMENTARY`

The default register for all tiers. Cinematic, warm, confident. Inspired by VG's `REGISTER_01 The Economist` but tuned for ad-format pacing (faster scenes, hookier music).

**Visual DNA:**
- Muted colour with controlled warmth, subtle film grain
- 35mm look, rule of thirds composition
- Generous negative space for caption overlays
- Shallow depth of field on subject shots

**Audio DNA:**
- TTS voice: Google Cloud Chirp 3 HD `en-NG-Standard-A` at 0.95× speaking rate
- Music BPM: 80-100, uplifting and moderate-energy
- Music mood keywords: cinematic, uplifting, moderate energy

**Motion DNA:**
- Default zoom: `slow_push` (gentle zoom-in over 4 seconds)
- Typical scene length: 4 seconds
- Transition duration: 400ms (xfade dissolve)

**Caption DNA:**
- Font: Inter
- Emphasis colour: per-niche (gold/indigo/red/cyan/sage)

**Used by:** Pilot, Standard, Creative Pod (default style)

### `OPERSCALE_02_AVATAR_LED`

Reserved for Creative Pod tier when customer chooses HeyGen avatar production.

**Visual DNA:**
- Studio-lit talking-head subject, high-contrast
- Clean professional background
- Static composition (avatar is the visual)

**Audio DNA:**
- TTS voice: Google Cloud Chirp 3 HD `en-NG-Standard-A` at 1.00× speaking rate, OR fal.ai PlayHT v3 cloned voice
- Music BPM: 90-110, energetic and modern
- Music mood keywords: energetic, modern, confident

**Motion DNA:**
- Default zoom: `static` (avatar already provides motion)
- Typical scene length: 6 seconds (avatar segments are longer)
- Transition duration: 250ms (faster cuts between speaker turns)

**Caption DNA:**
- Font: Inter
- Emphasis colour: per-niche (same palette as documentary)

**Used by:** Creative Pod only, when avatar-led production chosen

---

## Per-niche caption emphasis colours

Set as a 20-line extension to `generate_kinetic_ass.py` (per fork manual §8.7). Niche is a script parameter; the emphasis colour swaps per niche.

| Niche | Emphasis hex | Rationale |
|---|---|---|
| Real estate | `#D4AF37` (gold) | Conveys luxury and aspiration |
| Education | `#3D4A78` (indigo) | Conveys trust, depth, intellect |
| Fashion / e-com | `#FF4444` (red) | Conveys urgency, wantness |
| Fintech | `#00D4FF` (cyan) | Conveys tech, clarity, modernity |
| Health | `#5A7846` (sage) | Conveys wellness, calm, natural |

White is always the base caption colour; only emphasis words (per `caption_highlight_word` per scene) get the niche-specific colour.

---

## Hook-driven script structure

Every video — content bank or paid — follows a 3-act structure compressed into 15-60 seconds:

**Act 1: Hook (first 3 seconds)**
- A pattern interrupt that makes the viewer stop scrolling
- Often a question, a surprising fact, or a "this is wrong" claim
- Must reference the niche AND the customer's problem

**Act 2: Problem expansion + solution introduction (seconds 3-15)**
- Acknowledge the customer's actual pain
- Hint at the solution without giving it all away
- Build trust through specificity (numbers, names, concrete examples)

**Act 3: Call-to-action (last 5-10 seconds)**
- Single, specific CTA per the customer's brief
- Urgency language only when honest (avoid manufactured scarcity)
- End card with branding (Standard+ tiers)

For Pilot tier, Acts 1-3 fit in 15-30 seconds. For Standard, 15-45 seconds. For Creative Pod, 15-60 seconds with more room for the Act 2 build.

---

## Tone calibration per niche

The `prompt_configs` table holds per-niche tone instructions. Loaded at script generation time and combined with the customer's preferred-tone selection from the brief.

| Niche | Default tone | Voice rate | Tone modifiers customer can override |
|---|---|---|---|
| Real estate | Warm authoritative | 0.95× | Aspirational / Down-to-earth / Luxury |
| Education | Direct teacher | 0.95× | Energetic / Calm / Inspirational |
| Fashion | Energetic conversational | 1.05× | Playful / Aspirational / Edgy |
| Fintech | Clinical precise | 1.00× | Confident / Educational / Reassuring |
| Health | Calm reassuring | 0.95× | Encouraging / Scientific / Warm |

Customer's brief Q10 (preferred tone) overrides the default. Founder reviews at Gate 2 to confirm tone matches brief.

---

## What we never do

These are creative-direction red lines:

- **Manufactured scarcity** ("only 3 spots left!" when there aren't)
- **Income claims without disclaimers** ("make ₦5M this month" — illegal in most niches)
- **Health outcome claims** ("cures diabetes" — illegal across all health verticals)
- **Hate or divisive content** (no political alignment in commercial ads)
- **Cultural insensitivity** (no stereotyping of regions, tribes, religions)
- **Comparative attacks on competitors by name** (we mention "competitors" in the abstract)

These rules are enforced at Gate 0 (brief review) and Gate 2 (script review). The auto-evaluator pass between script generation and Gate 2 flags any of these for founder attention.

---

## Visual prompt formula (inherited from VG)

Every image prompt is constructed mechanically:

```
final_prompt = composition_prefix + ", " + scene_subject + ", " + style_dna + ", " + register_anchors
```

- `composition_prefix` — per-scene (e.g., "wide establishing shot, golden hour, ")
- `scene_subject` — what the LLM wrote about the scene's subject
- `style_dna` — locked at the order level: niche-specific recurring visual fingerprint
- `register_anchors` — from `production_registers.config.image_anchors`

The universal negative prompt is appended on every call:

```
text, watermark, logo, signature, low quality, blurry, distorted, deformed,
cropped, oversaturated, undersaturated, low contrast, bad anatomy, bad proportions,
extra limbs, mutated hands, poorly drawn hands, poorly drawn face,
out of frame, cluttered background, disfigured, ugly, gross proportions
```

Per-niche style DNA (held in the brief's metadata, customer-specific where available):
- Real estate: "warm afternoon light, architectural lines, aspirational interior, professional photography"
- Education: "soft natural light, clean modern study spaces, focus on hands and faces, intellectual atmosphere"
- Fashion: "vibrant colour palette, model focus, contemporary urban Lagos backdrop, fashion photography aesthetic"
- Fintech: "clean tech aesthetic, blue/cyan accents, smartphone/laptop integration, urban professional"
- Health: "natural greenery, soft daylight, wellness imagery, focus on calm gestures and healthy products"

---

## Cinema-lane positioning

We compete on **the documentary look**, not avatar-led production (per ADR 0013). Most of our competitors lean on avatar/UGC aesthetics; we lean on cinematic storytelling. This positions us as "the agency that makes ads that look like trailers, not TikToks."

When founder reviews at Gate 3 and a video looks too UGC-like (jagged motion, low-quality images, flat colour grade), it's regenerated. The brand promise is documentary-grade or better.

Avatar-led is offered only as a Creative Pod option for customers who specifically want it (B2C creators, founder-led brands). It's not our hero positioning.

---

## What good looks like

Founder-defined quality bar for paid orders, used as the Gate 3 review reference:

1. **Hook works.** First 3 seconds make the viewer want to keep watching.
2. **Captions sync.** No more than 100ms drift between audio and caption text.
3. **Images are coherent.** No floating limbs, no garbled text-in-image, no obvious "AI tells".
4. **Audio is balanced.** Voice clear over music, music doesn't dominate.
5. **CTA is specific.** Viewer knows exactly what to do next.
6. **Brand fits.** End card matches customer's brief, no generic placeholders.
7. **Pacing rewards mobile.** Each scene contributes — no holding shots that don't earn screen time.

When all 7 are met, the video ships. When 6 are met, founder regenerates the failing scene. When fewer than 6 are met, the video gets a full re-render from the script.
