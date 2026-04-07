import Foundation
import SwiftUI
import SwiftData

@MainActor
class DataService: ObservableObject {
    static let shared = DataService()
    
    @Published var races: [Race] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    @AppStorage("useGrokAI") private var useGrokAI: Bool = true
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    
    private let baseURL = "https://equiedge-scraper.vercel.app"
    
    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240    // 4 minutes
        config.timeoutIntervalForResource = 300   // 5 minutes
        return URLSession(configuration: config)
    }
    
    func refreshScrape() async {
        isLoading = true
        errorMessage = nil
        
        let urlString = useGrokAI
            ? "\(baseURL)/scrape-now?ai=true"
            : "\(baseURL)/scrape-now"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        
        do {
            print("📡 Starting scrape: \(urlString)")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            print("📡 Backend responded with status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            
            // Decode the scrape response (status only)
            if let scrapeResponse = try? JSONDecoder().decode([String: String].self, from: data) {
                print("✅ Scrape response: \(scrapeResponse)")
            }
            
            // Now fetch the actual race data
            await loadTodayRaces()
            
            print("✅ Manual scrape complete (Grok AI used: \(useGrokAI))")
            
        } catch let error as URLError where error.code == .timedOut {
            errorMessage = "Request timed out. The analysis is taking longer than expected. Try again or disable Grok AI."
            print("❌ Request timed out")
        } catch {
            errorMessage = "Failed to refresh data: \(error.localizedDescription)"
            print("❌ Scrape failed: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func loadTodayRaces() async {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseURL)/today-races") else {
            errorMessage = "Invalid races URL"
            isLoading = false
            return
        }
        
        do {
            let (data, _) = try await session.data(from: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let decodedRaces = try decoder.decode([Race].self, from: data)
            
            self.races = decodedRaces
            print("✅ Successfully loaded \(decodedRaces.count) races from backend")
            
        } catch {
            print("❌ Failed to load races: \(error.localizedDescription)")
            errorMessage = "Failed to load races: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // Optional: Auto-load on app start
    func loadCachedRaces() async {
        await loadTodayRaces()
    }
}
