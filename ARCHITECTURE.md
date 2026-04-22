# EquiEdge — Full Architecture

## System Overview

EquiEdge is an AI-powered horse racing analysis platform combining FormFav Pro data, Grok AI handicapping, Betfair Exchange market data, and TAB live odds. It consists of three main components:

1. **iOS App** — SwiftUI + SwiftData client (race browsing, bet tracking, subscription management)
2. **Backend** — Express.js server deployed on both Vercel (edge, 300s) and AWS Lambda (heavy jobs, 900s)
3. **Weekly Results Automation** — Cron-triggered pipeline that compiles metro selections, resolves via Betfair SP, and publishes P/L reports

---

## Repository Structure

```
equiedge-scraper/
├── EquiEdge/                      # iOS Xcode project
│   ├── EquiEdge/                  # App source (.swift files)
│   ├── EquiEdge.xcodeproj/
│   ├── EquiEdgeTests/
│   └── EquiEdgeUITests/
├── betfair/                       # Betfair Exchange integration
│   ├── auth.js                    # Certificate-based login, session cache
│   ├── client.js                  # JSON-RPC wrapper for Betting API
│   ├── markets.js                 # Meeting/market catalogue fetching
│   ├── matching.js                # FormFav <-> Betfair name reconciliation
│   └── overrides.json             # Manual track/horse name overrides
├── lib/                           # Shared business logic
│   ├── email.js                   # Resend email + HMAC token generation
│   ├── resultsBuilder.js          # Draft bundle builder with P/L calculation
│   └── results/
│       ├── selections.js          # Metro selection loader from Redis
│       └── betfairResults.js      # Betfair SP resolution for settled races
├── public/                        # Static files (served by Vercel)
│   ├── results.html               # Public weekly results page
│   └── admin/
│       └── results-review.html    # Admin review/approve UI
├── server.js                      # Express.js app (2,170 lines)
├── lambda.js                      # Serverless Express handler
├── template.yaml                  # SAM/CloudFormation (Lambda config)
├── vercel.json                    # Vercel routing, crons, builds
├── package.json                   # Dependencies
└── samconfig.toml                 # SAM deployment config
```

---

## iOS App

### Entry Point & Singletons

`EquiEdgeApp.swift` initialises four `@Observable` singletons and a SwiftData `ModelContainer`:

| Singleton | Purpose |
|---|---|
| `AuthManager.shared` | Sign In with Apple, Keychain token persistence |
| `SubscriptionManager.shared` | StoreKit 2 products, tier checks, backend sync |
| `DataService.shared` | API calls, race cache, TAB integration |
| `TrackSelection.shared` | Selected racetracks (UserDefaults) |

SwiftData stores a single `@Model`: `BetRecord` (SQLite). Race data is cached as JSON files, not in SwiftData.

### Navigation

Root view switches on `authManager.isSignedIn`:
- **Signed out** → `SignInView` (Sign In with Apple + feature cards)
- **Signed in** → `ContentView` (4-tab bar)

**Tabs:**
1. **Races** (flag.checkered) → `TodayRacesView` — Browse races, trigger AI analysis
2. **Bets** (target) → `MyBetsView` — Track placed bets, auto-settle via TAB
3. **Stats** (chart.line) → `PerformanceView` — P/L analytics
4. **Settings** (gearshape) → `SettingsView` — Account, subscription, track selector, unit size

Each tab maintains its own `NavigationPath`. Tab reselect pops to root.

### Key Views

| View | Purpose |
|---|---|
| `TodayRacesView` | Race list, date nav, AI analysis trigger, subscription gating |
| `RaceDetailView` | Race header, AI suggestions, runner field, bet logging |
| `RunnerDetailView` | Full Pro data (speed map, class profile, ML prediction, badges) |
| `GrokSelectionsView` | Browse all AI picks across tracks |
| `MyBetsView` | Bet tracking with auto result checking (Active/Pending Win/Settled) |
| `TrackSelectorView` | 234+ tracks, Metro/Provincial/Country classification, state groups |
| `PaywallView` | Basic vs Pro tier, monthly/annual toggle, purchase flow |
| `SignInView` | Auth landing with feature cards and Sign In with Apple |
| `SettingsView` | Account, subscription status, unit size slider, track selector |

### Data Models

**Race** (Codable, in-memory):
- Core: `id`, `date`, `track`, `raceNumber`, `distance`, `condition`, `weather`
- Collections: `runners: [Runner]`, `suggestions: [BetSuggestion]`
- Pro: `paceScenario`, `raceClass`, `raceName`, `raceStartTime`
- Analysis: `aiAnalysis` (Grok output text)

**Runner** (Codable):
- Core: `number`, `name`, `jockey`, `trainer`, `weight`, `barrier`, `form`
- Stats: `stats: RunnerStats` (overall, track, distance, condition, firstUp, secondUp)
- Pro: `age`, `claim`, `scratched`, `decorators: [FormBadge]`, `speedMap`, `classProfile`, `raceClassFit`, `prediction`

**BetSuggestion** (Codable):
- AI output: `horseName`, `confidence` (60-100), `units`, `reason`
- Odds: `fixedWinOdds` (from TAB)
- Pro: `paceAssessment`, `classAssessment`, `mlModelRank`, `mlWinProb`, `keyBadges`

**BetRecord** (SwiftData `@Model`):
- `raceInfo` ("TRACK R#"), `horseName`, `units`, `amount`, `confidence`, `reason`
- `result` (nil/Won/Lost/Pending Win), `odds`, `profit`, `date`

**Pro Structs** (Codable):
- `FormBadge` — type, label, sentiment (+/-/gray)
- `SpeedMap` — runningStyle (L/P/M/B/X), earlySpeedIndex, settlingPosition
- `ClassProfile` — currentRating, peakRating, highestClassWon, optimalRange, trend
- `RaceClassFit` — classDifference, withinOptimalRange, assessment
- `RacePrediction` — winProb, placeProb, modelRank

### Authentication (AuthManager)

1. User taps Sign In with Apple
2. OS returns `identityToken` (JWT) + `userIdentifier`
3. `POST /api/auth/apple { identityToken, userIdentifier }` → backend validates JWT
4. Store `userId`, `authToken`, `email` in Keychain (`com.equiedge.app`)
5. On app launch, restore from Keychain → `isSignedIn = true`

### Subscriptions (SubscriptionManager)

**Tiers:** expired (0) → trial (1) → basic (2) → pro (3)

**StoreKit 2 Products:**
- `EquiEdge.basic.monthly`, `equiedge.basic.annual`
- `equiedge.pro.monthly`, `equiedge.pro.annual`

**Backend Sync:**
- `GET /api/user/status` → tier, trackDaysUsedThisWeek, limits, trial info
- `POST /api/user/record-usage` → increment usage after each scrape
- Local StoreKit entitlements as fallback when S2S notifications delayed

**Limits:**
- Trial: 3 track-day uses, 3-day window
- Basic: 10 track-days/week (re-runs on same track-day are free)
- Pro: Unlimited

### Race Data & Caching (DataService)

**API Base:** `https://ghavmqa2tz5daqvb7ooj7qqk5u0xdcbm.lambda-url.ap-southeast-2.on.aws`

**Endpoints Called:**
- `GET /warm-stats?tracks=...` — Pre-cache jockey/trainer stats
- `GET /scrape-now?tracks=...&ai=true` — Trigger FormFav + Grok analysis
- `GET /today-races` — Fetch latest race data
- `GET /logs` — Poll server logs during scrape (every 3s)

**Local Cache:** `~/Library/Caches/equiedge_races/races_YYYY-MM-DD.json`
- Merge logic: deduplicate by race ID, keep existing data with new overlays
- Never overwrite good cache with empty API responses

### TAB Integration (On-Device)

Runs from user's Australian device to bypass geo-blocking.

**Meetings:** `api.beta.tab.com.au/v1/tab-info-service/racing/dates/{date}/meetings?jurisdiction=NSW`
- Returns thoroughbred meetings with race numbers, start times

**Race Detail:** `.../meetings/R/{venueMnemonic}/races/{num}?jurisdiction=NSW`
- Fixed win odds (`returnWin`), race results/status

**Functions:**
- `fetchTABSchedule()` → Track → race numbers mapping, first race times (skip if >1hr away)
- `fetchTABOdds()` → Populate `suggestion.fixedWinOdds` via horse name matching
- `fetchRaceResults()` → Auto-settle bets (Lost → auto, Won → Pending Win with odds prefilled)

### Bet Settlement Flow

```
Active (result=nil)
  ├─ TAB result: lost    → result="Lost", profit=-amount (auto)
  ├─ TAB result: won     → result="Pending Win", odds prefilled (auto)
  │   └─ User confirms   → result="Won", profit calculated
  └─ Manual Won/Lost always available, never overridden by TAB
```

### Theme (Theme.swift)

Dark theme with emerald/blue accent:
- Backgrounds: `#0A0A0F`, `#12121A`, `#1A1A26`
- Accents: emerald `#00DC82`, blue `#4A9EFF`, gold `#FFB800`, red `#FF4757`
- Reusable: `EEBadge`, `EEStatCard`, `EECardModifier`, `EEGlassCardModifier`, `EEGradientButtonStyle`

---

## Backend (server.js)

### Deployment Model

| Platform | Timeout | Purpose |
|---|---|---|
| Vercel (`equiedge-scraper.vercel.app`) | 300s | Main API, static pages, cron trigger |
| AWS Lambda (SAM, `ap-southeast-2`) | 900s | Heavy scrapes, weekly results job |

Both run the same `server.js`. Lambda uses `@vendia/serverless-express` wrapper (`lambda.js`).

### Authentication Middleware

| Middleware | Header | Protects |
|---|---|---|
| `requireAuth` | `x-api-key` or `?apiKey=` | Scrape, cache, Betfair, logs endpoints |
| `requireUserId` | `Authorization: Bearer <userId>` | User status, usage recording |
| `requireCron` | `Authorization: Bearer <CRON_SECRET>` | Cron trigger |
| `requireReviewToken` | `?token=week\|exp\|hmac` | Results draft/publish/reject |

### API Endpoints

#### Race Scraping & Cache

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/warm-stats` | x-api-key | Pre-cache jockey/trainer stats before scraping |
| GET | `/scrape-now` | x-api-key | Scrape FormFav + run Grok AI; `?tracks=...&ai=true&raceFilter=...` |
| GET | `/today-races` | x-api-key | Latest scraped races |
| GET | `/logs` | x-api-key | Last 500 server log lines |
| GET | `/cache/list` | x-api-key | List all cache keys for a date |
| GET | `/cache/:track/:date` | x-api-key | Fetch cached races for track-day |
| DELETE | `/cache/:track/:date` | x-api-key | Invalidate cache entry |
| GET | `/betfair/health` | x-api-key | Betfair session diagnostics |

#### User & Subscription

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/auth/apple` | none | Apple Sign-in (verify JWT, create user, start trial) |
| GET | `/api/user/status` | Bearer userId | Tier, usage, trial info |
| POST | `/api/user/record-usage` | Bearer userId | Record track-day analysis |
| GET/POST | `/api/apple-notifications` | none | App Store Server Notifications V2 (signed JWS) |
| POST | `/api/admin/set-tier` | Bearer ADMIN_SECRET | Admin tier override |

#### Weekly Results

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/api/cron/trigger-weekly-results` | CRON_SECRET | Vercel cron → fire-and-forget to Lambda |
| GET | `/api/jobs/build-weekly-results` | x-api-key | Heavy job: load, resolve, draft, email |
| GET | `/api/results/draft` | review token | Fetch draft for review |
| PATCH | `/api/results/draft` | review token | Edit rows, recompute aggregates |
| POST | `/api/results/publish` | review token | Publish to public page |
| POST | `/api/results/reject` | review token | Reject draft |
| GET | `/api/results/latest` | public | Latest published results |
| GET | `/api/results/published` | public | Specific published week |

#### Health

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/` | none | Health check → `{"status":"ok","version":"2.3-results"}` |

### Scrape Pipeline

```
User taps "Run Edge AI Analysis" in iOS app
  ↓
1. DataService.fetchTABSchedule() — filter tracks with upcoming races
  ↓
2. GET /warm-stats?tracks=...
   → fetchJockeyStats (batches of 10, cached per session)
   → fetchTrainerStats (batches of 10, cached per session)
   → clear track bias cache for fresh session
  ↓
3. GET /scrape-now?tracks=track1,track2&ai=true
   ↓
   3a. Check Redis cache — if fresh, return cached (< 100ms)
   ↓
   3b. Acquire scrape lock (lock:track-slug_date, 5-min TTL, NX SET)
       → Concurrent requests wait (poll 5s, max 5 min)
   ↓
   3c. scrapeFormFav(date, tracks)
       → fetchRace() × N races per track (FormFav Pro API)
       → Parse runners: number, name, jockey, trainer, weight, barrier, form
       → Pro fields: age, claim, decorators, speedMap, classProfile, raceClassFit
       → Race-level: paceScenario, raceClass, raceName, startTime
   ↓
   3d. fetchTrackBias(track) — cached per session
   ↓
   3e. fetchPredictions(date, track, race#) — ML model ranks + win probs
   ↓
   3f. fetchBetfairMeetings(date) — all AU meetings + WIN market catalogues
       → fetchBetfairMarket(meeting, race#, runners) — prices per runner
   ↓
   3g. enrichRaceData(race, trackBias, predictions, betfairMarket)
       → Form parsing (wins, places, spells, last 3 runs)
       → Weight analysis (effectiveWeight, weightDiff, apprentice claims)
       → Win rate deltas vs field average
       → Barrier analysis (wide barrier detection, track bias advantage)
       → Market overlay (mlWinProb / marketImpliedProb, requires $20k+ liquidity)
       → Badge summary (positive/negative decorator counts)
       → Field averages (avgWeight, avgWinPct, avgPlacePct, avgClassRating)
   ↓
   3h. analyzeRaceWithGrok(enrichedRaces) — batches of 4 concurrent
       → POST https://api.x.ai/v1/chat/completions
       → Model: grok-4-1-fast-reasoning
       → Temperature: 0.3, max_tokens: 3000, search_mode: "auto"
       → Validate: confidence >= 60, horse exists, max 1 pick/race
   ↓
   3i. Store to Redis (cache:track-slug_YYYY-MM-DD, 14-day TTL)
   ↓
   3j. Release scrape lock
  ↓
4. iOS: fetchTABOdds() — populate fixedWinOdds on suggestions
  ↓
5. Display in TodayRacesView
```

### Grok AI SYSTEM_PROMPT

**Philosophy:** "SNIPER not machine gunner" — max 3 selections per full card (7-10 races), passing on 60-70% of races.

**10-Step Analysis:**
1. Field Assessment — size, quality, race type
2. Pace Analysis — scenario (SLOW/MODERATE/FAST/VERY_FAST), speed map
3. Form Analysis — read right-to-left, badges, franking
4. Conditions Match — track condition, distance, barrier bias
5. Class & Weight — class profile, race fit, weight analysis
6. Connections — jockey/trainer 90d stats
7. Real-Time Intelligence — X search for track updates
8. ML + Market Cross-Reference — model rank agreement, overlay ratio
9. Devil's Advocate — strongest reason pick could lose
10. Edge Identification — verify factors, resolve flags, final confidence

**Selection Criteria:**
- Requires >= 1 primary factor + >= 2 secondary factors
- Confidence >= 60 to select, max 1 per race
- Hard cap at 65 for class rises (classDifference <= -5 OR raceClassRating - highestClassWon > 10)
- Hard cap at 65 for short-priced favourites (back < 2.80) without overlay

**Confidence Bands:**
- 60-64: Lean (1-2 units)
- 65-69: Moderate (2-3 units)
- 70-74: Solid (4-5 units)
- 75-79: Strong (5-6 units)
- 80-84: Very strong (7-8 units)
- 85+: Near-certainty (9-10 units) — max once per 20 cards

**Venue Tiers:** Metro Saturday > Metro Midweek > Provincial > Country (progressively higher thresholds)

---

## Betfair Exchange Integration

### betfair/auth.js
Certificate-based non-interactive login to `identitysso-cert.betfair.com`. Session cached in-memory with 3.5-hour TTL. Auto re-login on expiry.

### betfair/client.js
JSON-RPC wrapper for `api-au.betfair.com/exchange/betting/json-rpc/v1`. Handles 401 retry with session invalidation + re-auth.

### betfair/markets.js
High-level meeting and market data:
- `fetchBetfairMeetings(date)` — `listEvents` + `listMarketCatalogue` (WIN markets, 5-event batches). 10-min cache.
- `fetchBetfairMarket(meetingCtx, raceNumber, runners)` — Match race, match runners, fetch prices. 60-sec book cache.
- `fetchMarketBookWithSP(marketId)` — For results automation (SP_AVAILABLE, SP_TRADED, EX_TRADED price data).

### betfair/matching.js
FormFav ↔ Betfair name reconciliation:

**Track matching:**
1. Check `overrides.json`
2. Check `STATIC_TRACK_OVERRIDES` (hardcoded)
3. Title-case the slug

**Horse matching (3-tier):**
1. Override (`overrides.json` horses map)
2. Exact (normalised string equality)
3. Fuzzy (Levenshtein distance <= 2 AND length ratio > 80%)

**Name normalisation:** Strip leading digits, country suffix "(NZ)", apostrophes, punctuation; lowercase, trim, collapse spaces.

---

## Weekly Results Automation

See `WEEKLY-RESULTS-AUTOMATION.md` for the complete flow. Summary:

```
Vercel Cron (Sun 22:00 UTC ≈ Mon 08:00 AEST)
  ↓
GET /api/cron/trigger-weekly-results (validates CRON_SECRET)
  ↓
Fire-and-forget GET to Lambda /api/jobs/build-weekly-results
  ↓
Lambda (900s budget):
  ├─ loadWeekMetroSelections() — MGET 98 Redis keys (14 tracks × 7 days)
  ├─ resolveSelections() — Betfair SP resolution (3 concurrent, retry + re-auth)
  ├─ buildDraft() — P/L calculation ($10/unit), confidence bands, summary
  ├─ Store results_draft:{YYYY-WW} in Redis
  └─ sendResultsReadyEmail() — HMAC-signed review link (14-day expiry)
  ↓
Admin reviews on phone: edit rows, approve or reject
  ↓
Public page: /results.html → GET /api/results/latest
```

**Metro Tracks:** Randwick, Randwick Kensington, Rosehill, Darwin, Doomben, Eagle Farm, Caulfield, Caulfield Heath, Flemington, Sandown, Morphettville, Morphettville Parks, Ascot, Belmont.

**P/L:** $10/unit stake. Win: `(finalOdds - 1) * stake`. Loss: `-stake`. Scratched/unknown: excluded.

---

## Cache Strategy

### Tiers

| Tier | Location | TTL | Purpose |
|---|---|---|---|
| In-Process | betfair/markets.js | 10min meetings, 60s books | Fresh prices without API hammering |
| Session | server.js | Per-scrape lifetime | Track bias, jockey/trainer stats |
| Distributed | Upstash Redis | 14 days | Race analysis, cross-user sharing |
| Local | iOS Caches dir | Indefinite | Offline access to race data |

### Redis Keys

| Key Pattern | TTL | Purpose |
|---|---|---|
| `cache:{track}_{YYYY-MM-DD}` | 14 days | Cached race data (from scrape) |
| `lock:{track}_{YYYY-MM-DD}` | 5 min | Scrape lock (prevents duplicate Grok calls) |
| `user:{appleUserId}` | none | User record (tier, trial, usage) |
| `results_draft:{YYYY-WW}` | none | Draft results bundle |
| `results:published:{YYYY-WW}` | none | Published results (permanent archive) |
| `results:latest` | none | Most recent published results |
| `results_error:{YYYY-WW}` | 30 days | Error log from failed job |

---

## Environment Variables

### Required (Lambda + Vercel)

| Variable | Purpose |
|---|---|
| `FORMAV_API_KEY` | FormFav Pro tier API key |
| `XAI_API_KEY` | Grok API key (x.ai) |
| `EQUIEDGE_API_KEY` | Backend API key (x-api-key header) |

### Betfair (Optional)

| Variable | Purpose |
|---|---|
| `BETFAIR_APP_KEY` | Betfair developer app key |
| `BETFAIR_USERNAME` | Betfair Australia credentials |
| `BETFAIR_PASSWORD` | Betfair Australia credentials |
| `BETFAIR_CERT_PEM` | Client certificate (PEM) |
| `BETFAIR_KEY_PEM` | Client key (PEM) |

### Cache & Results

| Variable | Purpose |
|---|---|
| `UPSTASH_REDIS_REST_URL` | Redis cache URL |
| `UPSTASH_REDIS_REST_TOKEN` | Redis cache token |
| `CRON_SECRET` | Vercel cron validation |
| `RESULTS_REVIEW_SECRET` | HMAC token signing |
| `RESEND_API_KEY` | Email sending (Resend) |
| `ADMIN_EMAIL` | Weekly review email recipient |

### Other

| Variable | Purpose |
|---|---|
| `APPLE_BUNDLE_ID` | iOS app bundle (default: `Eedge.EquiEdge`) |
| `ADMIN_SECRET` | Admin tier override endpoint |
| `SITE_URL` | Review link base (default: `https://equiedge-scraper.vercel.app`) |

---

## Deployment

```bash
# Lambda (SAM)
cd /Users/marcravida/Desktop/equiedge-scraper
sam build && sam deploy

# Vercel
npx vercel --prod
```

**Vercel project:** `equiedge-scraper` → `equiedge-scraper.vercel.app`
**Lambda:** `ap-southeast-2`, stack `equiedge-scraper`, 512MB, 900s timeout, Node.js 22.x

---

## Dependencies

```json
{
  "@upstash/redis": "^1.37.0",
  "@vendia/serverless-express": "^4.12.6",
  "axios": "^1.6.0",
  "cors": "^2.8.5",
  "express": "^4.18.2",
  "jose": "^5.10.0"
}
```

No additional dependencies for results automation (native fetch, inline p-limit, node crypto HMAC, existing Levenshtein).
