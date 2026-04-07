import SwiftUI
import SwiftData

struct RaceDetailView: View {
    let race: Race
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [BetRecord]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Race Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(race.track) R\(race.raceNumber)")
                        .font(.largeTitle.bold())
                    
                    HStack {
                        Text(race.condition)
                        Text("•")
                        Text(race.distance)
                        Spacer()
                        Text(race.weather)
                    }
                    .font(.headline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                // Grok AI Suggestions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Grok AI Analysis")
                        .font(.title2.bold())
                        .padding(.horizontal)
                    
                    if race.suggestions.isEmpty {
                        ContentUnavailableView(
                            "No High-Confidence Picks",
                            systemImage: "flag.fill",
                            description: Text("Grok didn't find a strong edge in this race")
                        )
                    } else {
                        let raceInfo = "\(race.track) R\(race.raceNumber)"
                        ForEach(race.suggestions) { suggestion in
                            let existingBet = allBets.first {
                                $0.raceInfo == raceInfo && $0.horseName == suggestion.horseName
                            }
                            SuggestionCard(
                                suggestion: suggestion,
                                unitSize: unitSize,
                                isLogged: existingBet != nil,
                                onToggleBet: {
                                    if let bet = existingBet {
                                        modelContext.delete(bet)
                                    } else {
                                        let bet = BetRecord(
                                            raceInfo: raceInfo,
                                            horseName: suggestion.horseName,
                                            units: suggestion.units,
                                            amount: Double(suggestion.units) * unitSize,
                                            confidence: suggestion.confidence,
                                            reason: suggestion.reason
                                        )
                                        modelContext.insert(bet)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("\(race.track) R\(race.raceNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Suggestion Card
struct SuggestionCard: View {
    let suggestion: BetSuggestion
    let unitSize: Double
    let isLogged: Bool
    let onToggleBet: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(suggestion.horseName)
                    .font(.headline)
                Spacer()
                Text("\(suggestion.confidence)%")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            }
            
            Text("Recommend betting **\(suggestion.units)** units")
                .foregroundStyle(.orange)
            
            Text(suggestion.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: onToggleBet) {
                HStack {
                    Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(isLogged ? "Bet Logged" : "Log Bet")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isLogged ? Color.gray : Color.green)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}
