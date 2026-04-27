# Architecture

> The system shape of Operscale Video Ads, post-Vision-GridAI-fork decision.

**Read alongside:** `docs/VISION_GRIDAI_FORK_MANUAL.md` (the comprehensive fork strategy), `AGENT.md` (the LangGraph state machine), `deployment.md` (the runtime topology).

---

## The single picture

```
┌──────────────────────────────────────────────────────────────────────┐
│                       PUBLIC INTERNET (HTTPS)                        │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                          ┌───────────────┐
                          │    Traefik    │   (Hostinger-managed, port 443)
                          └───────┬───────┘
                                  │
       ┌──────────────────────────┼──────────────────────────────┐
       │                          │                              │
       ▼                          ▼                              ▼
┌──────────────┐         ┌────────────────┐           ┌──────────────────┐
│  Marketing   │         │   n8n editor   │           │  Supabase Kong   │
│  (Next.js)   │         │   + webhooks   │           │   gateway :8000  │
│ <brand>.com  │         │ n8n.srv….cloud │           │ supabase.…cloud  │
└──────┬───────┘         └────────┬───────┘           └─────────┬────────┘
       │                          │                              │
       │                          │             ┌────────────────┴───────┐
       │                          │             │                        │
       │                          │             ▼                        ▼
       │                          │     ┌─────────────┐         ┌────────────────┐
       │                          │     │ PostgREST   │         │  Realtime WSS  │
       │                          │     │ /rest/v1/*  │         │  /realtime/v1/* │
       │                          │     └──────┬──────┘         └────────┬───────┘
       │                          │            │                          │
       │                          │            └──────────┬───────────────┘
       │                          │                       │
       │                          │                       ▼
       │                          │              ┌─────────────────┐
       │                          │              │  Postgres       │
       │                          │              │  (Supabase)     │
       │                          │              │  shared with VG │
       │                          │              └─────────────────┘
       │                          │
       │                          ▼
       │              ┌─────────────────────────┐
       │              │   n8n container         │
       │              │   (n8n-n8n-1)           │
       │              │   shared with VG        │
       │              │                         │
       │              │   our workflows:        │
       │              │   WF_OPS_*  +  cloned   │
       │              │   VG render workflows   │
       │              └────────────┬────────────┘
       │                           │
       │       ┌───────────────────┼─────────────────────────┐
       │       │                   │                         │
       │       │                   │                         │
       │       ▼                   ▼                         ▼
       │  ┌─────────────┐    ┌──────────────────┐    ┌──────────────────┐
       │  │ External    │    │ Caption Burn     │    │ LangGraph        │
       │  │ APIs        │    │ Service :9998    │    │ agent container  │
       │  │             │    │ (host-side,      │    │ (operscale-      │
       │  │ • Anthropic │    │  not in Docker)  │    │  agent)          │
       │  │ • Google    │    │                  │    │                  │
       │  │   Cloud TTS │    │ docker exec n8n  │    │ Polls Supabase,  │
       │  │ • fal.ai    │    │ ffmpeg + libass  │    │ triggers n8n     │
       │  │   Seedream  │    │ + loudnorm       │    │ webhooks,        │
       │  │ • fal.ai    │    │                  │    │ writes orders    │
       │  │   Seedance  │    │ Shared with VG   │    └──────────────────┘
       │  │ • fal.ai    │    └──────────────────┘
       │  │   PlayHT    │
       │  │ • HeyGen    │
       │  │ • Vertex    │
       │  │   Lyria     │
       │  │ • Paystack  │
       │  │ • Resend    │
       │  │ • Evolution │
       │  │   API (WA)  │
       │  │ • Notion    │
       │  └─────────────┘
       │
       ▼
  Customer's browser
  (form, payment, video viewing)
```

---

## The two-product VPS

We run on **the same Hostinger KVM VPS as Vision GridAI**. The VPS hosts both products; they share Postgres, n8n, the caption burn service, and the JWT chain. They have separate containers for the new code (Next.js marketing site, LangGraph agent) and separate Supabase tables.

This is deliberate (per ADR 0004 and ADR 0008). Two reasons:
1. **Cost.** A second VPS would be $30–60/month for marginal isolation benefit during the launch period.
2. **Caption burn service is hard to duplicate.** It's host-side, listens on `:9998`, uses `docker exec` to reach n8n. Spinning up a second instance bound to a different port across two VPSs adds operational complexity for no win at our scale.

When sustained traffic justifies it (probably not within 90 days), we split: separate VPS, separate Supabase, separate n8n instance, our own caption burn service.

---

## What we inherit unchanged from Vision GridAI

The render core:
- `WF_TTS_AUDIO` — Google Cloud Chirp 3 HD per-scene TTS, master clock
- `WF_IMAGE_GENERATION` — fal.ai Seedream 4.5 portrait_9_16
- `WF_SCENE_*_PROCESSOR` — single-scene workers for retries
- `WF_SEEDANCE_I2V` — fal.ai Seedance 2.0 Fast (Creative Pod only)
- `WF_KEN_BURNS` — FFmpeg zoompan + 7 colour mood filter chains
- `WF_CAPTIONS_ASSEMBLY` — 47-node concat workflow with 3-layer crash prevention
- `WF_RETRY_WRAPPER` — exponential backoff sub-workflow used by every external API call
- `WF_ASSEMBLY_WATCHDOG` — cron monitoring stuck FFmpeg renders
- `WF_ENDCARD` + `WF_MUSIC_GENERATE` — Standard+ tier extensions
- The host-side `caption_burn_service.py` (port 9998), `generate_kinetic_ass.py`, `whisper_align.py`, `burn_captions.sh`

Webhook paths are namespaced with `/operscale/` to avoid collision with VG's running workflows. Workflow names are prefixed `OPS_` in n8n.

For the full inventory of what we keep vs delete, see fork manual §3.1 and §6.

---

## What we build new

The customer-facing layer that VG doesn't have:

### Marketing site (Next.js 15 in `operscale-web` container)
- Public landing page with three pricing tiers
- Multi-step intake form (15 questions)
- Resume-form-via-token mechanism for in-progress submissions
- Anonymous case-study pages at `/o/[order_id]`
- Paystack integration
- Terms of Service + Privacy Policy (NDPC-compliant)

### LangGraph agent (Python 3.11 in `operscale-agent` container)
- Listens for new orders via Supabase Realtime
- Generates angles + scripts via Claude Opus 4.7
- Triggers production workflows in n8n
- Listens for gate decisions via Realtime
- Triggers delivery after Gate 3 approval

See `AGENT.md` for the full state machine.

### New n8n workflows (`WF_OPS_*`)
Eight new workflows, all live in `workflows/operscale/`:

| Workflow | Purpose |
|---|---|
| `WF_OPS_INTAKE_RECEIVE` | Persist brief, fire auto-acknowledgement |
| `WF_OPS_PAYSTACK_WEBHOOK` | Verify HMAC-SHA512, transition order to `paid` |
| `WF_OPS_QUOTE_DELIVER` | Render rich quote email + WhatsApp |
| `WF_OPS_GATE_NOTIFY` | Push card to Notion gate-review DB |
| `WF_OPS_GATE_RESUME` | Notion automation → POST decision back to agent |
| `WF_OPS_DELIVERY_FANOUT` | Email + WhatsApp signed-URL delivery |
| `WF_OPS_REFUND` | Paystack refund API + DB update |
| `WF_OPS_AVATAR_QUALITY` | Photo quality auto-check at intake (Creative Pod) |

### New Supabase tables (12 tables, additive — VG schema untouched)
- `customers`, `briefs`, `orders`, `videos`, `scenes`, `production_log`
- `payments`, `gate_decisions`, `order_consent`, `llm_calls`
- `production_registers`, `prompt_configs`

VG's ~50 tables stay where they are. Our tables coexist in the same Postgres instance, separate concerns. The shared Supabase only matters for the JWT chain — when keys rotate, both products' apps must be updated.

For the full schema see `migrations/001_initial.sql` and fork manual §5.

### Notion gate-review database
The founder approves all gates via a Notion DB. Each gate creates a card with the relevant artefacts (brief, angles, script, render URL). A Notion automation POSTs the decision to `WF_OPS_GATE_RESUME` which writes to `gate_decisions` and the agent picks up via Realtime. See `docs/specs/notion-gate-review.md`.

---

## Trust boundaries (inherited from VG)

Three places where one component decides whether to trust another:

1. **Browser → n8n webhooks** — `Authorization: Bearer ${DASHBOARD_API_TOKEN}`. Same shared token Vision GridAI uses.
2. **Anything → Supabase** — Kong's `key-auth` plugin checks `apikey` (ANON) and JWT signed with `JWT_SECRET` (SERVICE_ROLE for server-to-server, ANON for read-only).
3. **n8n → external APIs** — n8n's encrypted credential store (in `~/.n8n/database.sqlite`).

For rotation procedures and the 4-sync-point JWT chain, see `security.md` and fork manual §10.

---

## Realtime data flow

Three places we use Supabase Realtime:

1. **Agent ← Supabase** — agent subscribes to `gate_decisions` and `videos` tables to know when human approvals land or renders complete. WSS via Kong.
2. **Founder dashboard ← Supabase** *(later, optional)* — when we eventually build a founder console (currently we use Notion), it'll subscribe to `orders.pipeline_stage` for live progress.
3. **Notion automation → us** — not Realtime; HTTP POST from Notion's automation engine into `WF_OPS_GATE_RESUME` webhook.

`REPLICA IDENTITY FULL` is set on every Realtime-published table or UPDATE events arrive without changed columns. Inherited rule from VG, do not skip.

---

## Failure isolation

Critical isolation properties:

| Failure | Effect on us | Mitigation |
|---|---|---|
| Vision GridAI ships a bug to a workflow we share | Could break our renders | We use prefixed `OPS_` copies of every shared workflow; never the `WF_X` directly |
| Vision GridAI's workflow runs consume all VPS CPU | Our renders slow down | Plan: KVM upgrade trigger at sustained 80% CPU |
| Caption burn service crashes | Both products' renders block | Host-level systemd auto-restart; founder gets paged |
| Supabase JWT rotation breaks | Both products' API calls fail | 4-sync-point checklist in `security.md` |
| Postgres OOMs | Everything stops | Plan: per-product DB at scale; for now, Postgres has 16 GB to itself |

---

## Why this architecture vs the alternatives

We considered three other shapes. Each is documented in an ADR:

- **ADR 0008: Greenfield (rejected)** — Building the render core from scratch would have taken 6+ months. Vision GridAI's stack is open, in our hands, and 235 commits past the bugs we'd otherwise re-discover.
- **ADR 0008: Forking VG vs share-via-API (chose fork)** — Sharing VG's render service via API would have created a vendor relationship with our other product, with all the version-skew risk that implies. Forking gives us control over the render pipeline as we evolve.
- **ADR 0016: Skip VG's React dashboard** — Vision GridAI has a beautiful 4-page React dashboard. We chose Notion-based gate review instead because (a) we're a 1-person ops team, (b) our gates need different fields, (c) Notion mobile is good enough for founder review on the move.

---

## What this architecture explicitly does not include

- **Customer self-service portal.** Customers email + WhatsApp us, see signed download URL in their inbox. No login, no dashboard, no profile page. ADR 0005.
- **Multi-tenant team accounts.** One customer = one email. No team / org / workspace concept. Could revisit at retainer scale (Phase 4+).
- **Public API for partners.** No third-party integrations exposed. Our Paystack webhook is the only inbound API.
- **Custom-built analytics on customer ad performance.** That's the customer's job. We deliver the file; they post; they own performance data.
- **Subscription billing.** All purchases are one-shot (Pilot/Standard/Creative Pod) or invoice-based retainers (Momentum/Velocity). No automatic recurring charges via Paystack.
- **A separate KMS for secrets.** Secrets live in `keys_new.env` (chmod 600), Docker compose env, and n8n's encrypted credential store. Adequate for our scale; revisit at $1M+ ARR.

---

## When this architecture changes

Track these triggers and re-baseline:

- **Day 30:** Are all VG inheritances behaving? Is the JWT chain stable? Is the caption burn service handling our load?
- **Day 60:** First paying customer. Is `gate_decisions` Realtime working reliably? Are renders completing within tier SLAs?
- **Day 90:** Sustained 3+ orders/day. Should we split the VPS? Is Postgres still happy on shared infrastructure?
- **Day 180:** ₦5M+ MRR. Time to spin out: own VPS, own Supabase, own n8n, own caption burn service. Notion can stay (or upgrade to a custom founder console).
