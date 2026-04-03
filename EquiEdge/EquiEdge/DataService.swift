import Foundation

class DataService {
    static let shared = DataService()
    
    // ←←← CHANGE THIS TO YOUR ACTUAL VERCEL URL ←←←
    private let backendBase = "https://equiedge-scraper.vercel.app"
    
    // MARK: - Load Today's Races from Backend
    func loadTodayRaces() async -> [Race] {
        guard let url = URL(string: "\(backendBase)/today-races") else {
            print("❌ Invalid backend URL")
            return loadMockRaces()
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Optional: Print status for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Backend responded with status: \(httpResponse.statusCode)")
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let races = try decoder.decode([Race].self, from: data)
            print("✅ Successfully loaded \(races.count) races from Sky Racing World")
            return races
            
        } catch {
            print("❌ Failed to load races from backend: \(error.localizedDescription)")
            return loadMockRaces()  // Fallback to mock data
        }
    }
    
    // MARK: - Manual Refresh Scrape
    func refreshScrape() async -> Bool {
        guard let url = URL(string: "\(backendBase)/scrape-now") else { return false }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String,
               status == "ok" {
                print("✅ Manual scrape triggered successfully")
                return true
            }
            return false
        } catch {
            print("❌ Refresh scrape failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Mock Data (Fallback)
    func loadMockRaces() -> [Race] {
        let today = Date()
        
        let mockHorse1 = Horse(
            number: 3,
            name: "Thunder Strike",
            jockey: "J. Kah",
            trainer: "C. Waller",
            weight: 57.5,
            barrier: 4,
            form: "1x2214",
            stats: HorseStats(winPct: 28, trackWinPct: 42, distanceWinPct: 35, goodTrackWinPct: 38, recentFormScore: 0.78)
        )
        
        let mockHorse2 = Horse(
            number: 7,
            name: "Speed Demon",
            jockey: "M. Zahra",
            trainer: "G. Waterhouse",
            weight: 55.0,
            barrier: 2,
            form: "312x15",
            stats: HorseStats(winPct: 31, trackWinPct: 25, distanceWinPct: 40, goodTrackWinPct: 45, recentFormScore: 0.65)
        )
        
        let race1 = Race(
            date: today,
            track: "Flemington",
            raceNumber: 5,
            distance: "1200m",
            condition: "Good 4",
            weather: "Fine, 21°C",
            runners: [mockHorse1, mockHorse2]
        )
        
        return [race1]
    }
}
