# SleepLab Pattern Service (Cloudflare Workers)

Cloudflare Worker backend for SleepLab AI pattern analysis.

## What This Service Does
- Authenticates app installs using device keypair challenge/signature flow.
- Issues short-lived JWT access tokens.
- Accepts selected-day sleep/event/physiology payloads.
- Calls Gemini Flash and returns structured pattern insights.

## Endpoints
- `POST /v1/auth/challenge`
- `POST /v1/auth/exchange`
- `POST /v1/patterns/analyze` (Bearer token required)

## Prerequisites
- Node.js 20+
- Cloudflare account
- Wrangler CLI

## 1) Install
```bash
cd backend/pattern-service
npm install
```

## 2) Create KV namespace
```bash
npx wrangler kv namespace create INSTALL_KEYS
npx wrangler kv namespace create INSTALL_KEYS --preview
```

Copy IDs into `wrangler.toml`:
```toml
[[kv_namespaces]]
binding = "INSTALL_KEYS"
id = "<prod-id>"
preview_id = "<preview-id>"
```

## 3) Set secrets
```bash
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put JWT_SIGNING_SECRET
npx wrangler secret put CHALLENGE_SIGNING_SECRET
```

Optional model override:
```bash
npx wrangler secret put GEMINI_MODEL
```
Default model is `gemini-2.5-flash`.

# ////do from here next

## 4) Run locally
```bash
npm run dev
```

## 5) Deploy
```bash
npm run deploy
```

## Curl Examples

### Challenge
```bash
curl -X POST http://127.0.0.1:8787/v1/auth/challenge \
  -H "Content-Type: application/json" \
  -d '{"publicKey":"<base64-ed25519-public-key>"}'
```

### Exchange
```bash
curl -X POST http://127.0.0.1:8787/v1/auth/exchange \
  -H "Content-Type: application/json" \
  -d '{
    "installId":"<uuid>",
    "publicKey":"<base64-ed25519-public-key>",
    "challengeToken":"<challenge-token>",
    "signature":"<base64-signature-over-challenge-token>"
  }'
```

### Analyze
```bash
curl -X POST http://127.0.0.1:8787/v1/patterns/analyze \
  -H "Authorization: Bearer <access-token>" \
  -H "Content-Type: application/json" \
  -d '{"selectedDates":[/* payload */]}'
```

## Tests
```bash
npm run test
npm run typecheck
```

## Security Notes
- No static API keys in iOS app.
- JWT lifetime is short (15 minutes by default).
- Challenge token lifetime is short (5 minutes by default).
- KV stores only install key mapping (`installId -> publicKey`).
- Do not persist raw health payloads.
- Restrict endpoint with WAF/rate limits and rotate secrets regularly.

## Production Hardening Checklist
- Add IP rate limits at Cloudflare edge.
- Add request size limits.
- Add structured audit logging without payload contents.
- Add token revocation list for compromised install IDs.
- Add stricter claim checks (`aud`, `iss`) if you manage multiple apps.
