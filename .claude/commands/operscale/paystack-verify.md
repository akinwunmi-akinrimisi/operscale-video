Generate Paystack webhook signature verification code for the target language.

Input: language (typescript | python)
Output: handler that:
  1. Reads raw request body BEFORE any JSON parsing (parsing changes whitespace and breaks HMAC)
  2. Computes HMAC-SHA512 with PAYSTACK_SECRET_KEY
  3. Compares using constant-time comparison (crypto.timingSafeEqual / hmac.compare_digest)
  4. Returns 401 on mismatch with no body (don't leak signature info)
  5. On success, parses body and proceeds to event processing

Reminder: PAYSTACK_SECRET_KEY lives in apps/agent env vars, NOT in n8n credentials.
