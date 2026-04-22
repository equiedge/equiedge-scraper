# EquiEdge Subscription Management

## Overview

Subscriptions are managed through a **dual-source system**: a backend Redis store (source of truth) and on-device StoreKit 2 entitlements (fallback). The iOS app reconciles both sources to determine the user's effective tier.

---

## Architecture

```
iOS App (SubscriptionManager)
    |
    |-- 1. GET /api/user/status  -->  Lambda (server.js)  -->  Redis (user:{appleUserId})
    |-- 2. StoreKit 2 local entitlements (fallback)
    |
    v
  Effective tier = max(backend tier, local StoreKit tier)
```

## Tiers

| Tier | Limits | How Activated |
|------|--------|---------------|
| `trial` | 3 days, 3 track-day analyses | Auto on first sign-in |
| `basic` | 10 track-days per ISO week | StoreKit purchase or admin override |
| `pro` | Unlimited | StoreKit purchase or admin override |
| `expired` | No access | Trial lapsed or subscription ended |

## Where Subscription is Displayed

- **Settings screen** (`SettingsView.swift`): Shows tier name, badge, usage stats, and "Upgrade Plan" button
- **Paywall** (`PaywallView.swift`): Shown via sheet from Settings or when usage limits hit
- Tier info drives gating in `DataService` when requesting AI analysis

## Data Flow

### 1. Sign In (POST `/api/auth/apple`)
- Verifies Apple identity token (JWKS)
- Creates Redis record if new user:
  ```json
  {
    "appleUserId": "000133.xxx",
    "tier": "trial",
    "trialStartDate": "2026-04-21T11:08:38.407Z",
    "trialUsage": [],
    "weeklyUsage": { "isoWeek": "2026-W17", "tracks": [] },
    "subscriptionExpiresAt": null,
    "createdAt": "2026-04-21T11:08:38.407Z"
  }
  ```
- Redis key: `user:{appleUserId}` (no TTL, permanent)

### 2. Status Check (GET `/api/user/status`)
- Called by `SubscriptionManager.refreshStatus()` on app launch and after purchases
- Backend computes `effectiveTier(user)`:
  - Trial: expired if > 3 days old OR 3 uses reached
  - Basic/Pro: expired if `subscriptionExpiresAt` < now
- Returns tier + usage counts for display

### 3. Local Entitlement Fallback
- After backend sync, if tier is still `trial` or `expired`, `refreshFromLocalEntitlements()` runs
- Iterates `Transaction.currentEntitlements` (StoreKit 2)
- If a valid (non-revoked) subscription exists on-device, upgrades local tier
- **This is why the app can show a different tier than Redis** -- sandbox/test purchases create local entitlements that the backend doesn't know about until Apple's S2S notification arrives

### 4. Usage Recording (POST `/api/user/record-usage`)
- Called before each AI analysis with `{ trackSlug, date }`
- Composite key: `{trackSlug}_{date}` (e.g., `randwick_2026-04-22`)
- Re-runs on same track-day are free (idempotent)
- Returns 403 when limits exceeded

### 5. Apple S2S Notifications (POST `/api/apple-notifications`)
- App Store Server Notifications V2 (JWS signed)
- `SUBSCRIBED` / `DID_RENEW` -> updates tier + expiry in Redis
- `EXPIRED` / `DID_REVOKE` / `REFUND` -> sets tier to `expired`

## Redis Key Format

```
user:{appleUserId}
```

Example appleUserId: `000133.25b49123d9e64b878ee026d2abecfa1d.0655`

## Known Discrepancy: App Shows Different Tier Than Redis

**Scenario:** Redis shows `trial`, app shows `Basic`.

**Cause:** The app's `refreshFromLocalEntitlements()` (SubscriptionManager.swift:277-295) checks on-device StoreKit transactions. Xcode StoreKit testing or sandbox purchases create local entitlements that override the backend tier. The backend only updates when Apple's S2S notification arrives at `/api/apple-notifications`.

**This is expected behavior for test/sandbox accounts.** In production, S2S notifications typically arrive within seconds, so Redis and the app stay in sync.

---

## How to Override / Provide Free Access

### Method 1: Admin API Endpoint (Recommended)

**Endpoint:** `POST /api/admin/set-tier`

**Authentication:** `Authorization: Bearer <ADMIN_SECRET>` (env var on Lambda)

**Request body:**
```json
{
  "appleUserId": "000133.25b49123d9e64b878ee026d2abecfa1d.0655",
  "tier": "pro",
  "expiresAt": null
}
```

- Set `tier` to `"pro"` or `"basic"` for free access
- Set `expiresAt` to `null` for permanent access, or an ISO date for temporary access (e.g., `"2027-01-01T00:00:00.000Z"`)
- Sets `adminOverride: true` flag on the user record
- If the user doesn't exist yet, creates a minimal record

**Example curl:**
```bash
# Permanent pro access
curl -X POST "https://ghavmqa2tz5daqvb7ooj7qqk5u0xdcbm.lambda-url.ap-southeast-2.on.aws/api/admin/set-tier" \
  -H "Authorization: Bearer $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appleUserId":"000133.25b49123d9e64b878ee026d2abecfa1d.0655","tier":"pro","expiresAt":null}'

# Basic access until end of year
curl -X POST "https://ghavmqa2tz5daqvb7ooj7qqk5u0xdcbm.lambda-url.ap-southeast-2.on.aws/api/admin/set-tier" \
  -H "Authorization: Bearer $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appleUserId":"000133.25b49123d9e64b878ee026d2abecfa1d.0655","tier":"basic","expiresAt":"2027-01-01T00:00:00.000Z"}'
```

**After override:** The user needs to relaunch the app (or pull-to-refresh on a screen that calls `refreshStatus()`) for the new tier to take effect.

### Method 2: Direct Redis Edit (Upstash Console)

1. Go to your Upstash Redis console
2. Find key: `user:000133.25b49123d9e64b878ee026d2abecfa1d.0655`
3. Edit the JSON value, setting:
   ```json
   {
     "tier": "pro",
     "subscriptionExpiresAt": null,
     "adminOverride": true
   }
   ```
4. Save. The next `/api/user/status` call from the app will pick up the new tier.

### Method 3: Reset Trial

To give a user a fresh trial (3 more days + 3 more analyses):
```bash
curl -X POST ".../api/admin/set-tier" \
  -H "Authorization: Bearer $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"appleUserId":"...","tier":"trial","expiresAt":null}'
```
Then in Redis, also reset `trialStartDate` to now and clear `trialUsage` array.

---

## Environment Variables

| Variable | Location | Purpose |
|----------|----------|---------|
| `ADMIN_SECRET` | Lambda (SAM template) | Bearer token for `/api/admin/set-tier` |
| `UPSTASH_REDIS_REST_URL` | Lambda | Redis connection |
| `UPSTASH_REDIS_REST_TOKEN` | Lambda | Redis auth |
| `APPLE_BUNDLE_ID` | Lambda | For Apple JWT verification (default: `Eedge.EquiEdge`) |

## Key Files

| File | Role |
|------|------|
| `EquiEdge/SubscriptionManager.swift` | iOS subscription state, StoreKit 2, backend sync |
| `EquiEdge/SettingsView.swift` | Subscription display UI |
| `EquiEdge/PaywallView.swift` | Purchase flow UI |
| `EquiEdge/AuthManager.swift` | Sign in with Apple, Keychain storage |
| `server.js` (lines 1489-1911) | All backend subscription logic |
| `EquiEdge/Configuration.storekit` | StoreKit testing config for Xcode |
