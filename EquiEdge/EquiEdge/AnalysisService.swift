import Foundation

public class AnalysisService {
    public static let shared = AnalysisService()
    
    var confidenceThreshold: Double = 0.28
    
    public func analyze(race: Race) -> [BetSuggestion] {
        var suggestions: [BetSuggestion] = []
        
        for horse in race.runners {
            let score = calculateScore(horse: horse, race: race)
            let predictedProb = min(0.60, max(0.05, score / 120.0))
            
            guard predictedProb >= confidenceThreshold else { continue }
            
            let units = max(1, min(5, Int(predictedProb * 100) / 20))
            let reason = generateDetailedReason(horse: horse, race: race, prob: predictedProb)
            
            suggestions.append(BetSuggestion(
                horse: horse,
                predictedProb: predictedProb,
                units: units,
                reason: reason,
                raceInfo: "\(race.track) R\(race.raceNumber) • \(race.distance)"
            ))
        }
        
        return suggestions.sorted { $0.predictedProb > $1.predictedProb }
    }
    
    private func calculateScore(horse: Horse, race: Race) -> Double {
        var score = 0.0
        score += horse.stats.recentFormScore * 45
        score += horse.stats.trackWinPct * 0.8
        if race.condition.lowercased().contains("good") {
            score += horse.stats.goodTrackWinPct * 0.7
        }
        score += max(0, (14 - Double(horse.barrier))) * 2.5
        score += (62 - horse.weight) * 1.2
        return score
    }
    
    private func generateDetailedReason(horse: Horse, race: Race, prob: Double) -> String {
        var parts: [String] = []
        if horse.stats.recentFormScore > 0.65 {
            parts.append("Excellent recent form: \(horse.form)")
        }
        if horse.stats.trackWinPct > 30 {
            parts.append("Strong at this track (\(Int(horse.stats.trackWinPct))% win rate)")
        }
        if horse.stats.distanceWinPct > 25 {
            parts.append("Proven over \(race.distance)")
        }
        parts.append("Well suited to \(race.condition) in \(race.weather)")
        parts.append("Barrier \(horse.barrier) • Weight \(horse.weight)kg")
        parts.append("Estimated win probability: \(Int(prob * 100))%")
        return parts.joined(separator: "\n• ")
    }
}

public struct BetSuggestion: Identifiable {
    public let id = UUID()
    public let horse: Horse
    public let predictedProb: Double
    public let units: Int
    public let reason: String
    public let raceInfo: String
}
