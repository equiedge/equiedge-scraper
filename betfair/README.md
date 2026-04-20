# Betfair Exchange integration

This module wires Betfair Australia market prices into the FormFav
scrape pipeline so Grok can reason about market overlays alongside
form. Everything is optional — if the env vars aren't set the
scraper runs exactly like the pre-v5 version.

## What it adds

For every race FormFav returns, the scraper attaches:

- `marketData.marketId`, `marketName`, `marketTime`, `totalMatched`
- per-runner `backPrice`, `layPrice`, `impliedProb`, `matchedVolume`
- a `favorite` shortcut (name / number / price)
- a `marketSummary` on the race object with liquidity flag and
  favourite price for quick Grok filtering

These feed into SYSTEM_PROMPT v5, which:

- Uses an overlay ratio (ML `winProbability` ÷ market
  `impliedProb`) as the primary edge signal (≥ 1.25 = strong).
- Hard-caps confidence on class-rise runners at 65.
- Suppresses selections when the race is illiquid (<$20k matched)
  and the only edge is market overlay.
- Flags short-priced favourites (< $2.80) without overlay support.

## Prerequisites

1. A funded Betfair AU account (same login you use on the
   exchange website).
2. An **application key** from
   https://developer.betfair.com/en/get-started/ — pick the
   **Delayed** key for dev/staging; the Live key requires a
   paid subscription and explicit approval.
3. `openssl` on your machine (macOS/Linux ship with it).

## Setup

### 1. Generate the client cert

```
bash betfair/setup-cert.sh
```

This creates `betfair/.secrets/client-2026.crt` and
`client-2026.key` and prints their PEM contents.

### 2. Upload the cert to Betfair

Log in at https://myaccount.betfair.com.au/account/mysecurity →
**Automated login** section → upload `client-2026.crt`. Wait ~1
minute for activation.

### 3. Configure env vars

Local dev — add to `.env.local`:

```
BETFAIR_USERNAME=...
BETFAIR_PASSWORD=...
BETFAIR_APP_KEY=...          # delayed key unless you have live
BETFAIR_CERT_PEM="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
BETFAIR_KEY_PEM="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

The `\n` literals matter — they get expanded at runtime by
`betfair/auth.js`. Multi-line PEMs also work if your host
supports them.

Vercel — add the same five vars via `vercel env add` or the
dashboard, for Production **and** Preview **and** Development.
Vercel's web UI accepts pasted multi-line PEMs directly.

### 4. Deploy / restart and verify

```
curl -H "x-api-key: $EQUIEDGE_API_KEY" https://<your-host>/betfair/health
```

Expected response when everything's wired:

```json
{
  "enabled": true,
  "envStatus": { "BETFAIR_APP_KEY": true, "BETFAIR_CERT_PEM": true, ... },
  "loginOk": true,
  "session": { "hasToken": true, "ageSeconds": 12, "ttlSeconds": 12588 },
  "requests": { "requestCount": 1, "uptimeSeconds": 34 }
}
```

Then hit `/scrape?date=YYYY-MM-DD` — server logs should show:

```
Betfair: 8 AU horse-racing meetings found for 2026-04-25
Betfair: market catalogue loaded for 8 venues
Betfair: randwick R3 matched 12/12 runners
```

## File layout

| File | Purpose |
|---|---|
| `auth.js` | Cert-login + session-token cache (3.5h TTL). |
| `client.js` | Thin JSON-RPC wrapper, retries once on 401 / INVALID_SESSION. |
| `matching.js` | Track-slug → venue, `R<n>` → market, runner → selection fuzzy match. |
| `markets.js` | High-level `fetchBetfairMeetings()` + `fetchBetfairMarket()`. |
| `overrides.json` | Manual corrections for the stubborn cases. Starts empty. |
| `setup-cert.sh` | One-shot openssl script for the client cert. |

## Caches

- Meetings + catalogue: 10-minute TTL (fields change late).
- Market book (prices): 60-second TTL (prices move fast).

All caches are per-process, so Vercel cold starts repay the API
cost on the first request of each lambda. Inside a warm lambda
the same `/scrape` call costs 1 × `listEvents` + N × `listMarketCatalogue`
+ M × `listMarketBook` where N is batches of 5 meetings and M is
the number of races you query within 60 s.

## Overrides

When a venue or horse consistently fails to match, edit
`betfair/overrides.json`:

```json
{
  "tracks": {
    "murwillumbah": "Murwillumbah (AUS)"
  },
  "horses": {
    "sir slick": "sir slick nz"
  }
}
```

Both keys and values are lowercased, punctuation-stripped after
running through `normaliseHorseName`. You'll see the mismatch in
logs as:

```
Betfair: no meeting match for "murwillumbah" (tried: Murwillumbah)
Betfair: randwick R5 — 1 unmatched runners: Sir Slick
```

## Failure modes

The scraper should never break because of Betfair. Known fall-throughs:

| Condition | Behaviour |
|---|---|
| Any env var missing | `BETFAIR_ENABLED = false`, scrape runs with `marketData = null` everywhere. Grok reverts to form-only. |
| Cert expired / revoked | `auth.js` throws on login, `markets.js` catches + returns empty map, `/scrape` still succeeds with `marketData = null`. Log line: `Betfair login failed: ...`. |
| Meeting not in catalogue (country meetings, late scratchings, non-thoroughbred) | Race gets `marketData = null`; Grok is told "no market" in STEP 8 and reverts to form-only for that race. |
| Market illiquid (<$20k matched) | `marketHasLiquidity = false`; v5 prompt suppresses overlay-only selections in those races. |
| Session expires mid-scrape | `client.js` auto-retries once after `invalidateSession()`. |

Cost-wise the Delayed key is free but capped at 100 data requests
per minute — a single `/scrape` across a full Australian Saturday
typically costs 15-25 requests so there's plenty of headroom.

## When to rotate

- Every 24 months (cert expiry — the setup script uses 730-day
  validity so you'll see login failures ~2 years from generation).
- Immediately if either PEM leaks.

To rotate, delete `betfair/.secrets/*`, re-run `setup-cert.sh`,
upload the new `.crt` to Betfair (it supports up to 5 active
certs so you can overlap), then update Vercel env vars.
