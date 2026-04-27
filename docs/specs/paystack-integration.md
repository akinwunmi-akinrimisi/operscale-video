# Paystack Integration Spec

> The implementation contract for Paystack payment integration in Operscale Video Ads.

**Read alongside:** `security.md` §paystack-webhook-security, `customer-journey.md` §stage-7, ADR 0007.

---

## What this spec covers

- Webhook signature verification (HMAC-SHA512)
- Idempotency rules
- Refund flow
- Currency handling (NGN/kobo)
- Test vs live key separation

This spec does NOT cover Paystack account setup, which is a manual one-time task.

---

## Account setup

Akinwunmi already has a Paystack account for Operscale Systems. For Operscale Video Ads:

1. Create a sub-account or new account, depending on Paystack's policy — they may allow multiple businesses under one account
2. Configure webhook URL: `https://n8n.srv1297445.hstgr.cloud/webhook/operscale/paystack`
3. Note: Paystack signs webhook payloads with the account's secret key — same key used for API calls
4. Both test and live mode have separate keys

## Webhook flow

```
Customer pays via Paystack-hosted checkout
  ↓
Paystack POST to https://n8n.srv1297445.hstgr.cloud/webhook/operscale/paystack
  Headers: { 'X-Paystack-Signature': '<HMAC-SHA512 of raw body>' }
  ↓
n8n WF_OPS_PAYSTACK_WEBHOOK:
  1. Compute HMAC-SHA512(rawBody, PAYSTACK_SECRET_KEY)
  2. If signature mismatch: return 401, log to production_log, do nothing else
  3. Parse event
  4. If event = 'charge.success':
     a. INSERT INTO payments (customer_id, order_id, paystack_tx_ref, amount_kobo, status, webhook_payload)
        ON CONFLICT (paystack_tx_ref) DO NOTHING  ← idempotency
     b. UPDATE orders SET pipeline_stage = 'paid' WHERE id = order_id AND pipeline_stage = 'awaiting_payment'
        ← state-conditional update prevents double-progression
     c. INSERT INTO production_log (order_id, stage, action, details) — for audit
  5. If event = 'charge.failed': UPDATE payments to status = 'failed'
  6. Return 200 OK to Paystack
```

## Webhook signature verification (Next.js side, when we proxy through API route)

If we choose to handle the webhook in Next.js API route instead of directly in n8n:

```typescript
// apps/web/app/api/webhooks/paystack/route.ts
import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export async function POST(req: Request) {
  const rawBody = await req.text();
  const signature = req.headers.get('x-paystack-signature');
  
  if (!signature) {
    return new Response('Missing signature', { status: 401 });
  }
  
  const computedSignature = crypto
    .createHmac('sha512', process.env.PAYSTACK_SECRET_KEY!)
    .update(rawBody)
    .digest('hex');
    
  if (computedSignature !== signature) {
    // Critical: do NOT log the body — contains payment metadata
    console.error('Paystack signature mismatch');
    return new Response('Invalid signature', { status: 401 });
  }
  
  const event = JSON.parse(rawBody);
  
  if (event.event === 'charge.success') {
    const { reference, amount, customer, metadata } = event.data;
    
    // Idempotency via UNIQUE on paystack_tx_ref
    const { error: insertError } = await supabase
      .from('payments')
      .insert({
        order_id: metadata.order_id,
        customer_id: metadata.customer_id,
        paystack_tx_ref: reference,
        amount_kobo: amount,
        status: 'paid',
        webhook_payload: event,
        paid_at: new Date().toISOString(),
      });
    
    if (insertError && !insertError.message.includes('duplicate')) {
      console.error('Payments insert error:', insertError);
      return new Response('Internal error', { status: 500 });
    }
    
    // State-conditional update (idempotent across duplicate webhooks)
    await supabase
      .from('orders')
      .update({ pipeline_stage: 'paid' })
      .eq('id', metadata.order_id)
      .eq('pipeline_stage', 'awaiting_payment');
  }
  
  return new Response('OK', { status: 200 });
}
```

**Decision: handle webhook in n8n.** Per the architectural pattern of customer-flow webhooks living in n8n, not Next.js. The Next.js API route example above is for reference only.

## NGN/kobo conversion

Paystack works in kobo (1 NGN = 100 kobo). Our schema:

```sql
amount_paid_kobo INTEGER NOT NULL  -- in payments and orders tables
```

Display logic (Next.js):

```typescript
function formatNGN(kobo: number): string {
  return new Intl.NumberFormat('en-NG', {
    style: 'currency',
    currency: 'NGN',
    minimumFractionDigits: 0,
  }).format(kobo / 100);
}

formatNGN(7500000)   // "₦75,000"
formatNGN(17500000)  // "₦175,000"
formatNGN(35000000)  // "₦350,000"
```

Tier prices in kobo:
- Pilot: 7,500,000 kobo (₦75,000)
- Standard: 17,500,000 kobo (₦175,000)
- Creative Pod: 35,000,000 kobo (₦350,000) — first half is 17,500,000 kobo

## Initialise transaction (creating the payment link)

In `WF_OPS_QUOTE_DELIVER`, we initialise a Paystack transaction and embed the link:

```javascript
// n8n HTTP Request node
POST https://api.paystack.co/transaction/initialize
Headers: 
  Authorization: Bearer ={{ $env.PAYSTACK_SECRET_KEY }}
  Content-Type: application/json

Body:
{
  "email": "{{ $('Get Customer').item.json.email }}",
  "amount": {{ $('Get Order').item.json.amount_paid_kobo }},
  "currency": "NGN",
  "reference": "operscale-{{ $('Get Order').item.json.id }}-1",
  "metadata": {
    "order_id": "{{ $('Get Order').item.json.id }}",
    "customer_id": "{{ $('Get Customer').item.json.id }}",
    "tier": "{{ $('Get Order').item.json.tier }}",
    "is_first_half_creative_pod": false
  },
  "callback_url": "https://{{ $env.BRAND_DOMAIN }}/payment-success"
}
```

For Creative Pod 50/50 payment, two transactions are initialised: one at quote stage (50%), one at Gate 2 approval (50%).

## Refund flow

Triggered by founder approval at Gate 3 with `decision = 'refund'`, OR by direct customer support escalation.

```javascript
// WF_OPS_REFUND
POST https://api.paystack.co/refund
Headers:
  Authorization: Bearer ={{ $env.PAYSTACK_SECRET_KEY }}
  Content-Type: application/json

Body:
{
  "transaction": "{{ $('Get Payment').item.json.paystack_tx_ref }}",
  "amount": {{ $('Get Payment').item.json.amount_kobo }},
  "currency": "NGN",
  "merchant_note": "Refund for order {{ $('Get Order').item.json.id }} per customer request"
}
```

After Paystack confirms refund (asynchronous — settles in 5-10 business days):

```sql
UPDATE payments SET 
  status = 'refunded', 
  refunded_at = NOW(),
  refund_reason = $1
WHERE paystack_tx_ref = $2;

UPDATE orders SET pipeline_stage = 'refunded' WHERE id = $3;

INSERT INTO production_log (order_id, stage, action, details) 
VALUES ($3, 'refund', 'paystack_refund_initiated', $4);
```

## Test vs live keys

Both keys live in `/root/operscale_keys.env`:

```
PAYSTACK_PUBLIC_KEY_TEST=pk_test_...
PAYSTACK_SECRET_KEY_TEST=sk_test_...
PAYSTACK_PUBLIC_KEY_LIVE=pk_live_...
PAYSTACK_SECRET_KEY_LIVE=sk_live_...
```

Container env reads `PAYSTACK_PUBLIC_KEY` and `PAYSTACK_SECRET_KEY` (no `_LIVE`/`_TEST` suffix). The active set is selected via `docker-compose.override.yml`:

```yaml
# Test mode (Days 17-33):
- PAYSTACK_PUBLIC_KEY=${PAYSTACK_PUBLIC_KEY_TEST}
- PAYSTACK_SECRET_KEY=${PAYSTACK_SECRET_KEY_TEST}

# Live mode (Day 34+):
- PAYSTACK_PUBLIC_KEY=${PAYSTACK_PUBLIC_KEY_LIVE}
- PAYSTACK_SECRET_KEY=${PAYSTACK_SECRET_KEY_LIVE}
```

## Test cards

Per Paystack's [test docs](https://paystack.com/docs/payments/test-payments/):
- Card: `4084 0840 8408 4081`
- Expiry: any future date
- CVV: `408`
- PIN (when prompted): `0000`
- OTP (when prompted): `123456`

For test refunds, the test card behaviour mirrors live: a refund request transitions the payment to `refunded` after a delay (~30s in test mode, real settlement time in live mode).

## Failure modes

| Failure | Handling |
|---|---|
| Paystack returns rate-limit (429) on transaction init | `WF_RETRY_WRAPPER` exponential backoff |
| Webhook signature mismatch | Return 401, log to production_log, do not process |
| Duplicate webhook delivery (Paystack retries) | INSERT ON CONFLICT DO NOTHING via UNIQUE constraint on paystack_tx_ref |
| Customer pays but webhook fails to deliver | Paystack retries up to 5 times. After that, manual reconciliation: founder can query Paystack API for transaction status and POST manually to `/webhook/operscale/paystack/manual-reconcile` |
| Paystack outage | Customer can't pay; quote message says "Payment not working? Reply and we'll help" — manual bank-transfer fallback |
| Refund rejected by Paystack | Founder gets notified; manual decision: alternative refund method, or hold on refund until Paystack issue resolves |

## Audit and reporting

Daily query for finance reconciliation:

```sql
SELECT 
  DATE(paid_at) AS day,
  COUNT(*) AS num_paid,
  SUM(amount_kobo) / 100.0 AS total_ngn,
  COUNT(*) FILTER (WHERE status = 'refunded') AS num_refunded,
  SUM(amount_kobo) FILTER (WHERE status = 'refunded') / 100.0 AS refunded_ngn
FROM payments
WHERE paid_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(paid_at)
ORDER BY day DESC;
```

This reconciles against Paystack's dashboard daily. Discrepancy > 0.5% triggers investigation.

## Compliance notes

- Paystack handles PCI compliance. Card details NEVER touch our infrastructure.
- We store: Paystack transaction reference, amount, customer email, customer business name. NOT card numbers, NOT CVV.
- Refunds within 30 days of original transaction are straightforward via Paystack's API. Beyond 30 days, may require Paystack support contact.
- Per NDPC: customer email + business name retained per their order timeline; refund records retained for 7 years per Nigerian financial record-keeping requirements.
