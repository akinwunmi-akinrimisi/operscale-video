# Security

> Security boundaries, secrets handling, and inherited security disciplines for Operscale Video Ads.

**Read alongside:** `docs/VISION_GRIDAI_FORK_MANUAL.md` §10 (auth + secrets), `deployment.md`, `architecture.md`.

---

## Trust model — three boundaries inherited from Vision GridAI

The platform has three places where one component decides whether to trust another:

### Boundary 1: Browser → n8n webhooks

**Mechanism:** `Authorization: Bearer ${DASHBOARD_API_TOKEN}` header.

**Where the token lives:**
- `/docker/n8n/docker-compose.override.yml` env var (n8n container)
- `/opt/dashboard/.env` (VG's React dashboard)
- `/docker/operscale-video-ads/docker-compose.override.yml` (our `operscale-web` and `operscale-agent` containers)
- An n8n credential entry, ID `KtMyWD7uJJBZYLjt` (httpHeaderAuth type)

**The single shared token across both products is intentional.** Our workflows live in the same n8n instance as VG's, so a single shared bearer simplifies operations. See fork manual §10.2.

**The missing-`=` expression trap (READ THIS):**

n8n string parameters that begin with `=` evaluate as expressions. Without the `=`, the literal `{{ $env.DASHBOARD_API_TOKEN }}` is sent over the wire and the receiving endpoint rejects it.

A 17-node sweep across `WF_SUPERVISOR` (11 nodes) and `WF_ANALYTICS_CRON` (6 nodes) had been failing silently this way **for ~30 days** before VG Session 38 caught it. The workflows ran without errors; the operations just never completed.

In every webhook-triggered node we import or write, the Authorization header value MUST be:

```
={{ $env.DASHBOARD_API_TOKEN }}    ← correct (note the leading `=`)
```

NOT:

```
{{ $env.DASHBOARD_API_TOKEN }}    ← WRONG, sends literal text
```

**Lint rule `AUTH-01`** (in `tools/lint_n8n_workflows.py`, ported from VG) fails CI when an `Authorization` header value contains `{{` but does not start with `=`. Do not disable this rule.

### Boundary 2: Anything → Supabase (PostgREST + Realtime)

**Mechanism:** Kong gateway with `key-auth` plugin.

- `/rest/v1/*` routes require `apikey` header (ANON for read-only) plus `Authorization: Bearer <SERVICE_ROLE_JWT>` for server-to-server writes
- `/realtime/v1/*` (WSS) requires JWT in the WSS subprotocol

**RLS lockdown:** Per VG migration 030 + our migration 001, every Operscale table carries:
- `RESTRICTIVE FOR anon DENY` policy
- `PERMISSIVE FOR service_role` policy

Anon role is blocked at the policy layer **and** revoked at the GRANT layer. Browser clients NEVER read Operscale data directly — Next.js API routes proxy through service-role on the server side.

### Boundary 3: n8n → external APIs

**Mechanism:** n8n's encrypted credential store at `~/.n8n/database.sqlite` inside the `n8n-n8n-1` container, encrypted with `N8N_ENCRYPTION_KEY`.

Workflow JSONs reference credentials by ID. The secret never appears in the JSON.

**Lint rule `CRED-01`** blocks PRs that add an HTTP node bound to an inline `Authorization` header where a stored credential should be used. Do not bypass.

Credential types in use:
- `httpHeaderAuth` — Anthropic, Fal.ai, HeyGen, Paystack, Resend, Notion
- `supabaseApi` — Supabase service-role connection
- `googleCloud` — Google Cloud TTS, Vertex AI Lyria
- `googleDriveOAuth2Api` — currently unused (our delivery is Supabase Storage signed URLs)

---

## Supabase JWT chain — the 5 sync points

The single secret that signs every Supabase token is `JWT_SECRET` in `/docker/supabase/.env`. From there, **five** downstream copies must stay in sync.

| # | Location | What | After rotation |
|---|---|---|---|
| 1 | `/docker/n8n/docker-compose.override.yml` | `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` env vars | Replace, restart n8n stack |
| 2 | `_realtime.tenants.jwt_secret` (DB rows × 2) | Per-tenant secret for Realtime | `UPDATE _realtime.tenants SET jwt_secret = '<NEW>' WHERE name IN ('realtime', 'realtime-dev')` |
| 3 | `/docker/supabase/supabase/kong.yml` | Kong consumer credentials | Replace + `docker exec supabase-kong-1 kong reload` |
| 4 | `dashboard/.env` + `/opt/dashboard/.env` | VG dashboard `VITE_SUPABASE_ANON_KEY` | Replace + rebuild + redeploy |
| 5 | **`/docker/operscale-video-ads/docker-compose.override.yml`** | Our `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Replace + `cd /docker/operscale-video-ads && docker compose up -d` |

Skipping any one produces a different silent failure mode:

| Skipped | Symptom |
|---|---|
| #1 | n8n HTTP requests to PostgREST get `JWSError JWSInvalidSignature` |
| #2 | Dashboard or agent's WSS subscription connects but immediately gets `401 jwt invalid` |
| #3 | Kong serves cached old keys; the new ones are rejected even though `kong.yml` has them |
| #4 | VG dashboard reads cached tokens from the prior build |
| #5 | Our containers can't read/write Supabase; agent stops processing orders |

A typical rotation takes ~5 minutes when followed in order. A rotation that misses one step typically isn't detected for hours/days because the failures are silent at most layers.

For the full rotation playbook, see fork manual §10.4 + VG's [Auth + Secrets doc](https://akinwunmi-akinrimisi.github.io/vision-gridai-platform/infrastructure/auth-secrets/).

---

## Secrets inventory

### Shared with Vision GridAI (do not rotate without coordinating)

| Secret | Where | Rotation owner |
|---|---|---|
| `JWT_SECRET` | `/docker/supabase/.env` | Both products |
| `DASHBOARD_API_TOKEN` | `/docker/n8n/docker-compose.override.yml` | Both products |
| `N8N_ENCRYPTION_KEY` | `/docker/n8n/docker-compose.override.yml` | Both products |
| `POSTGRES_PASSWORD` | `/docker/supabase/.env` | Both products |

### Operscale-only

| Secret | Where | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | `/root/operscale_keys.env` | Tier with rate limits per Anthropic |
| `PAYSTACK_PUBLIC_KEY` | `/root/operscale_keys.env` | OK to expose to browser |
| `PAYSTACK_SECRET_KEY` | `/root/operscale_keys.env` | Server-side only, never expose |
| `FAL_KEY` | `/root/operscale_keys.env` | Used for both image gen + voice cloning |
| `HEYGEN_API_KEY` | `/root/operscale_keys.env` | Phase 3+ |
| `RESEND_API_KEY` | `/root/operscale_keys.env` | Email delivery |
| `EVOLUTION_API_KEY` | `/root/operscale_keys.env` | WhatsApp delivery |
| `NOTION_API_KEY` | `/root/operscale_keys.env` | Gate review automation |
| `GCP_TTS_CREDENTIALS_JSON` | `/root/operscale_keys.env` | Service account JSON, base64-encoded |
| `BACKBLAZE_KEY_ID`, `BACKBLAZE_APPLICATION_KEY` | `/root/operscale_keys.env` | Backups |

All Operscale secrets in a single file (`/root/operscale_keys.env`), `chmod 600`, root-only. Never committed to git. `.gitignore` blocks `*.env` and `docker-compose.override.yml`.

---

## Customer photo consent (Creative Pod custom avatar)

When a Creative Pod customer chooses avatar-led production with their own face, we collect a photo. This creates real legal obligations.

### Required at intake

1. **Explicit consent checkbox** in the form: "I confirm I own the rights to this image and have permission from any person depicted, and I authorise plovera to render derivative video using this image."
2. **Indemnification clause** in our Terms of Service: customer indemnifies us for any third-party rights claim related to images they upload.
3. **Logged consent record** in the `order_consent` table with `consent_text_signed`, `signed_at`, `ip_address`.

### Photo handling

- **Storage:** Supabase Storage bucket `customer-photos`, RLS-locked (only service_role can read).
- **Retention:** 90 days post-delivery for repeat-customer convenience, then deleted. Beyond 90 days, customer re-uploads.
- **Access logging:** Every read of a customer photo writes a row to `production_log` with the access reason.

### NDPC compliance (Nigeria Data Protection Commission)

- Customers' email + WhatsApp + business name are PII; storage is encrypted at rest.
- Right to erasure honoured: a customer email asking us to delete their data triggers a manual workflow that drops their `customers`, `briefs`, `orders`, `payments`, `order_consent` rows after 30-day grace period.
- Privacy Policy at `/legal/privacy` discloses data collected, retention periods, third-party processors (Anthropic, Paystack, fal.ai, HeyGen, Resend, Evolution API, Google Cloud, Hostinger).
- Annual NDPC compliance audit by Akinwunmi (or delegated to a compliance contractor at scale).

---

## Inherited security disciplines

These exist because Vision GridAI's 2026-04-21 security audit uncovered specific issues. We inherit the fixes:

### 1. `caption_highlight_word` shell injection guard

VG migration 031 added a CHECK constraint:

```sql
CHECK (caption_highlight_word IS NULL
       OR caption_highlight_word !~ '[`$|;<>&\\]')
```

The column is rendered into FFmpeg subtitle filter strings; user input could break out without this. We inherit this constraint in `migrations/001_initial.sql`.

### 2. RLS lockdown on every public table

Per VG migrations 030+031. All Operscale tables enable RLS with restrictive anon-deny + permissive service-role policies. See `migrations/001_initial.sql`.

### 3. JWT exp default = 1 year (not 2099)

Old VG keys had `exp` in 2099 — effectively immortal. Our key generation defaults `exp` to 1 year ahead. Annual rotation is calendar-scheduled.

### 4. Linter rules in CI

`tools/lint_n8n_workflows.py` ported from VG. Two enforced rules:

- `AUTH-01`: Authorization header value with `{{` MUST start with `=`
- `CRED-01`: HTTP nodes with inline Authorization headers MUST use stored credentials instead

### 5. Per-rotation backup discipline

Every rotation writes a timestamped bundle to `/root/backups/operscale-deploy-YYYYMMDDTHHMMSSZ/` containing the JSONs/configs that were modified. This enables atomic rollback within minutes if a rotation breaks something.

---

## Paystack webhook security

Every Paystack webhook MUST pass HMAC-SHA512 signature verification before any side effect:

```typescript
import crypto from 'crypto';

export async function POST(req: Request) {
  const rawBody = await req.text();
  const signature = req.headers.get('x-paystack-signature');
  
  const computedSignature = crypto
    .createHmac('sha512', process.env.PAYSTACK_SECRET_KEY!)
    .update(rawBody)
    .digest('hex');
    
  if (computedSignature !== signature) {
    // CRITICAL: do NOT log the body — it contains payment metadata
    return new Response('Invalid signature', { status: 401 });
  }
  
  // ... process verified webhook
}
```

Skipping signature verification means anyone with a Paystack webhook URL can fake a payment and trigger a render. Paystack's documentation provides test signatures; verify your implementation against them.

**Idempotency:** `payments.paystack_tx_ref` has a UNIQUE constraint. Duplicate webhook deliveries from Paystack (which happen) are no-ops at the DB layer.

---

## Rate limiting

| Surface | Limit | Mechanism |
|---|---|---|
| `/api/intake/submit` | 10/IP/hour | Next.js middleware with Redis (or in-memory for v1) |
| `/api/webhooks/paystack` | none (Paystack signs requests; signature verification is sufficient) | n/a |
| `/api/save-token/[token]` (form resume) | 30/IP/hour | Next.js middleware |
| External outbound APIs | per-provider, handled by `WF_RETRY_WRAPPER` | Exponential backoff 1s→2s→4s→8s, 4 attempts max |

---

## Threat model — what we're not protecting against

We are deliberately NOT defending against:

- **Targeted state-actor attacks.** Out of scope for an SMB ad agency.
- **DDoS at the network layer.** Cloudflare Pro at the edge would help; we accept this risk for now.
- **Sophisticated phishing of Akinwunmi's personal accounts.** Standard 2FA + password manager hygiene.
- **Insider threats from team members with admin access.** Trust-based; will revisit when team grows beyond 3 people.

We ARE defending against:

- **Credential leakage** (via lint rules, encrypted credential stores, env file permissions)
- **Spoofed webhooks** (via signature verification on Paystack)
- **Public access to customer data** (via RLS lockdown)
- **Shell injection via user-supplied values** (via CHECK constraints + parameterised queries)
- **Stale JWTs after rotation** (via the 5-sync-point checklist)

---

## Incident response

If a security issue is discovered:

1. **Stop the bleeding.** Disable the affected endpoint or feature flag.
2. **Capture state.** `mkdir -p /root/backups/incident-$(date +%Y%m%d-%H%M%S)/` and copy relevant configs.
3. **Notify if customer data may be involved.** Email affected customers within 24 hours per NDPC.
4. **Patch.** Write the fix, test in staging, deploy.
5. **Post-mortem.** Document in `docs/incidents/YYYY-MM-DD-<short-name>.md` per VG pattern.
6. **Update lint rules or add new ones** so the same class of bug can't recur.

---

## Quarterly review

Calendar reminder set for every 3 months:

- Rotate JWT secret (5 sync points)
- Rotate `DASHBOARD_API_TOKEN`
- Audit `/root/operscale_keys.env` for unused keys (clean up)
- Re-run linters across all workflows
- Test backup restore on a clean VPS
- Verify Privacy Policy is current
