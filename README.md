# Operscale AI Video Ads

**Productised AI video ad agency for Nigerian SMBs.** End-to-end automated intake → script → production → delivery with human approval gates at each major step.

- **Brand:** Operscale (sub-offering)
- **Market:** Nigeria-first, SMB segment
- **Pricing:** ₦75K (Pilot) / ₦175K (Standard) / ₦350K (Creative Pod) / ₦600K-1.2M monthly retainers
- **Unit cost:** ~$6-8/video via Vision GridAI pipeline
- **Capacity:** 90 videos/day (shared with Vision GridAI)

---

## Repository Structure

```
operscale-video-ads/
├── apps/
│   ├── web/              # Next.js 15 + TypeScript site + landing + Paystack
│   ├── agent/            # LangGraph intake agent (Python, Claude Opus 4.7)
│   └── n8n-workflows/    # Delivery automation (render queue, publishing)
├── packages/
│   └── shared/           # Shared types, schemas, prompt templates
├── infra/                # Docker Compose, nginx configs, deployment scripts
├── docs/
│   ├── adr/              # Architecture Decision Records
│   ├── diagrams/         # Mermaid + PNG architecture diagrams
│   └── (all .md files below)
├── AGENT.md              # Intake agent architecture + state machine
├── CLAUDE.md             # Claude Code rules for this repo
├── skills.md              # Custom Superpowers skills for this project
├── skills.sh             # Skill installation script
├── README.md             # This file
├── architecture.md       # System architecture overview
├── security.md           # Secrets, RLS, webhooks, fraud prevention
├── implementation.md     # Phased build plan (day-by-day)
├── deployment.md         # VPS deployment + resource quotas
├── customer-journey.md   # End-to-end funnel flow
├── pricing-and-packages.md
├── gates-and-approvals.md
├── content-bank-playbook.md
├── ad-creative-playbook.md
└── niche-briefs/         # Per-niche briefs (real estate, fintech, etc.)
```

---

## Quick Start (for Claude Code sessions)

1. **Read `CLAUDE.md` first.** It defines how to work in this repo.
2. **Read `skills.md` and run `skills.sh`** to install project skills.
3. **For any task, find the relevant doc first:**
    - Building agent logic → `AGENT.md`
    - Building UI → `architecture.md` § Web, plus Anthropic `frontend-design` skill
    - Deploying → `deployment.md`
    - Security question → `security.md`
    - Customer flow question → `customer-journey.md`
4. **Use Superpowers for all new work.** gstack only for `/qa`, `/browse`, `/careful`, `/freeze`, `/review`.

---

## The 30-Second Mental Model

A Nigerian SMB sees a video ad on Meta/TikTok produced from our Phase 1 content bank → clicks → lands on `/` → hits "DM for a sample" (primary) or "Start a brief" (secondary) → agent qualifies on WhatsApp → brief form → Claude Opus 4.7 analyses → enriched-summary email with Paystack link → payment → deeper analysis → script draft (Gate 1: **founder approval**) → Vision GridAI renders → QA (Gate 2: **founder approval**) → delivery email + WhatsApp → anonymised case study auto-published (Gate 3: **founder approval**).

Revenue target (realistic): 1-3 sales/day by day 90 = ₦5M-15M/month at ~94% gross margin.

---

## What This Repo Is Not

- **Not a CMS.** Customers get email + WhatsApp only. No portal at v1.
- **Not the video renderer.** Vision GridAI is the upstream dependency. We submit render jobs; we don't build pipelines here.
- **Not John (sales agent).** Different repo, different purpose. John is voice/Retell; this is chat/WhatsApp/email.
- **Not a general SaaS.** Every decision optimises for "founder-operated, 1-3 sales/day, Nigerian SMB."

---

## Key Docs (Ranked by Read Priority for New Contributors)

1. `CLAUDE.md` — working rules
2. `architecture.md` — how it all fits together
3. `AGENT.md` — the brain of the system
4. `customer-journey.md` — what the customer actually experiences
5. `gates-and-approvals.md` — where human judgement gets applied
6. `security.md` — before touching any secret or webhook
7. `implementation.md` — build phases and acceptance criteria
8. Remaining docs — read as needed

---

## Status

**Phase:** Pre-launch (Week 0)
**Next milestone:** Content bank build (90 videos across 5 niches by day 30)
**See:** `implementation.md` for week-by-week plan

---

*Last updated: 2026-04-21*
