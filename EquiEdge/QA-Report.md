# EquiEdge iOS App - QA Bug & Issue Report

**Date:** 2026-04-21
**Reviewer:** QA Engineer
**Scope:** Full app review - all flows, integrations, endpoints (excluding Grok AI analysis)

---

## CRITICAL ISSUES

### BUG-001: Hardcoded API Key Exposed in Source Code
**File:** `DataService.swift:101`
**Severity:** Critical (Security)
**Description:** The API key is hardcoded as a plain string constant in the source file. This key will be visible in the compiled binary and can be extracted by anyone with the IPA.
**Steps to Reproduce:**
1. Build the app
2. Extract the binary from the IPA
3. Run `strings` on the binary - the API key `5124f85d...` is visible
**Impact:** Unauthorized access to the backend Lambda endpoint.

### BUG-002: User Authentication Uses userId as Bearer Token
**File:** `SubscriptionManager.swift:127`
**Severity:** Critical (Security)
**Description:** The app sends the Apple User Identifier directly as a `Bearer` token for all authenticated API calls. The `userId` is a stable, opaque identifier from Apple but is NOT a cryptographic token. Any user who obtains another user's Apple User ID can impersonate them to the backend.
**Steps to Reproduce:**
1. Sign in with Apple
2. Intercept network requests - observe `Authorization: Bearer <userId>`
3. The userId is a stable string that doesn't expire or rotate
**Impact:** Account impersonation; any user's subscription status and usage can be manipulated.

### BUG-003: New URLSession Created on Every API Call
**File:** `DataService.swift:102-107`
**Severity:** Critical (Performance/Resource Leak)
**Description:** The `session` property is a computed property that creates a brand new `URLSession` with a new `URLSessionConfiguration` on every access. URLSessions are heavyweight objects with their own connection pools. During a multi-track scrape, dozens of sessions may be created and never invalidated.
**Steps to Reproduce:**
1. Select 5+ tracks
2. Run Edge AI Analysis
3. Monitor memory usage - URLSession objects accumulate
**Impact:** Memory leaks, excessive TCP connections, potential crashes on low-memory devices.

---

## HIGH SEVERITY ISSUES

### BUG-004: @Transient Properties Lost on Cache Round-Trip
**File:** `Models.swift:21,183-192`
**Severity:** High
**Description:** `BetSuggestion.keyBadges` and all Runner pro fields (`stats`, `decorators`, `speedMap`, `classProfile`, `raceClassFit`, `prediction`) are marked `@Transient`. However, they ARE included in `CodingKeys` and are encoded/decoded to/from JSON cache. The `@Transient` attribute means SwiftData won't persist them to the database, but since these objects aren't being stored in SwiftData (they're decoded from JSON cache), this creates a confusing semantic mismatch. More critically: `keyBadges` IS encoded to cache JSON, but since it's `@Transient`, if the objects are ever inserted into a SwiftData ModelContext, these values will be silently dropped.
**Steps to Reproduce:**
1. Run analysis (data gets cached as JSON)
2. Navigate to a race - pro data (speedMap, decorators, predictions) should display
3. If the Race/Runner objects are ever persisted via SwiftData (e.g., via modelContainer), the transient fields are lost
**Impact:** Pro data display may be unreliable across app sessions; data inconsistency between cache and SwiftData.

### BUG-005: Race Hashable/Equatable Not Implemented - NavigationLink May Break
**File:** `TodayRacesView.swift:168`, `Models.swift:261`
**Severity:** High
**Description:** `Race` is used as a `NavigationLink(value:)` destination via `.navigationDestination(for: Race.self)`. This requires `Race` to conform to `Hashable`. `@Model` classes get synthesized `Hashable` based on their persistent ID, but since Race objects are decoded fresh from JSON cache (with new UUIDs each time for runners/suggestions), navigation state may break when the race list reloads.
**Steps to Reproduce:**
1. Navigate to a race detail
2. While viewing, if `processRaceData` runs (e.g., background refresh), the Race object in the NavigationPath may no longer match any object in the list
3. Navigation may silently fail or show stale data
**Impact:** Navigation failures; user may get stuck on a detail view showing outdated data.

### BUG-006: processRaceData Discards Existing Suggestions Every Time
**File:** `DataService.swift:983-1002`
**Severity:** High
**Description:** `processRaceData` always rebuilds `suggestionsByRaceID` from scratch by calling `AnalysisService.shared.analyze(race:)`. But `AnalysisService.analyze()` simply returns `race.suggestions` (the raw server data). After `processRaceData` runs, the `suggestionsByRaceID` dictionary uses `String(describing: race.id)` as the key, which for a `@Model` class may not produce the expected string. More importantly, if `race.suggestions` is empty (e.g., for races without AI analysis), the race is filtered out entirely - meaning the user can't see field data for un-analysed races via the "Picks Only" filter being OFF.
**Steps to Reproduce:**
1. Run analysis for a track
2. Observe that `self.races` only contains races where suggestions exist
3. Toggle "Picks Only" OFF - `allRaces` contains all races, but `self.races` is the filtered subset
4. This is actually working as designed, but the `String(describing: race.id)` key generation is fragile
**Impact:** If `race.id` representation changes, the lookup breaks silently.

### BUG-007: Subscription Product ID Inconsistency
**File:** `SubscriptionManager.swift:43-44`
**Severity:** High
**Description:** The basic monthly product ID uses different casing: `"EquiEdge.basic.monthly"` (capital E) while all other IDs use lowercase: `"equiedge.basic.annual"`, `"equiedge.pro.monthly"`, `"equiedge.pro.annual"`. The `monthlyProduct(for:)` method at line 253 constructs the ID as `"equiedge.\(tier).monthly"` (lowercase), which will NEVER match the basic monthly product `"EquiEdge.basic.monthly"`.
**Steps to Reproduce:**
1. Open Paywall
2. Select "Basic" tier
3. Select "Monthly" billing
4. Tap "Subscribe to Basic"
5. `handlePurchase()` calls `monthlyProduct(for: "basic")` which looks for `"equiedge.basic.monthly"` - this won't match `"EquiEdge.basic.monthly"`
6. Error: "Product not available"
**Impact:** Users CANNOT purchase the Basic Monthly subscription. This is a revenue-blocking bug.

### BUG-008: Date Navigation Can Go Into the Future Beyond Today
**File:** `DataService.swift:229-236`
**Severity:** High
**Description:** `goToNextDay()` only blocks navigation past today (`guard !isShowingToday`). But `canGoForward` also returns true when not showing today. If the user navigates to yesterday, then forward to today, this works. However, there's no check preventing navigating to future dates if `selectedDate` somehow gets set to a future date (e.g., timezone edge case where `startOfToday` changes mid-session).
**Steps to Reproduce:**
1. Open app near midnight
2. Navigate back one day
3. Wait until after midnight (selectedDate is now yesterday, isShowingToday is false)
4. Tap forward - selectedDate becomes "today" (which is now the new day)
5. Tap forward again - goes to tomorrow (the old "today")
**Impact:** Empty UI with no data for future dates.

---

## MEDIUM SEVERITY ISSUES

### BUG-009: TAB Horse Name Matching Too Loose - False Matches Possible
**File:** `DataService.swift:737-739`
**Severity:** Medium
**Description:** Horse name matching uses `.contains()` in both directions: `name.contains(target) || target.contains(name)`. This means a horse named "Red" would match "Fred", "Redback", etc. Similarly, "The" would match almost any horse.
**Steps to Reproduce:**
1. Have a race with a horse whose name is a substring of another horse (e.g., "Star" and "Starlight")
2. Check TAB odds
3. The wrong horse's odds may be assigned
**Impact:** Incorrect odds displayed for selections; potential wrong bet settlement results.

### BUG-010: Race Results False Positive from Fuzzy Name + Number Matching
**File:** `DataService.swift:888-893`
**Severity:** Medium
**Description:** In `fetchRaceResults`, runner matching uses the same loose `.contains()` logic AND adds a fallback on `runnerNumber`. If a bet was logged with `runnerNumber: 0` (the default), it won't match on number, but could match the wrong horse by name substring.
**Steps to Reproduce:**
1. Log a bet for horse "Star" (runner number 0 due to default)
2. Race results come in with "Starlight" winning
3. "Star" (which may have lost) could be matched to "Starlight" and marked as a winner
**Impact:** Incorrect auto-settlement of bets (false wins or losses).

### BUG-011: scenePhase Reset Overwrites Manual Date Navigation
**File:** `TodayRacesView.swift:177-184`
**Severity:** Medium
**Description:** When the app returns to foreground, `onChange(of: scenePhase)` calls `dataService.goToToday()` if the selected date is not today. This means if a user is reviewing yesterday's races and switches to another app briefly, they'll lose their position when returning.
**Steps to Reproduce:**
1. Navigate to yesterday's races
2. Switch to another app
3. Return to EquiEdge
4. Date resets to today, losing the user's browsing context
**Impact:** Poor UX when reviewing historical data.

### BUG-012: Pending Win Bets Not Counted in Performance Win Rate
**File:** `PerformanceView.swift:17-21`
**Severity:** Medium
**Description:** The `winRate` calculation filters for `$0.result != nil` (settled) and counts `$0.result == "Won"`. But bets in "Pending Win" state have `result == "Pending Win"` which passes the `!= nil` filter but does NOT count as "Won". This deflates the win rate.
**Steps to Reproduce:**
1. Have a bet auto-detected as winner (status = "Pending Win")
2. Don't confirm the odds yet
3. Check Performance tab
4. The pending win counts as a loss in the denominator but not in the numerator
**Impact:** Inaccurate win rate and ROI statistics.

### BUG-013: Pending Win Bets Included in P&L With Zero Profit
**File:** `MyBetsView.swift:134-137`
**Severity:** Medium
**Description:** `todayPnL` sums `profit ?? 0` for all today's bets. A "Pending Win" bet has `profit == nil` (since odds haven't been confirmed), so it contributes $0 to P&L. Meanwhile its stake was already deducted from "Lost" bets. The P&L bar will show an inaccurate negative number until the win is confirmed.
**Steps to Reproduce:**
1. Place two bets today: one loses ($10 loss), one is a pending win
2. Today's P&L shows -$10 instead of reflecting the pending win
**Impact:** Misleading P&L display.

### BUG-014: Multiple DataService Instances via @StateObject
**File:** `TodayRacesView.swift:6`, `SettingsView.swift:11`, `ContentView.swift:7`
**Severity:** Medium
**Description:** `DataService.shared` is a singleton, but it's referenced via `@StateObject` in some views and `@ObservedObject` in others. `@StateObject` with a shared singleton is technically safe (it won't re-create the object), but mixing `@StateObject` and `@ObservedObject` for the same object across views is a code smell that may cause unexpected SwiftUI update behavior. Specifically, `MyBetsView` uses `@ObservedObject` while `TodayRacesView` and `SettingsView` use `@StateObject`.
**Steps to Reproduce:**
1. This is a structural issue - no immediate crash, but SwiftUI view lifecycle may behave unexpectedly
**Impact:** Potential UI not updating correctly in some views.

### BUG-015: ConfidenceThreshold AppStorage Not Used Anywhere
**File:** `SettingsView.swift:10`
**Severity:** Medium (Dead Code)
**Description:** `@AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.41` is declared in SettingsView but never used in any view or logic. There's no UI to adjust it, and AnalysisService doesn't reference it.
**Steps to Reproduce:**
1. Search codebase for "confidenceThreshold" usage beyond the declaration
**Impact:** Dead code; if threshold filtering was intended, it's not implemented.

### BUG-016: Cache Merge Doesn't Preserve Updated Suggestion Results
**File:** `DataService.swift:176-192`
**Severity:** Medium
**Description:** `mergeCacheData` replaces existing races whose IDs match new data. If the user has already settled bets (which updates `suggestion.result` in the cache via `updateCacheWithResults`), and then re-runs analysis for the same track, the new scrape data will overwrite the cache and lose the settled results.
**Steps to Reproduce:**
1. Run analysis for a track
2. Bet on a horse, and the bet settles as Won/Lost (cache updated)
3. Re-run analysis for the same track
4. The new scrape response replaces the old Race objects in cache
5. The Won/Lost results on suggestions are lost
**Impact:** Historical bet results disappear from the Races tab after re-analysis.

### BUG-017: Race.id is a Server-Supplied String - Potential Duplicates
**File:** `Models.swift:262`
**Severity:** Medium
**Description:** `Race.id` is a `String` supplied by the server (not a UUID). If the server generates IDs like "CAULFIELD-R1-2026-04-21", re-scraping the same race will produce the same ID. The merge logic handles this correctly. However, if the server ever returns an empty or null ID, the race would get an empty string ID, and ALL such races would collide.
**Steps to Reproduce:**
1. Inspect server responses for race ID format and edge cases
**Impact:** Potential data corruption if server sends malformed IDs.

### BUG-018: cacheRaceDataFromScrapeResponse Always Caches to "Today"
**File:** `DataService.swift:209`
**Severity:** Medium
**Description:** `cacheRaceDataFromScrapeResponse` always saves to `Self.startOfToday`. If the analysis is triggered just before midnight and completes after midnight, the data will be cached under the new day's date, not the race day.
**Steps to Reproduce:**
1. Start analysis at 11:58 PM
2. Analysis completes at 12:02 AM
3. Races from the old day get cached under the new day's date
**Impact:** Races appear under the wrong date in history.

---

## LOW SEVERITY ISSUES

### BUG-019: BetSuggestion.keyBadges Marked @Transient but Encoded in Codable
**File:** `Models.swift:21`
**Severity:** Low
**Description:** `keyBadges` is `@Transient` (SwiftData won't persist it) but is included in `CodingKeys` and gets encoded/decoded for JSON cache. This is intentionally working around SwiftData's inability to persist `[String]?` easily, but it's a maintenance trap - future developers may not understand why it's transient.
**Impact:** Code maintainability.

### BUG-020: Email Only Available on First Apple Sign-In
**File:** `AuthManager.swift:54`
**Severity:** Low
**Description:** Apple only provides the email on the FIRST sign-in. If the user deletes and reinstalls the app, `credential.email` will be nil on subsequent sign-ins. The code handles this via `email ?? response.email`, but if the backend also doesn't have the email stored, `userEmail` will remain nil.
**Steps to Reproduce:**
1. Sign in with Apple (email provided)
2. Delete and reinstall app
3. Sign in again - email may show as "Apple ID" instead of the actual email
**Impact:** Settings screen shows "Apple ID" instead of user's email.

### BUG-021: Log Polling Continues After Analysis Fails
**File:** `DataService.swift:365-366`
**Severity:** Low
**Description:** `startLogPolling()` is called in `refreshScrape()` with a `defer { stopLogPolling() }`. This correctly stops polling when the method returns. However, if the method throws before `startLogPolling()` is called (e.g., at the subscription guard on line 291), the defer still runs `stopLogPolling()` on a nil task, which is harmless but unnecessary.
**Impact:** No functional impact; minor code clarity issue.

### BUG-022: Moonee Valley Track Name Matching May Fail
**File:** `DataService.swift:679-684`
**Severity:** Low
**Description:** TAB meeting matching uses `name.contains(trackName)` and `trackName.contains(name)`. For multi-word tracks like "Moonee Valley", the scraper may return the track as "MOONEE VALLEY" but TAB may list it as "The Valley" or with different spacing. The matching logic doesn't account for common TAB venue name aliases.
**Steps to Reproduce:**
1. Select "Moonee Valley" track (if it existed in the selector - note it's currently missing)
2. Run analysis
3. TAB odds may fail to match because the venue mnemonic differs
**Impact:** No odds displayed for tracks with mismatched names.

### BUG-023: DateFormatter Locale Not Set - Potential Formatting Issues
**File:** `DataService.swift:116-120`, `SubscriptionManager.swift:324-328`
**Severity:** Low
**Description:** Multiple `DateFormatter` instances use `dateFormat = "yyyy-MM-dd"` without setting `locale = Locale(identifier: "en_US_POSIX")`. On some device locales, date formatting may produce unexpected results (e.g., different calendar systems).
**Steps to Reproduce:**
1. Change device locale to a non-Gregorian calendar (e.g., Arabic, Japanese)
2. Open the app
3. Date strings may not match expected format, breaking TAB API URLs and cache filenames
**Impact:** App may fail to load races or match cached data on non-Gregorian locale devices.

### BUG-024: SwipeToDelete Uses DispatchQueue Instead of Task
**File:** `MyBetsView.swift:22-25, 53-55`
**Severity:** Low
**Description:** `SwipeToDeleteModifier` uses `DispatchQueue.main.asyncAfter` for delayed deletion. While functional, this doesn't integrate with Swift Concurrency's structured approach and the delay is fire-and-forget (not cancellable).
**Impact:** Minor code quality issue; deletion animation could theoretically fire after view is dismissed.

### BUG-025: Performance View Includes "Pending Win" in Streak Calculation
**File:** `PerformanceView.swift:28-41`
**Severity:** Low
**Description:** The `bestStreak` calculation only resets on `result == "Lost"`. A "Pending Win" bet has `result == "Pending Win"` which doesn't match "Won" or "Lost", so it doesn't increment or reset the streak. This creates a gap in the streak that neither continues nor breaks it.
**Steps to Reproduce:**
1. Win 3 bets in a row
2. Next bet is "Pending Win"
3. Win next bet
4. Best streak shows 3 (not 5) because the pending win interrupted counting
**Impact:** Slightly inaccurate streak display.

### BUG-026: Runner Field List Doesn't Show Scratched State
**File:** `RaceDetailView.swift:228-291`
**Severity:** Low
**Description:** `RunnerRowCard` doesn't check or display whether a runner is scratched (`runner.scratched`). Scratched runners appear in the field list identically to active runners.
**Steps to Reproduce:**
1. Open a race detail where a runner is scratched
2. The scratched runner appears in the field list with no visual indicator
**Impact:** Users may tap on scratched runners without realizing they're scratched.

### BUG-027: PerformanceView Shows Emoji in Stats
**File:** `PerformanceView.swift:137`
**Severity:** Low (Consistency)
**Description:** The "Best Streak" stat card uses a fire emoji `"\(bestStreak)\u{1F525}"` which is inconsistent with the rest of the minimal design system that doesn't use emojis.
**Impact:** Minor design inconsistency.

### BUG-028: GrokSelectionsView File Named Incorrectly
**File:** `GrokSelectionsView.swift`
**Severity:** Low
**Description:** The file is named `GrokSelectionsView.swift` but the struct inside is `AISelectionsView`. The file name references an old naming convention ("Grok") that no longer matches the code.
**Impact:** Developer confusion; no runtime impact.

### BUG-029: No Offline Handling / Network Error Recovery
**File:** Various
**Severity:** Low (UX)
**Description:** There's no explicit handling for offline state. When TAB API calls fail, errors are silently logged. When the backend is unreachable, the error message is technical (`URLError` descriptions). There's no retry mechanism or user-facing offline indicator.
**Steps to Reproduce:**
1. Enable Airplane Mode
2. Try to run analysis or check results
3. Error messages are technical and unhelpful
**Impact:** Poor offline UX.

### BUG-030: Paywall Hardcoded Prices Don't Match StoreKit Products
**File:** `PaywallView.swift:157-158`
**Severity:** Low
**Description:** Prices are hardcoded as "$14.99", "$34.99", "$11.99", "$28.99" in the paywall UI. If the actual App Store prices change (or differ by region), the displayed prices won't match what the user is charged.
**Steps to Reproduce:**
1. Change App Store Connect pricing
2. Open paywall - old prices still displayed
**Impact:** Potential regulatory/compliance issue; user trust.

### BUG-031: TrackSelectorView Uses Non-Unique State Identifier
**File:** `TrackSelectorView.swift:719`
**Severity:** Low
**Description:** `ForEach(classGroup.stateGroups, id: \.stateCode)` uses `stateCode` as the identifier, but the same state code appears across multiple classification groups (e.g., "NSW" in Metro, Provincial, and Country). The `expandedStates` set uses `stateCode + classification.rawValue` as composite key (line 729), which is correct for expansion state, but the ForEach identifier may cause SwiftUI to confuse state groups.
**Steps to Reproduce:**
1. Open Track Selector
2. Expand NSW in Metro
3. Scroll to NSW in Provincial
4. SwiftUI may reuse the wrong cell due to matching stateCode
**Impact:** Potential visual glitches in track selector.

### BUG-032: Bet Record Display Shows Stale Runner Data
**File:** `RaceDetailView.swift:82-84`
**Severity:** Low
**Description:** Existing bet detection uses `$0.raceInfo == raceInfo && $0.horseName == suggestion.horseName`. If a horse's name is updated between scrapes (e.g., name correction), the bet won't match and the user could accidentally log a duplicate bet.
**Steps to Reproduce:**
1. Log a bet for a horse
2. Re-run analysis (server may return slightly different horse name formatting)
3. The "Bet Logged" indicator may not appear, allowing duplicate bet logging
**Impact:** Duplicate bets in the bet log.

---

## SUMMARY

| Severity | Count |
|----------|-------|
| Critical | 3     |
| High     | 5     |
| Medium   | 10    |
| Low      | 14    |
| **Total**| **32**|

### Top Priority Fixes
1. **BUG-007** - Basic Monthly subscription cannot be purchased (revenue blocker)
2. **BUG-001** - API key exposed in source code
3. **BUG-002** - userId used as auth token (security)
4. **BUG-003** - URLSession created on every call (resource leak)
5. **BUG-009/010** - Fuzzy horse name matching can cause wrong odds/settlement
