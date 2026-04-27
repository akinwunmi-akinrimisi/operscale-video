# 0007. Paystack as the sole payment provider in v1

Date: 2026-04-21
Status: Accepted

## Context

We need to accept payments from Nigerian SMB customers. Three families of options:

1. **Paystack only.** Nigeria's most popular merchant payment processor. Card, bank transfer, Mobile Money. NGN-native. KYC-compliant. 1.5% + ₦100 (capped at ₦2000) per transaction. Webhook signature verification via HMAC-SHA512.
2. **Paystack + Flutterwave.** Both providers cover ~95% of Nigerian payment instruments. Some customer overlap but materially the same coverage. Doubles operational surface.
3. **International stack (Stripe / Wise / etc.).** Useful for diaspora customers paying USD. Adds complexity at the regulatory and accounting layer (NDPC, foreign-exchange).

Customer segment is Nigerian SMBs, NGN-native. Diaspora customers are < 5% expected at v1 and will pay via Paystack's bank-transfer rails or be quoted in NGN with a manual payment-link from the founder.

## Decision

**Paystack is the sole payment provider in v1.** All NGN amounts stored in kobo (1 NGN = 100 kobo). All charges processed through Paystack's checkout URL embedded in the quote email and WhatsApp message.

Concretely:
- `WF_OPS_PAYSTACK_WEBHOOK` receives Paystack's webhook POST, verifies HMAC-SHA512 against `PAYSTACK_SECRET_KEY` BEFORE JSON-parsing the body, then transitions `orders.pipeline_stage = 'paid'`
- `payments.paystack_tx_ref` has UNIQUE constraint for idempotency (Paystack does retry deliveries)
- Refunds via Paystack API (`WF_OPS_REFUND` workflow), founder-initiated through Notion gate-decision UI
- `PAYSTACK_SECRET_KEY` lives in `apps/agent/`'s container env vars, NOT in n8n credential store (because the verification happens server-side in the Next.js webhook proxy first, then the validated payload is forwarded to n8n)
- Test mode for Days 17-33 of implementation, live mode flipped on Day 34

## Consequences

**Saved:** integration cost of a second processor. About 5-7 days of engineering time avoided.

**Coverage adequate:** Paystack supports all major Nigerian payment instruments at our segment (card, bank-transfer, Mobile Money). We don't lose meaningful conversion vs. a multi-processor stack.

**Single point of failure.** If Paystack has a regional outage, we can't accept payment until it recovers. Mitigation: the customer's Paystack link works for 72 hours per order; outages are rare and recover within hours.

**No subscription billing.** All purchases are one-shot or invoice-based retainers. No automatic recurring charges. (Paystack supports recurring; we just don't use it. Decision deferred until retainer revenue justifies the integration.)

**Foreign-currency customers blocked.** USD or GBP payments are not supported in v1. Diaspora customers either pay via NGN bank transfer (manual) or get a custom-quote payment link.

**Webhook discipline is non-negotiable.** Skipping signature verification = anyone can fake a payment. The `paystack-integration` skill enforces the discipline; the `/operscale:paystack-verify` slash command generates the verification handler.

## Revisit conditions

Add a second processor when:
- Diaspora segment exceeds 10% of revenue (justify Stripe)
- Pan-African expansion planned (Flutterwave is stronger across Ghana, Kenya)
- Paystack outage exceeds 12 hours sustained AND we have customers waiting for a payment link in that window

## Reference

- [docs/specs/paystack-integration.md](../specs/paystack-integration.md) — implementation details.
- [security.md](../../security.md) §paystack-webhook-security.
- [skills.md](../../skills.md) §paystack-integration skill.
