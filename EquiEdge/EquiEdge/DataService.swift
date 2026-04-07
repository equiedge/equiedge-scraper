import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
final class DataService: ObservableObject {
    static let shared = DataService()
    
    @Published private(set) var races: [Race] = []
    @Published private(set) var allRaces: [Race] = []
    @Published private(set) var suggestionsByRaceID: [String: [BetSuggestion]] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedDate: Date = DataService.startOfToday

    @Published private(set) var logs: [String] = []

    private let _tsFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @MainActor
    func clearLogs() {
        logs.removeAll()
    }

    @MainActor
    private func log(_ message: String) {
        let ts = _tsFormatter.string(from: Date())
        logs.append("[\(ts)] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
    
    @AppStorage("useAI") private var useAI: Bool = true
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    
    private let baseURL = "https://equiedge-scraper.vercel.app"
    
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240    // 4 minutes
        config.timeoutIntervalForResource = 300   // 5 minutes
        return URLSession(configuration: config)
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
    
    init() {}
    
    // MARK: - Date Navigation
    
    @MainActor
    func goToPreviousDay() {
        let dates = cachedDates
        guard let currentIndex = dates.firstIndex(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }) else {
            // Current date not in cache — go to most recent cached date before selectedDate
            if let earlier = dates.first(where: { $0 < selectedDate }) {
                selectedDate = earlier
                loadRacesForSelectedDate()
            }
            return
        }
        let nextIndex = currentIndex + 1 // cachedDates sorted newest first
        if nextIndex < dates.count {
            selectedDate = dates[nextIndex]
            loadRacesForSelectedDate()
        }
    }
    
    @MainActor
    func goToNextDay() {
        let dates = cachedDates
        guard let currentIndex = dates.firstIndex(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }) else { return }
        let prevIndex = currentIndex - 1 // cachedDates sorted newest first
        if prevIndex >= 0 {
            selectedDate = dates[prevIndex]
            loadRacesForSelectedDate()
        }
    }
    
    var canGoBack: Bool {
        let dates = cachedDates
        guard let currentIndex = dates.firstIndex(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }) else {
            return dates.contains(where: { $0 < selectedDate })
        }
        return currentIndex + 1 < dates.count
    }
    
    var canGoForward: Bool {
        let dates = cachedDates
        guard let currentIndex = dates.firstIndex(where: {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        }) else { return false }
        return currentIndex - 1 >= 0
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
    func loadCachedRaces() async {
        // Load from local cache first so races appear immediately
        if let cached = loadFromCache(for: selectedDate) {
            log("Loading races from local cache…")
            processRaceData(cached)
        }
        // Only fetch fresh data from API if viewing today
        if isShowingToday {
            try? await loadTodayRaces()
        }
    }
    
    @MainActor
    func refreshScrape() async {
        let aiEnabled = UserDefaults.standard.bool(forKey: "useAI")
        log("AI: \(aiEnabled ? "enabled" : "disabled")")
        
        log("Refreshing scrape…")
        let urlString: String
        if aiEnabled {
            urlString = "\(baseURL)/scrape-now?ai=true"
        } else {
            urlString = "\(baseURL)/scrape-now"
        }
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return }
            print("🔍 Scrape-now HTTP status: \(httpResponse.statusCode)")
            log("scrape-now status: \(httpResponse.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                print("🔍 Response body: \(body)")
            }
            if httpResponse.statusCode == 200 {
                log("Scrape succeeded. Reloading races…")
                print("✅ Manual scrape triggered successfully")
                // Reset to today before loading
                selectedDate = Self.startOfToday
                try? await loadTodayRaces()
            }
        } catch {
            print("❌ refreshScrape error: \(error)")
            log("refreshScrape error: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    func loadTodayRaces() async throws {
        let aiEnabled = UserDefaults.standard.bool(forKey: "useAI")
        let aiParam = aiEnabled ? "true" : "false"
        guard let url = URL(string: "\(baseURL)/today-races?ai=\(aiParam)") else {
            errorMessage = "Invalid races URL"
            isLoading = false
            return
        }
        
        log("AI: \(aiEnabled ? "enabled" : "disabled")")
        log("Loading today's races…")
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, _) = try await session.data(from: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let decoded = try decoder.decode([Race].self, from: data)
            log("Decoded races: \(decoded.count)")
            
            // Only update if we got data — don't wipe existing races with empty response
            if !decoded.isEmpty {
                saveToCache(data, for: Self.startOfToday)
                if isShowingToday {
                    processRaceData(data)
                }
            } else {
                log("API returned empty — keeping cached races")
            }
            
        } catch {
            print("❌ Failed to load races: \(error)")
            errorMessage = "Failed to load races: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    private func processRaceData(_ data: Data) {
        let aiEnabled = UserDefaults.standard.bool(forKey: "useAI")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let races = try? decoder.decode([Race].self, from: data) else { return }
        
        var newSuggestions: [String: [BetSuggestion]] = [:]
        for race in races {
            let suggestions: [BetSuggestion]
            if aiEnabled {
                suggestions = AnalysisService.shared.analyze(race: race)
            } else {
                suggestions = []
            }
            
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
