import Foundation

class AnalysisService {
    static let shared = AnalysisService()
    
    func analyze(race: Race) -> [BetSuggestion] {
        return race.suggestions
    }
}
