# REMLogic (SleepLab)

A privacy-first iOS sleep tracker that reads HealthKit data, visualizes sleep patterns, and optionally connects to an AI agent for conversational sleep analysis.

## Project Structure

```
sleep-app/
├── SleepLab/                        # iOS app (Swift, SwiftUI)
│   ├── App/                         # App entry point
│   ├── Models/                      # Data models (sleep, behavior)
│   ├── ViewModels/                  # View models + pattern analysis
│   ├── Views/                       # UI views
│   │   ├── Agent/                   # AI agent connection settings
│   │   ├── Comparison/              # Multi-day comparison
│   │   ├── Detail/                  # Day detail view
│   │   ├── Permission/              # HealthKit permission
│   │   ├── Shared/                  # Design system (SleepPalette)
│   │   ├── Tags/                    # Behavior event tags
│   │   └── Timeline/               # Main timeline
│   ├── Services/                    # HealthKit, CoreData, Agent sync
│   └── Resources/                   # Info.plist, assets
│
├── backend/pattern-service/         # Cloudflare Worker (TypeScript)
│   ├── src/
│   │   ├── auth/                    # JWT + API key auth
│   │   ├── routes/                  # API endpoints
│   │   ├── schema/                  # Zod validation schemas
│   │   ├── util/                    # HTTP helpers
│   │   ├── crypto.ts                # AES-256-GCM encryption
│   │   ├── config.ts                # Environment config
│   │   └── index.ts                 # Router
│   ├── migrations/                  # D1 SQL migrations
│   ├── skills/sleeplab-agent/       # OpenClaw agent skill
│   └── test/                        # Vitest tests
│
└── SleepLab.xcodeproj              # Xcode project
```

---

## iOS App Setup

### Requirements

- Xcode 15+
- iOS 17+
- Physical device (HealthKit not available on Simulator)

### Build & Run

1. Open `SleepLab.xcodeproj` in Xcode
2. Select your development team under **Signing & Capabilities**
3. Build and run on a physical device

### Configuration

The backend URL is configured in `SleepLab/Resources/Info.plist`:

```xml
<key>PATTERN_API_BASE_URL</key>
<string>https://sleeplab-pattern-service.adithya261004.workers.dev</string>
```

### HealthKit Permissions

The app requests read access to:
- Sleep Analysis
- Heart Rate
- Heart Rate Variability
- Respiratory Rate
- Workouts

On first launch, grant all requested permissions for complete sleep data.

---

## Backend Setup

### Requirements

- [Node.js](https://nodejs.org/) 18+
- [Bun](https://bun.sh/) (optional, for faster installs)
- Cloudflare account with Workers enabled

### Install Dependencies

```bash
cd backend/pattern-service
bun install    # or: npm install
```

### Environment Variables

The Worker needs these secrets:

| Variable | Purpose |
|---|---|
| `GEMINI_API_KEY` | Google Gemini API key for AI pattern analysis |
| `JWT_SIGNING_SECRET` | Secret for signing JWT tokens |
| `CHALLENGE_SIGNING_SECRET` | Secret for challenge-response auth |
| `ENCRYPTION_KEK` | 256-bit hex key for encrypting sleep data at rest |

### Local Development

1. Create a `.dev.vars` file in `backend/pattern-service/`:

```env
GEMINI_API_KEY=your_gemini_key
JWT_SIGNING_SECRET=your_jwt_secret
CHALLENGE_SIGNING_SECRET=your_challenge_secret
ENCRYPTION_KEK=your_64_char_hex_string
```

2. Start the dev server:

```bash
bun run dev
```

The Worker runs at `http://localhost:8787`.

### Run Tests

```bash
bun run test        # Run all tests
bun run typecheck   # TypeScript type checking
```

### Deploy to Cloudflare

#### 1. Create Resources

```bash
# Create D1 database
npx wrangler d1 create sleeplab-sleep-data

# Create KV namespaces
npx wrangler kv namespace create AGENT_KEYS
npx wrangler kv namespace create AGENT_KEYS --preview
```

#### 2. Update `wrangler.toml`

Replace the placeholder IDs with the real IDs from the commands above:

```toml
[[kv_namespaces]]
binding = "AGENT_KEYS"
id = "<your-kv-id>"
preview_id = "<your-kv-preview-id>"

[[d1_databases]]
binding = "SLEEP_DATA"
database_name = "sleeplab-sleep-data"
database_id = "<your-d1-database-id>"
```

#### 3. Set Secrets

```bash
# Generate and set the encryption key
openssl rand -hex 32  # copy the output

npx wrangler secret put ENCRYPTION_KEK          # paste the hex string
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put JWT_SIGNING_SECRET
npx wrangler secret put CHALLENGE_SIGNING_SECRET
```

#### 4. Apply Database Migration

```bash
npx wrangler d1 migrations apply sleeplab-sleep-data --remote
```

#### 5. Deploy

```bash
npx wrangler deploy
```

---

## AI Agent Integration

The app can connect to an AI agent (like OpenClaw) so you can ask questions about your sleep in natural language.

### How It Works

1. The iOS app syncs encrypted sleep data to the Cloudflare Worker
2. The Worker stores it in D1 (encrypted with AES-256-GCM)
3. Your AI agent queries the data via REST API using an API key
4. Only your agent can read your data — nobody else

### Connecting an Agent

#### In the App

1. Open the app → tap the **⚙ gear icon** in the toolbar
2. Toggle **Agent Access** on
3. Tap **Copy Connection Code**

#### In Your Agent

Paste the connection code into your agent's chat. If using the OpenClaw skill, the agent auto-configures itself.

For other agents, provide these instructions along with the code:

```
Use curl with Authorization: Bearer <api_key> to call:
- GET /v1/data/sleep?days=7       → recent sleep data
- GET /v1/data/sleep/YYYY-MM-DD   → specific day details
- GET /v1/data/sleep/range?from=YYYY-MM-DD&to=YYYY-MM-DD → date range
- GET /v1/data/sleep/stats?days=14 → aggregated averages
- GET /v1/data/events?days=7       → behavior logs
```

### OpenClaw Skill Setup

Copy the skill folder into your OpenClaw skills directory:

```bash
cp -r backend/pattern-service/skills/sleeplab-agent /path/to/openclaw/skills/
```

The skill includes:
- `SKILL.md` — agent instructions for parsing connection codes and calling endpoints
- `scripts/query.sh` — helper script for curl-based queries
- `.env.example` — config template

### Disconnecting

In the app settings, tap **Disconnect & Delete Data**. This:
- Revokes the API key
- Deletes all synced data from the server
- The agent can no longer access any data

---

## API Reference

### Auth Endpoints (iOS App → Worker)

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/v1/auth/challenge` | None | Start auth challenge |
| `POST` | `/v1/auth/exchange` | None | Exchange signed challenge for JWT |

### Agent Management (iOS App → Worker)

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/v1/agent/register` | JWT | Create API key + connection code |
| `DELETE` | `/v1/agent/revoke` | JWT | Revoke key + delete all data |

### Data Sync (iOS App → Worker)

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/v1/data/sync` | JWT | Sync encrypted sleep data |

### Data Query (Agent → Worker)

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/v1/data/sleep?days=N` | API Key | Last N days summaries (1–30) |
| `GET` | `/v1/data/sleep/:date` | API Key | Full detail for one day |
| `GET` | `/v1/data/sleep/range?from=&to=` | API Key | Date range query (inclusive) |
| `GET` | `/v1/data/sleep/stats?days=N` | API Key | Aggregated averages |
| `GET` | `/v1/data/events?days=N` | API Key | Behavior event logs |

### Pattern Analysis (iOS App → Worker)

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/v1/patterns/analyze` | JWT | AI-powered sleep pattern analysis |

---

## Security

- **Encryption at rest**: All sleep data in D1 is encrypted with AES-256-GCM
- **Key hierarchy**: A master KEK (Worker secret) wraps per-user DEKs
- **API keys**: Prefixed with `slk_` for easy identification, stored in KV
- **JWT auth**: Ed25519 challenge-response for iOS app ↔ Worker
- **Data isolation**: Per-install data separation via `installId`
- **Keychain storage**: API keys persist across app reinstalls via iOS Keychain

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS App | Swift, SwiftUI, HealthKit, CryptoKit |
| Backend | Cloudflare Workers, TypeScript |
| Database | Cloudflare D1 (SQLite) |
| Key-Value | Cloudflare KV |
| Encryption | Web Crypto API (AES-256-GCM, AES-KW) |
| AI | Google Gemini |
| Validation | Zod |
| Testing | Vitest |
