# Weekly Metro Results Automation

## Overview

Every Monday morning (Australian time), EquiEdge automatically compiles the previous week's AI race selections for metro tracks, looks up each result and final odds via Betfair, computes P/L, and emails a review link. Publishing to the public results page happens only after explicit approval from the phone.

---

## Full Flow

### 1. Vercel Cron Fires (Sunday 22:00 UTC / Monday 08-09:00 AEST)

- Hits `GET /api/cron/trigger-weekly-results` on `equiedge-scraper.vercel.app`
- Validates `Authorization: Bearer $CRON_SECRET`
- Computes previous week label (e.g. `2026-W17`)
- Fire-and-forget `fetch` to Lambda at `/api/jobs/build-weekly-results?week=2026-W17`
- Returns 202 immediately (stays under Vercel's 10s timeout)

### 2. Lambda Runs the Heavy Job (up to 900s budget)

**Idempotency check** — if `results_draft:2026-W17` already exists in Redis, no-op (unless `?force=1`).

**Load selections** — builds 98 Redis keys (7 days x 14 metro tracks), fetches all in a single `MGET`. Parses each cached race JSON, extracts `suggestions` array (horseName, confidence, units, marketBackPrice, reason). Only metro tracks.

**Resolve via Betfair** — for each selection, grouped by race:
- Fetches Betfair meetings for that date (cached per date)
- Matches track name to Betfair venue using `betfair/matching.js`
- Finds the WIN market for that race number
- Fetches market book with SP data (`SP_AVAILABLE`, `SP_TRADED`, `EX_TRADED`)
- Matches horse name to Betfair runner (exact normalised match, then Levenshtein <= 2 fallback)
- Extracts result: `WINNER` -> win, `LOSER` -> loss, `REMOVED` -> scratched
- Extracts final odds priority: `sp.actualSP` -> `sp.nearPrice` -> `lastPriceTraded`
- Any failure -> `unknown` + `needsManualReview: true`
- Concurrency: 3 parallel, with exponential retry and session re-auth on 401

**Build draft** — computes per-row P/L ($10/unit), summary (totalBets, wins, losses, profit, ROI), confidence band breakdown (60-64, 65-69, 70-74, etc.). Scratched/unknown rows excluded from summary. Stores as `results_draft:2026-W17` in Redis.

**Send email** — via Resend API to `ADMIN_EMAIL`. Subject: "EquiEdge results ready - 2026-W17". Contains one-line summary (bets, W/L, profit, ROI) and a "Review & Approve" button linking to the admin page with an HMAC-signed token (14-day expiry).

**On failure** — writes `results_error:2026-W17` to Redis, sends failure email with error details.

### 3. Review on Phone

Open the email link: `https://equiedge-scraper.vercel.app/admin/results-review.html?week=2026-W17&token=...`

- Mobile-first dark UI showing summary bar + every selection as an editable card
- Rows needing review are highlighted gold (no Betfair match, no SP, scratched)
- You can edit: result (win/loss/scratched/unknown), final odds, notes
- **Save** -> `PATCH /api/results/draft` — sends edited rows, server recomputes summary + confidence bands, stores back to Redis
- **Approve** -> `POST /api/results/publish` — copies draft to `results:published:2026-W17` + `results:latest`, sets status to "published"
- **Reject** -> `POST /api/results/reject` — marks draft as rejected, nothing published

### 4. Public Page Goes Live

`https://equiedge-scraper.vercel.app/results.html` fetches `/api/results/latest` and renders:
- Summary cards (bets, W/L, profit, ROI, staked)
- Confidence band breakdown cards
- Sortable detail table (date, track, race, horse, confidence, units, odds, result, P/L)

---

## Data Flow

```
Scrape (daily)           -> Redis cache (14-day TTL)
                              |
Cron (Sunday)            -> Lambda job reads cache
                              |
Betfair API              -> Results + SP odds
                              |
Draft bundle             -> Redis (results_draft:YYYY-WW)
                              |
Email                    -> Review link to phone
                              |
Approve                  -> Redis (results:latest + results:published:YYYY-WW)
                              |
Public page              -> Fetches results:latest
```

---

## Metro Tracks (hardcoded)

Randwick, Randwick Kensington, Rosehill, Darwin, Doomben, Eagle Farm, Caulfield, Caulfield Heath, Flemington, Sandown, Morphettville, Morphettville Parks, Ascot, Belmont.

---

## API Endpoints

| Endpoint | Auth | Runtime | Purpose |
|---|---|---|---|
| `GET /api/cron/trigger-weekly-results` | `CRON_SECRET` | Vercel | Cron trigger, fires Lambda |
| `GET /api/jobs/build-weekly-results` | `EQUIEDGE_API_KEY` | Lambda | Heavy job: load, resolve, draft, email |
| `GET /api/results/draft?week&token` | HMAC token | Vercel | Get draft for review |
| `PATCH /api/results/draft?week&token` | HMAC token | Vercel | Edit rows, recompute aggregates |
| `POST /api/results/publish?week&token` | HMAC token | Vercel | Publish to public page |
| `POST /api/results/reject?week&token` | HMAC token | Vercel | Reject draft |
| `GET /api/results/latest` | None (public) | Vercel | Get latest published results |
| `GET /api/results/published?week` | None (public) | Vercel | Get specific published week |

---

## Files

| File | Purpose |
|---|---|
| `lib/results/selections.js` | Metro selection loader from Redis cache (MGET) |
| `lib/results/betfairResults.js` | Betfair SP resolution for settled races |
| `lib/resultsBuilder.js` | Draft bundle builder with P/L + confidence bands |
| `lib/email.js` | Resend email + HMAC review tokens |
| `public/results.html` | Public weekly results page |
| `public/admin/results-review.html` | Admin review/approve UI (mobile-first) |

---

## Environment Variables

**Vercel** (`equiedge-scraper` project):
- `CRON_SECRET` — validates Vercel cron requests
- `RESULTS_REVIEW_SECRET` — HMAC signing key for review tokens
- `RESEND_API_KEY` — Resend email API key
- `ADMIN_EMAIL` — email address for review notifications
- `LAMBDA_FUNCTION_URL` — Lambda Function URL for fire-and-forget trigger

**Lambda** (SAM template parameters):
- `ResultsReviewSecret` — same as `RESULTS_REVIEW_SECRET`
- `ResendApiKey` — same as `RESEND_API_KEY`
- `AdminEmail` — same as `ADMIN_EMAIL`

---

## Redis Keys

| Key | TTL | Purpose |
|---|---|---|
| `cache:{track}_{YYYY-MM-DD}` | 14 days | Cached race data (existing, from scrape) |
| `results_draft:{YYYY-WW}` | None | Draft results bundle |
| `results:published:{YYYY-WW}` | None | Published results (permanent archive) |
| `results:latest` | None | Most recent published results (public page) |
| `results_error:{YYYY-WW}` | 30 days | Error log from failed job |

---

## P/L Calculation

- Stake = `units * $10`
- Win: profit = `(finalFixedOdds - 1) * stake`
- Loss: profit = `-stake`
- Scratched: excluded from summary (refund)
- Unknown: excluded from summary until manually resolved

---

## Manual Operations

**Re-run a specific week:**
```bash
curl -H "x-api-key: $API_KEY" \
  "$LAMBDA_URL/api/jobs/build-weekly-results?manualWeek=2026-W17&force=1"
```

**Test the cron trigger:**
```bash
curl -H "Authorization: Bearer $CRON_SECRET" \
  "https://equiedge-scraper.vercel.app/api/cron/trigger-weekly-results"
```

---

## Deployment

```bash
# Lambda
cd /Users/marcravida/Desktop/equiedge-scraper
sam build && sam deploy

# Vercel
npx vercel --prod
```

## Dependencies

Zero new dependencies. Uses native `fetch`, inline p-limit, existing `betfair/matching.js` Levenshtein, and Node `crypto` for HMAC tokens.
