import Foundation
import SwiftUI   // ← This was missing

class DataService {
    static let shared = DataService()
    private let backendBase = "https://equiedge-scraper.vercel.app"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    
    @AppStorage("useGrokAI") var useGrokAI = true
    
    @MainActor
    func loadTodayRaces() async throws -> [Race] {
        let url = URL(string: "\(backendBase)/today-races")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let races = try decoder.decode([Race].self, from: data)
        return races
    }
    
    @MainActor
    func refreshScrape() async throws {
        let aiParam = useGrokAI ? "?ai=true" : ""
        let url = URL(string: "\(backendBase)/scrape-now\(aiParam)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        print("✅ Manual scrape complete (Grok AI used: \(useGrokAI))")
    }
}
