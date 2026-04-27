# 0005. Email and WhatsApp only; no customer portal in v1

Date: 2026-04-21
Status: Accepted

## Context

After payment, the customer needs to:
- See their quote and Paystack payment link
- Receive their final video file (or signed URL)
- Receive any clarifying messages from us during production
- Optionally: see status of their order in flight

Three options for the customer-facing surface:

1. **Email + WhatsApp only.** No login, no dashboard. All communication via Resend (email) and Evolution API (WhatsApp Business). Customer receives signed Supabase Storage URL valid 7 days.
2. **Lightweight customer portal.** Magic-link login at `app.plovera.shop`. Order status, download, message history. Single page — no profile, no billing UI.
3. **Full customer portal.** Account, multi-order history, brand asset management, retainer subscription UI.

Nigerian SMB segment behaviour: WhatsApp is the dominant channel for B2B vendor communication. Email is universal and acceptable for transactional content (receipts, downloads). Neither requires a learnable UI.

## Decision

**Email + WhatsApp only for v1. No portal at any depth.**

Concretely:
- Quote email rendered by `WF_OPS_QUOTE_DELIVER` via Resend, with embedded Paystack link
- WhatsApp message rendered by the same workflow via Evolution API, shorter copy + same link
- Delivery email (`WF_OPS_DELIVERY_FANOUT`) carries the 7-day signed Supabase Storage URL + receipt PDF
- Delivery WhatsApp carries the URL + a one-line message
- Founder communicates ad-hoc with customers via WhatsApp directly (no in-product chat)
- 7-day post-delivery follow-up email scheduled via n8n cron

## Consequences

**Saved:** roughly 2-3 weeks of build time on a portal that wouldn't move conversion or retention numbers in our segment.

**Mobile-first by default.** WhatsApp on phone, Resend email on phone. No responsive web UI to maintain.

**Customer can lose access to the URL.** Mitigation: signed URL valid 7 days, customer can request a re-issue via WhatsApp. After 7 days, founder regenerates.

**No order-status visibility for the customer.** They get the milestone notifications (acknowledgement, paid, in-production, ready-for-review, delivered) via WhatsApp + email. They don't see "Stage 4 of 8" in real time. Acceptable: our SLAs are 36-72h, not 36-72 minutes. A status page would mostly say "We're working on it" anyway.

**Trade-off accepted:** if a customer wants to see *all* their past orders in one place, they have to dig through WhatsApp history. Acceptable for v1. Revisit at retainer scale.

**Anonymous case study pages exist** at `plovera.shop/o/[order_id]` for marketing — but these are public pages indexed for SEO, not customer-only views. Customers see them too but they're not authenticated.

## Revisit conditions

Build a portal when:
- Customers request order history surface in 5+ instances within a 30-day window
- Retainer customers (₦600K+/month) sign up — they have multiple parallel orders worth a single-pane-of-glass view
- A second reviewer is hired and needs a per-customer view distinct from the founder's Notion gate-review surface

## Reference

- [customer-journey.md](../../customer-journey.md): full customer touchpoint flow.
- [architecture.md](../../architecture.md) §what-this-architecture-explicitly-does-not-include.
