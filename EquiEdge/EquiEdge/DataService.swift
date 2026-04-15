import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class DataService: ObservableObject {
    static let shared = DataService()

    /// Creates a JSONDecoder that handles ISO 8601 dates with and without fractional seconds
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = isoFull.date(from: str) { return date }
            if let date = isoBasic.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(str)")
        }
        return decoder
    }
    
    @Published private(set) var races: [Race] = []
    @Published private(set) var allRaces: [Race] = []
    @Published private(set) var suggestionsByRaceID: [String: [BetSuggestion]] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedDate: Date = DataService.startOfToday

    @Published private(set) var logs: [String] = []
    private var logPollingTask: Task<Void, Never>?

    // Analysis progress state (persists across tab switches)
    @Published var analysisProgress: Double = 0
    @Published var showProgressBar = false
    @Published var analysisProgressMessage: String = ""
    @Published var isAnalysisComplete = false
    @Published var isAnalysing = false
    @Published var tooEarlyTrackNames: [String] = []

    @MainActor
    func clearLogs() {
        logs.removeAll()
        localLogs.removeAll()
    }

    @MainActor
    private func log(_ message: String) {
        localLogs.append(message)
        logs.append(message)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
    
    /// Local log lines that should persist across server log polling
    private var localLogs: [String] = []

    @MainActor
    private func fetchServerLogs() async {
        guard let url = URL(string: "\(baseURL)/logs") else { return }
        do {
            let request = authenticatedRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let serverLines = try? JSONDecoder().decode([String].self, from: data) {
                // Merge: local logs first, then server logs
                if !serverLines.isEmpty {
                    self.logs = localLogs + serverLines
                }
            }
        } catch {
            // Silently ignore polling failures
        }
    }
    
    @MainActor
    private func startLogPolling() {
        logPollingTask?.cancel()
        logPollingTask = Task {
            while !Task.isCancelled {
                await fetchServerLogs()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    
    @MainActor
    private func stopLogPolling() {
        logPollingTask?.cancel()
        logPollingTask = nil
    }
    
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    
    private let baseURL = "https://equiedge-scraper.vercel.app"
    private let apiKey: String = {
        // Read from Info.plist or fallback to hardcoded key
        Bundle.main.object(forInfoDictionaryKey: "EQUIEDGE_API_KEY") as? String ?? ""
    }()

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600    // 10 minutes
        config.timeoutIntervalForResource = 660   // 11 minutes
        return URLSession(configuration: config)
    }

    /// Creates an authenticated URLRequest with the API key header
    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    var isShowingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    // MARK: - Per-date cache
    
    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("equiedge_races", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private static func cacheFileURL(for date: Date) -> URL {
        let dateStr = dateFormatter.string(from: date)
        return cacheDirectory.appendingPathComponent("races_\(dateStr).json")
    }
    
    /// All dates that have cached race data, sorted newest first
    var cachedDates: [Date] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.cacheDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> Date? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("races_") else { return nil }
            let dateStr = String(name.dropFirst(6))
            return Self.dateFormatter.date(from: dateStr)
        }.sorted(by: >)
    }
    
    private func saveToCache(_ data: Data, for date: Date) {
        try? data.write(to: Self.cacheFileURL(for: date))
    }
    
    private func loadFromCache(for date: Date) -> Data? {
        try? Data(contentsOf: Self.cacheFileURL(for: date))
    }
    
    /// Returns the set of track slugs (lowercased, hyphenated) already cached for a given date
    func cachedTrackSlugs(for date: Date) -> Set<String> {
        guard let data = loadFromCache(for: date) else { return [] }
        let decoder = Self.makeDecoder()
        guard let races = try? decoder.decode([Race].self, from: data) else { return [] }
        // Convert track names (e.g. "CAULFIELD") to slug form (e.g. "caulfield")
        return Set(races.map { $0.track.lowercased().replacingOccurrences(of: " ", with: "-") })
    }

    /// Merges new races into existing cached data for a date, deduplicating by race id
    private func mergeCacheData(existing: Data?, new: Data) -> Data {
        let decoder = Self.makeDecoder()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let newRaces = (try? decoder.decode([Race].self, from: new)) ?? []
        guard let existing, let existingRaces = try? decoder.decode([Race].self, from: existing) else {
            return new
        }

        let newIDs = Set(newRaces.map { $0.id })
        // Keep existing races that aren't replaced by new data
        let kept = existingRaces.filter { !newIDs.contains($0.id) }
        let merged = kept + newRaces

        return (try? encoder.encode(merged)) ?? new
    }

    init() {}

    // MARK: - Date Navigation
    
    @MainActor
    func goToPreviousDay() {
        let cal = Calendar.current
        if let previous = cal.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = previous
            loadRacesForSelectedDate()
        }
    }

    @MainActor
    func goToNextDay() {
        guard !isShowingToday else { return }
        let cal = Calendar.current
        if let next = cal.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = next
            loadRacesForSelectedDate()
        }
    }

    var canGoBack: Bool {
        return true
    }

    var canGoForward: Bool {
        // Can always go forward if we're not on today
        if !isShowingToday { return true }
        return false
    }

    @MainActor
    func goToToday() {
        selectedDate = Self.startOfToday
        loadRacesForSelectedDate()
    }
    
    @MainActor
    private func loadRacesForSelectedDate() {
        if let cached = loadFromCache(for: selectedDate) {
            processRaceData(cached)
        } else {
            self.races = []
            self.allRaces = []
            self.suggestionsByRaceID = [:]
        }
    }
    
    // MARK: - Loading
    
    @MainActor
    func loadCachedRaces() {
        // Load from local cache only — never hit the API here
        if let cached = loadFromCache(for: selectedDate) {
            log("Loading races from local cache…")
            processRaceData(cached)
        }
    }
    
    @MainActor
    func refreshScrape(forceFullScrape: Bool = false) async throws {
        let selectedTracks = TrackSelection.shared.selectedSlugs

        logs.removeAll()
        localLogs.removeAll()

        guard !selectedTracks.isEmpty else {
            log("ERROR: No racetracks have been selected to analyse")
            errorMessage = "No racetracks have been selected to analyse"
            throw URLError(.badURL)
        }

        // Determine which tracks actually need analysis
        let tracksToScrape: Set<String>
        if forceFullScrape {
            tracksToScrape = selectedTracks
            log("Full re-analysis requested for \(tracksToScrape.count) tracks")
        } else {
            let alreadyCached = cachedTrackSlugs(for: Self.startOfToday)
            tracksToScrape = selectedTracks.subtracting(alreadyCached)
            if tracksToScrape.isEmpty {
                log("All \(selectedTracks.count) selected tracks already analysed for today")
                log("Use 'Re-analyse All Tracks' to force refresh")
                // Still load/process cached data so UI is up to date
                selectedDate = Self.startOfToday
                loadRacesForSelectedDate()
                return
            }
            let skipped = selectedTracks.intersection(alreadyCached)
            if !skipped.isEmpty {
                log("Skipping \(skipped.count) already-analysed tracks: \(skipped.sorted().joined(separator: ", "))")
            }
        }

        log("Starting AI analysis for \(tracksToScrape.count) track(s)…")

        // Fetch TAB schedule to determine future races and skip past ones
        log("Checking TAB schedule for upcoming races…")
        let schedule = await fetchTABSchedule(for: tracksToScrape)

        // Filter out tracks whose first race is more than 1 hour away
        let oneHourFromNow = Date().addingTimeInterval(60 * 60)
        var tooEarlySlugs: [String] = []
        var allowedTracks = tracksToScrape
        if schedule.succeeded {
            for (slug, firstTime) in schedule.firstRaceTime {
                if firstTime > oneHourFromNow {
                    tooEarlySlugs.append(slug)
                    allowedTracks.remove(slug)
                }
            }
            if !tooEarlySlugs.isEmpty {
                let names = tooEarlySlugs.sorted().map { slug in
                    slug.replacingOccurrences(of: "-", with: " ").capitalized
                }
                tooEarlyTrackNames = names
                log("Skipping \(names.count) tracks (first race >1hr away): \(names.joined(separator: ", "))")
                if allowedTracks.isEmpty {
                    // All tracks too early — nothing to scrape
                    selectedDate = Self.startOfToday
                    loadRacesForSelectedDate()
                    return
                }
            }
        }

        let raceFilterParam = buildRaceFilterParam(from: schedule.futureRaces.filter { allowedTracks.contains($0.key) })

        if schedule.succeeded && schedule.futureRaces.filter({ allowedTracks.contains($0.key) }).isEmpty {
            // TAB API worked but found 0 upcoming races — all races are done for today
            log("No upcoming races found — all races have already run")
            log("Use 'Re-analyse All Tracks' to force a full refresh if needed")
            selectedDate = Self.startOfToday
            loadRacesForSelectedDate()
            return
        } else if !schedule.succeeded {
            // TAB API failed — proceed without filter as graceful fallback
            log("TAB schedule unavailable — proceeding with full scrape (no race filter)")
        }

        let tracksParam = allowedTracks.sorted().joined(separator: ",")
        var urlString = "\(baseURL)/scrape-now?ai=true&tracks=\(tracksParam)"
        if let filter = raceFilterParam {
            urlString += "&raceFilter=\(filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filter)"
            log("Race filter: \(filter)")
        }
        guard let url = URL(string: urlString) else {
            log("ERROR: Invalid scrape URL")
            throw URLError(.badURL)
        }
        
        // Start polling server logs while scrape runs
        startLogPolling()
        
        defer { stopLogPolling() }
        
        do {
            let request = authenticatedRequest(url: url)
            let (data, response) = try await session.data(for: request)

            // One final log fetch to get everything
            await fetchServerLogs()

            guard let httpResponse = response as? HTTPURLResponse else {
                log("ERROR: Non-HTTP response")
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode == 200 {
                log("Analysis complete. Loading races…")
                selectedDate = Self.startOfToday
                try? await loadTodayRaces()
                log("Done — \(races.count) races with picks, \(allRaces.count) total")
            } else {
                log("ERROR: Server returned \(httpResponse.statusCode)")
                if let body = String(data: data, encoding: .utf8) {
                    log(body)
                }
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }
        } catch {
            await fetchServerLogs()
            log("ERROR: \(error.localizedDescription)")
            throw error
        }
    }
    
    @MainActor
    func loadTodayRaces() async throws {
        guard let url = URL(string: "\(baseURL)/today-races?ai=true") else {
            errorMessage = "Invalid races URL"
            isLoading = false
            return
        }

        log("Loading today's races…")
        isLoading = true
        errorMessage = nil
        
        do {
            let request = authenticatedRequest(url: url)
            let (data, _) = try await session.data(for: request)

            let decoder = Self.makeDecoder()

            let decoded = try decoder.decode([Race].self, from: data)
            log("Decoded races: \(decoded.count)")
            
            // Only save to cache and update UI if the API returned actual races
            // so we never overwrite good cached data with an empty response
            guard !decoded.isEmpty else {
                log("No races returned from API — keeping existing cache")
                isLoading = false
                return
            }

            // Merge new races with existing cached data (additive scraping)
            let existingData = loadFromCache(for: Self.startOfToday)
            let mergedData = mergeCacheData(existing: existingData, new: data)
            saveToCache(mergedData, for: Self.startOfToday)
            if isShowingToday {
                processRaceData(mergedData)
                // Fetch TAB fixed win odds for suggestions (runs from user's AU device)
                await fetchTABOdds(for: self.races)
            }
            
        } catch {
            print("❌ Failed to load races: \(error)")
            errorMessage = "Failed to load races: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - TAB Odds Fetching (client-side, runs from Australian device)
    
    /// Fetch live TAB fixed win odds for the current races (today only)
    @MainActor
    func fetchLiveOdds() async {
        guard isShowingToday, !races.isEmpty else { return }
        await fetchTABOdds(for: self.races)
        // Force UI refresh since fixedWinOdds is set on existing objects
        objectWillChange.send()
    }
    
    /// Result of a TAB schedule fetch
    struct TABScheduleResult {
        let futureRaces: [String: [Int]]
        let succeeded: Bool  // true if TAB API was reachable and returned data
        let firstRaceTime: [String: Date]  // earliest race start per track slug
    }

    /// Fetches the TAB meetings schedule and returns a dict of { trackSlug: [futureRaceNumbers] }
    /// plus sets raceStartTime on any already-loaded races. Used before triggering a scrape.
    func fetchTABSchedule(for tracks: Set<String>) async -> TABScheduleResult {
        let dateStr = Self.dateFormatter.string(from: Date())
        let meetingsURL = "https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/\(dateStr)/meetings?jurisdiction=NSW"

        guard let url = URL(string: meetingsURL) else { return TABScheduleResult(futureRaces: [:], succeeded: false, firstRaceTime: [:]) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meetings = json["meetings"] as? [[String: Any]] else {
                log("TAB schedule: failed to fetch")
                return TABScheduleResult(futureRaces: [:], succeeded: false, firstRaceTime: [:])
            }

            let thoroughbredMeetings = meetings.filter { ($0["raceType"] as? String) == "R" }
            let venueNames = thoroughbredMeetings.compactMap { $0["meetingName"] as? String }
            log("TAB schedule: \(thoroughbredMeetings.count) meetings — \(venueNames.joined(separator: ", "))")
            log("TAB schedule: matching against tracks: \(tracks.sorted().joined(separator: ", "))")

            let isoFull = ISO8601DateFormatter()
            isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]

            let now = Date()
            let buffer: TimeInterval = 5 * 60 // 5 min buffer
            var futureRaces: [String: [Int]] = [:]
            var firstRaceTime: [String: Date] = [:]

            for trackSlug in tracks {
                let trackName = trackSlug.lowercased().replacingOccurrences(of: "-", with: " ")

                // Find matching TAB meeting (exact match only to avoid e.g. "newcastle" matching "newcastle uk")
                guard let meeting = thoroughbredMeetings.first(where: { m in
                    let name = (m["meetingName"] as? String ?? "").lowercased()
                    let mnemonic = (m["venueMnemonic"] as? String ?? "").lowercased()
                    let nameSlug = name.replacingOccurrences(of: " ", with: "-")
                    return name == trackName || nameSlug == trackSlug.lowercased() || mnemonic == trackSlug.lowercased()
                }) else {
                    log("TAB schedule: no match for '\(trackSlug)'")
                    continue
                }

                guard let tabRaces = meeting["races"] as? [[String: Any]] else { continue }

                var upcoming: [Int] = []
                for tabRace in tabRaces {
                    guard let raceNum = tabRace["raceNumber"] as? Int,
                          let timeStr = tabRace["raceStartTime"] as? String,
                          let startTime = isoFull.date(from: timeStr) ?? isoBasic.date(from: timeStr) else { continue }

                    // Track earliest race time for this track
                    if let existing = firstRaceTime[trackSlug] {
                        if startTime < existing { firstRaceTime[trackSlug] = startTime }
                    } else {
                        firstRaceTime[trackSlug] = startTime
                    }

                    // Also set raceStartTime on any already-loaded Race objects
                    if let existing = self.races.first(where: { $0.track.lowercased().replacingOccurrences(of: " ", with: "-") == trackSlug && $0.raceNumber == raceNum }) {
                        existing.raceStartTime = startTime
                    }

                    if startTime.timeIntervalSince(now) > -buffer {
                        upcoming.append(raceNum)
                    }
                }

                if !upcoming.isEmpty {
                    futureRaces[trackSlug] = upcoming.sorted()
                }
            }

            let totalFuture = futureRaces.values.reduce(0) { $0 + $1.count }
            log("TAB schedule: \(totalFuture) upcoming races across \(futureRaces.count) tracks")
            return TABScheduleResult(futureRaces: futureRaces, succeeded: true, firstRaceTime: firstRaceTime)
        } catch {
            log("TAB schedule: \(error.localizedDescription)")
            return TABScheduleResult(futureRaces: [:], succeeded: false, firstRaceTime: [:])
        }
    }

    /// Builds the raceFilter query param string: "caulfield:3,4,5;randwick:2,3,4"
    private func buildRaceFilterParam(from schedule: [String: [Int]]) -> String? {
        guard !schedule.isEmpty else { return nil }
        return schedule.map { track, nums in
            "\(track):\(nums.map(String.init).joined(separator: ","))"
        }.joined(separator: ";")
    }

    /// Normalise a horse name for fuzzy matching: lowercase, strip country suffixes like "(NZ)", trim whitespace
    private func normaliseHorseName(_ name: String) -> String {
        var n = name.lowercased()
        // Remove country suffixes like "(NZ)", "(IRE)", "(GB)", "(USA)"
        if let range = n.range(of: #"\s*\([a-z]{2,4}\)\s*$"#, options: .regularExpression) {
            n.removeSubrange(range)
        }
        return n.trimmingCharacters(in: .whitespaces)
    }
    
    private func fetchTABOdds(for races: [Race]) async {
        guard !races.isEmpty else { return }

        let dateStr = Self.dateFormatter.string(from: Date())
        let meetingsURL = "https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/\(dateStr)/meetings?jurisdiction=NSW"

        guard let url = URL(string: meetingsURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                log("TAB odds: non-200 response")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meetings = json["meetings"] as? [[String: Any]] else {
                log("TAB odds: unexpected response format")
                return
            }

            // Filter to thoroughbred meetings only (raceType "R")
            let thoroughbredMeetings = meetings.filter { ($0["raceType"] as? String) == "R" }
            log("TAB odds: \(thoroughbredMeetings.count) thoroughbred meetings (of \(meetings.count) total)")

            // Log venue names for debugging
            let venueNames = thoroughbredMeetings.compactMap { m -> String? in
                let name = m["meetingName"] as? String ?? "?"
                let mnemonic = m["venueMnemonic"] as? String ?? "?"
                return "\(name)[\(mnemonic)]"
            }
            log("TAB venues: \(venueNames.joined(separator: ", "))")

            // ISO 8601 date formatter for race start times
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFallback = ISO8601DateFormatter()
            isoFallback.formatOptions = [.withInternetDateTime]

            var oddsFound = 0
            var timesFound = 0

            // Process ALL races (for times), but only fetch detail for those with picks (for odds)
            let racesWithPicks = Set(races.filter { race in
                !(suggestionsByRaceID[String(describing: race.id)] ?? []).isEmpty
            }.map(\.id))

            for race in races {
                // Our track name is uppercase from server.js (e.g. "CAULFIELD", "MOONEE VALLEY")
                let trackName = race.track.lowercased()

                // Find matching TAB meeting
                let meeting = thoroughbredMeetings.first { m in
                    let name = (m["meetingName"] as? String ?? "").lowercased()
                    let mnemonic = (m["venueMnemonic"] as? String ?? "").lowercased()
                    return name == trackName || name.contains(trackName) || trackName.contains(name)
                        || mnemonic == trackName
                }
                
                guard let meeting else {
                    log("TAB: no match for '\(trackName)'")
                    continue
                }

                let venueMnemonic = meeting["venueMnemonic"] as? String ?? ""
                let raceType = meeting["raceType"] as? String ?? "R"
                let meetingName = meeting["meetingName"] as? String ?? "?"

                // ── Extract race start time from meeting-level races array ──
                if let meetingRaces = meeting["races"] as? [[String: Any]] {
                    if let tabRace = meetingRaces.first(where: { ($0["raceNumber"] as? Int) == race.raceNumber }),
                       let timeStr = tabRace["raceStartTime"] as? String {
                        if let parsed = isoFormatter.date(from: timeStr) ?? isoFallback.date(from: timeStr) {
                            race.raceStartTime = parsed
                            timesFound += 1
                        }
                    }
                }

                // ── Only fetch race detail (for odds) if this race has picks ──
                guard racesWithPicks.contains(race.id) else { continue }

                let suggestions = suggestionsByRaceID[String(describing: race.id)] ?? []
                guard !suggestions.isEmpty else { continue }

                log("TAB odds: '\(trackName)' -> \(meetingName)[\(venueMnemonic)]")

                // Construct race detail URL directly (more reliable than _links parsing)
                let raceDetailURLStr = "https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/\(dateStr)/meetings/\(raceType)/\(venueMnemonic)/races/\(race.raceNumber)?jurisdiction=NSW"

                guard let detailURL = URL(string: raceDetailURLStr) else { continue }

                var detailRequest = URLRequest(url: detailURL)
                detailRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                detailRequest.timeoutInterval = 10

                guard let (detailData, detailResp) = try? await URLSession.shared.data(for: detailRequest),
                      let detailHTTP = detailResp as? HTTPURLResponse, detailHTTP.statusCode == 200,
                      let raceDetail = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                      let runners = raceDetail["runners"] as? [[String: Any]], !runners.isEmpty else {
                    log("TAB odds: failed to fetch R\(race.raceNumber) at \(venueMnemonic)")
                    continue
                }

                log("TAB odds: \(runners.count) runners in \(meetingName) R\(race.raceNumber)")

                // Match each suggested horse to a TAB runner
                for suggestion in suggestions {
                    let target = normaliseHorseName(suggestion.horseName)

                    let runner = runners.first { r in
                        let name = normaliseHorseName(r["runnerName"] as? String ?? r["name"] as? String ?? "")
                        return name == target || name.contains(target) || target.contains(name)
                    }

                    guard let runner else {
                        let sampleNames = runners.prefix(5).compactMap { $0["runnerName"] as? String ?? $0["name"] as? String }
                        log("TAB odds: '\(suggestion.horseName)' not found. Runners: \(sampleNames)")
                        continue
                    }

                    // Extract fixed win odds
                    if let fixedOdds = runner["fixedOdds"] as? [String: Any],
                       let returnWin = fixedOdds["returnWin"] as? Double, returnWin > 0 {
                        suggestion.fixedWinOdds = returnWin
                        log("TAB odds: \(suggestion.horseName) = $\(String(format: "%.2f", returnWin))")
                        oddsFound += 1
                    } else {
                        log("TAB odds: no fixedOdds for \(runner["runnerName"] as? String ?? "?")")
                    }
                }
            }

            log("TAB: \(timesFound) race times, \(oddsFound) prices found")
        } catch {
            log("TAB: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Race Result Fetching (client-side, auto-settle bets)

    /// Parse "TRACK R3" into (track: "TRACK", raceNumber: 3)
    private static func parseRaceInfo(_ info: String) -> (track: String, raceNumber: Int) {
        guard let range = info.range(of: " R", options: .backwards) else {
            return (info, 0)
        }
        let track = String(info[info.startIndex..<range.lowerBound])
        let num = Int(info[range.upperBound...]) ?? 0
        return (track, num)
    }

    /// Fetch TAB race results for unsettled bets and auto-mark them.
    /// - Losers are auto-settled with profit = -amount
    /// - Winners become "Pending Win" with prefilled odds (user must confirm)
    /// - Also updates the race cache so results show in Races tab history
    @MainActor
    func fetchRaceResults(bets: [BetRecord], in modelContext: ModelContext) async {
        let unsettled = bets.filter { $0.result == nil }
        guard !unsettled.isEmpty else {
            log("Results: no unsettled bets to check")
            return
        }
        log("Results: checking \(unsettled.count) unsettled bets…")

        // Group bets by date string -> raceInfo -> [BetRecord]
        let grouped: [String: [String: [BetRecord]]] = {
            var dict: [String: [String: [BetRecord]]] = [:]
            for bet in unsettled {
                let dateStr = Self.dateFormatter.string(from: bet.date)
                dict[dateStr, default: [:]][bet.raceInfo, default: []].append(bet)
            }
            return dict
        }()

        var totalSettled = 0
        var totalPendingWins = 0

        for (dateStr, raceGroups) in grouped {
            let meetingsURL = "https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/\(dateStr)/meetings?jurisdiction=NSW"
            guard let url = URL(string: meetingsURL) else { continue }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meetings = json["meetings"] as? [[String: Any]] else {
                continue
            }

            let thoroughbredMeetings = meetings.filter { ($0["raceType"] as? String) == "R" }
            log("Results: \(thoroughbredMeetings.count) thoroughbred meetings for \(dateStr)")

            // Track cache updates: [raceInfo: [(horseName, result)]]
            var cacheUpdates: [(trackName: String, raceNumber: Int, horseName: String, result: String)] = []

            for (raceInfo, betsInRace) in raceGroups {
                let (trackName, raceNumber) = Self.parseRaceInfo(raceInfo)
                let trackLower = trackName.lowercased()

                // Find matching TAB meeting
                guard let meeting = thoroughbredMeetings.first(where: { m in
                    let name = (m["meetingName"] as? String ?? "").lowercased()
                    let mnemonic = (m["venueMnemonic"] as? String ?? "").lowercased()
                    return name == trackLower || name.contains(trackLower) || trackLower.contains(name)
                        || mnemonic == trackLower
                }) else {
                    log("Results: no TAB match for '\(trackName)'")
                    continue
                }

                let venueMnemonic = meeting["venueMnemonic"] as? String ?? ""
                let raceType = meeting["raceType"] as? String ?? "R"

                let raceDetailURLStr = "https://api.beta.tab.com.au/v1/tab-info-service/racing/dates/\(dateStr)/meetings/\(raceType)/\(venueMnemonic)/races/\(raceNumber)?jurisdiction=NSW"
                guard let detailURL = URL(string: raceDetailURLStr) else { continue }

                var detailRequest = URLRequest(url: detailURL)
                detailRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                detailRequest.timeoutInterval = 10

                log("Results: fetching \(raceInfo) from TAB [\(venueMnemonic)]…")

                guard let (detailData, detailResp) = try? await URLSession.shared.data(for: detailRequest),
                      let detailHTTP = detailResp as? HTTPURLResponse, detailHTTP.statusCode == 200,
                      let raceDetail = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                      let runners = raceDetail["runners"] as? [[String: Any]], !runners.isEmpty else {
                    log("Results: failed to fetch \(raceInfo) detail")
                    continue
                }

                // Check if the race has results — raceStatus or race-level results array
                let raceStatus = (raceDetail["raceStatus"] as? String ?? "").lowercased()
                let resultsArray = raceDetail["results"] as? [[Any]] ?? []
                let hasResults = !resultsArray.isEmpty
                    || raceStatus == "resulted" || raceStatus == "paying" || raceStatus == "paid"
                    || raceStatus == "final" || raceStatus == "interim"
                guard hasResults else {
                    log("Results: \(raceInfo) not yet resulted (status: \(raceStatus))")
                    continue
                }

                // Build position map from race-level results: [[8], [11], [15], [4]] → {8: 1, 11: 2, 15: 3, 4: 4}
                var positionByRunnerNumber: [Int: Int] = [:]
                for (index, place) in resultsArray.enumerated() {
                    for entry in place {
                        if let num = entry as? Int {
                            positionByRunnerNumber[num] = index + 1
                        } else if let num = entry as? Double {
                            positionByRunnerNumber[Int(num)] = index + 1
                        }
                    }
                }
                let winnerNumbers = positionByRunnerNumber.filter { $0.value == 1 }.map { $0.key }
                log("Results: \(raceInfo) (status: \(raceStatus)) — winner runner#: \(winnerNumbers)")

                for bet in betsInRace {
                    let target = normaliseHorseName(bet.horseName)

                    let runner = runners.first { r in
                        let name = normaliseHorseName(r["runnerName"] as? String ?? r["name"] as? String ?? "")
                        let num = r["runnerNumber"] as? Int ?? r["tabNo"] as? Int ?? 0
                        return name == target || name.contains(target) || target.contains(name)
                            || (bet.runnerNumber > 0 && num == bet.runnerNumber)
                    }

                    guard let runner else {
                        log("Results: '\(bet.horseName)' not found in TAB runners")
                        continue
                    }

                    let runnerNum = runner["runnerNumber"] as? Int ?? 0
                    let finishPos = positionByRunnerNumber[runnerNum] ?? 0
                    if finishPos == 1 {
                        bet.result = "Pending Win"
                        // Prefill odds from TAB fixed win if available
                        if let fixedOdds = runner["fixedOdds"] as? [String: Any],
                           let returnWin = fixedOdds["returnWin"] as? Double, returnWin > 0 {
                            bet.odds = returnWin
                            log("Results: \(bet.horseName) WON @ $\(String(format: "%.2f", returnWin)) — pending confirmation")
                        } else {
                            log("Results: \(bet.horseName) WON — pending odds confirmation")
                        }
                        totalPendingWins += 1
                        cacheUpdates.append((trackName, raceNumber, bet.horseName, "Won"))
                    } else {
                        bet.result = "Lost"
                        bet.profit = -bet.amount
                        totalSettled += 1
                        log("Results: \(bet.horseName) finished #\(finishPos) — Lost")
                        cacheUpdates.append((trackName, raceNumber, bet.horseName, "Lost"))
                    }
                }
            }

            // Persist results into the race cache for this date
            if !cacheUpdates.isEmpty, let date = Self.dateFormatter.date(from: dateStr) {
                updateCacheWithResults(cacheUpdates, for: date)
            }
        }

        log("Results: \(totalSettled) lost, \(totalPendingWins) pending wins")
        if totalSettled > 0 || totalPendingWins > 0 {
            try? modelContext.save()
        }
    }

    /// Update the race cache with result data so Races tab shows won/lost on historical picks
    @MainActor
    private func updateCacheWithResults(_ updates: [(trackName: String, raceNumber: Int, horseName: String, result: String)], for date: Date) {
        guard let data = loadFromCache(for: date) else {
            log("Results cache: no cache file for date")
            return
        }
        let decoder = Self.makeDecoder()
        guard let races = try? decoder.decode([Race].self, from: data) else {
            log("Results cache: failed to decode cache")
            return
        }

        var matched = 0
        for update in updates {
            guard let race = races.first(where: {
                $0.track.lowercased() == update.trackName.lowercased() && $0.raceNumber == update.raceNumber
            }) else {
                log("Results cache: no race match for \(update.trackName) R\(update.raceNumber) (tracks: \(races.map { $0.track }))")
                continue
            }

            let target = normaliseHorseName(update.horseName)
            if let suggestion = race.suggestions.first(where: {
                normaliseHorseName($0.horseName) == target
            }) {
                suggestion.result = update.result
                matched += 1
                log("Results cache: \(update.horseName) → \(update.result)")
            } else {
                log("Results cache: horse '\(update.horseName)' not in suggestions for \(update.trackName) R\(update.raceNumber)")
            }
        }
        log("Results cache: updated \(matched)/\(updates.count) suggestions")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let updatedData = try? encoder.encode(races) {
            saveToCache(updatedData, for: date)
            // Refresh UI if viewing this date
            if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                processRaceData(updatedData)
            }
        }
    }

    @MainActor
    private func processRaceData(_ data: Data) {
        let decoder = Self.makeDecoder()

        guard let races = try? decoder.decode([Race].self, from: data) else { return }

        var newSuggestions: [String: [BetSuggestion]] = [:]
        for race in races {
            let suggestions = AnalysisService.shared.analyze(race: race)
            if !suggestions.isEmpty {
                newSuggestions[String(describing: race.id)] = suggestions
            }
        }
        log("Computed suggestions for \(newSuggestions.count) races")
        self.suggestionsByRaceID = newSuggestions
        self.allRaces = races
        self.races = races.filter { newSuggestions[String(describing: $0.id)]?.isEmpty == false }
        log("Filtered to \(self.races.count) races with picks")
        
        print("✅ Successfully loaded \(self.races.count) races")
    }
}

