# Track Management Guide

When a track is added, changed, or removed, multiple parts of the system need updating. This document covers every touchpoint.

---

## System Components That Reference Tracks

| Component | File(s) | What it does with tracks |
|---|---|---|
| iOS App | `DataService.swift`, `TrackSelectorView.swift` | User selects tracks to scrape, sends to backend |
| Backend (server.js) | `server.js` | Receives track names, scrapes FormFav, calls Grok, caches by track slug |
| Betfair Matching | `betfair/matching.js` | Maps track names to Betfair venue names |
| Redis Cache | Upstash | Keys formatted as `cache:{track-slug}_{date}` |
| Results Automation | `lib/results/selections.js` | Hardcoded `METRO_TRACKS` list determines which tracks are included in weekly results |
| Grok AI Prompt | `server.js` (SYSTEM_PROMPT) | References metro/provincial/country venue tiers for confidence calibration |

---

## Adding a New Track

### 1. iOS App (`TrackSelectorView.swift`)

The track selector shows available tracks to the user. If the new track should appear in the picker:

- Add the track name to the relevant track list/array in `TrackSelectorView.swift`
- Use the exact display name (e.g. "Eagle Farm", "Morphettville Parks")
- The app sends this name to `/scrape-now?tracks=Eagle+Farm`

### 2. Backend — No Changes Needed

`server.js` is track-agnostic. It takes whatever track name the iOS app sends, passes it to FormFav, and caches the result. The cache key is generated dynamically:

```
cache:{track.toLowerCase().replace(/\s+/g, '-')}_{date}
```

So "Eagle Farm" becomes `cache:eagle-farm_2026-04-21`. No hardcoded track list in server.js.

### 3. Betfair Matching (`betfair/matching.js`)

Betfair uses its own venue names (e.g. "Randwick (AUS)", "Eagle Farm"). The matching module handles this automatically for most tracks via:

1. Title-casing the slug ("eagle-farm" -> "Eagle Farm")
2. Static overrides in `STATIC_TRACK_OVERRIDES` for non-obvious mappings
3. Override file `betfair/overrides.json` for stubborn edge cases

**If the new track's name doesn't match Betfair's venue name**, add an entry:

```javascript
// In betfair/matching.js STATIC_TRACK_OVERRIDES
'new-track-slug': 'Betfair Venue Name',
```

Or in `betfair/overrides.json`:
```json
{ "tracks": { "new-track-slug": "Betfair Venue Name" } }
```

**How to check:** Run a scrape with `?tracks=NewTrack&ai=true` and check `/logs` for "Betfair: no meeting match for ..." warnings. If you see one, add the override.

### 4. Results Automation (`lib/results/selections.js`)

**Only if the new track is a metro track** that should be included in weekly results:

```javascript
// In lib/results/selections.js
const METRO_TRACKS = [
  'Randwick', 'Randwick Kensington', 'Rosehill',
  'Darwin', 'Doomben', 'Eagle Farm',
  'Caulfield', 'Caulfield Heath', 'Flemington', 'Sandown',
  'Morphettville', 'Morphettville Parks',
  'Ascot', 'Belmont',
  'New Track Name',  // <-- add here
];
```

The track name here must match exactly what gets stored in the cache key (the display name before slug conversion). The code converts it to a slug internally for the Redis key lookup.

**If the track is provincial or country, do NOT add it.** Only metro tracks go in weekly results.

### 5. Grok AI Prompt (server.js — SYSTEM_PROMPT)

The prompt references venue quality tiers:

```
- METRO SATURDAY (Randwick, Flemington, Eagle Farm, Morphettville, Ascot)
- METRO MIDWEEK (Canterbury, Sandown, Doomben, etc.)
- PROVINCIAL (Newcastle, Geelong, Ipswich, Gold Coast, Townsville, etc.)
```

If the new track is metro, add it to the appropriate line so Grok applies the correct confidence thresholds. This is in the `SYSTEM_PROMPT` constant near the top of `server.js` (around line 154-170).

### 6. Deploy

After changes:
```bash
sam build && sam deploy    # Lambda
npx vercel --prod          # Vercel
```

---

## Renaming a Track

If a track changes its official name (e.g. hypothetically "Caulfield" becomes "Caulfield Racecourse"):

### What breaks:
- **Redis cache** — old cached data uses the old slug. New scrapes create new keys. Old data expires naturally (14-day TTL). No manual cleanup needed.
- **Results automation** — if the old name is in `METRO_TRACKS`, update it. Old cached data from the previous name won't match the new name, so any data cached under the old name during the transition week may be missed.

### Update checklist:
1. `TrackSelectorView.swift` — update display name
2. `betfair/matching.js` — update or add override if Betfair uses a different name
3. `lib/results/selections.js` — update `METRO_TRACKS` if it's metro
4. `server.js` SYSTEM_PROMPT — update venue tier references
5. Deploy both Lambda and Vercel

---

## Removing a Track

If a track closes permanently or is no longer relevant:

### 1. iOS App
- Remove from `TrackSelectorView.swift`

### 2. Backend
- No changes needed. server.js is track-agnostic. Old cache entries expire after 14 days.

### 3. Betfair Matching
- Optional: remove the override from `matching.js` or `overrides.json` if one exists. Not strictly necessary — unused overrides are harmless.

### 4. Results Automation
- Remove from `METRO_TRACKS` in `lib/results/selections.js` if present. This stops the weekly job from looking for it (saves 7 unnecessary Redis key lookups per week).

### 5. Grok AI Prompt
- Remove from venue tier references in SYSTEM_PROMPT if mentioned by name.

### 6. Deploy

---

## Track Name Conventions

| Context | Format | Example |
|---|---|---|
| iOS display / API param | Title Case with spaces | `Eagle Farm` |
| Redis cache key slug | Lowercase with hyphens | `eagle-farm` |
| Betfair venue | Title Case, sometimes with "(AUS)" | `Eagle Farm` or `Eagle Farm (AUS)` |
| FormFav | Varies — the backend handles this | `eagle-farm` |
| METRO_TRACKS array | Title Case with spaces (matches iOS) | `Eagle Farm` |

The slug conversion is: `track.toLowerCase().replace(/\s+/g, '-')`

So "Randwick Kensington" -> `randwick-kensington`, "Morphettville Parks" -> `morphettville-parks`.

---

## Quick Reference: Where to Edit

| Scenario | Files to touch |
|---|---|
| Add metro track | `TrackSelectorView.swift`, `lib/results/selections.js`, `server.js` (SYSTEM_PROMPT), possibly `betfair/matching.js` |
| Add provincial/country track | `TrackSelectorView.swift`, possibly `betfair/matching.js` |
| Remove any track | `TrackSelectorView.swift`, `lib/results/selections.js` (if metro), optionally `betfair/matching.js` |
| Rename any track | All of the above depending on metro/provincial |
| Fix Betfair matching for a track | `betfair/matching.js` (STATIC_TRACK_OVERRIDES) or `betfair/overrides.json` |
