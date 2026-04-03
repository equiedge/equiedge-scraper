import SwiftUI
import SwiftData

public struct RaceDetailView: View {
    
    let race: Race
    let suggestions: [BetSuggestion]
    
    public init(race: Race, suggestions: [BetSuggestion]) {
        self.race = race
        self.suggestions = suggestions
    }
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Race Header
                VStack(spacing: 8) {
                    Text("\(race.track)")
                        .font(.largeTitle.bold())
                    Text("Race \(race.raceNumber) • \(race.distance)")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    Text("\(race.condition) • \(race.weather)")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                .padding(.top)
                
                // Suggestions
                if suggestions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "flag.slash")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("No high-confidence bets")
                            .font(.title2.bold())
                        Text("EquiEdge only suggests when it is very confident.\nTry another race.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("\(suggestion.horse.number). \(suggestion.horse.name)")
                                    .font(.title2.bold())
                                Spacer()
                                Text("\(Int(suggestion.predictedProb * 100))%")
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(.green)
                            }
                            
                            Text(suggestion.reason)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                            
                            HStack {
                                Text("Bet \(suggestion.units) units")
                                    .font(.headline)
                                Spacer()
                                Text("\(Double(suggestion.units) * unitSize, specifier: "$%.0f")")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }
                            
                            Button {
                                logBet(suggestion: suggestion)
                            } label: {
                                Text("Log This Bet")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundStyle(.black)
                                    .font(.headline)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Race Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func logBet(suggestion: BetSuggestion) {
        let record = BetRecord(
            raceDate: race.date,
            track: race.track,
            raceNumber: race.raceNumber,
            horseName: suggestion.horse.name,
            predictedProb: suggestion.predictedProb,
            unitsBet: suggestion.units,
            unitSize: unitSize
        )
        modelContext.insert(record)
        
        // Simple success feedback
        print("✅ Bet logged: \(suggestion.horse.name) - \(suggestion.units) units")
    }
}
#if DEBUG
private struct _PreviewRaceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleHorse = Horse(number: 1, name: "Sample Horse", jockey: "J. Doe", trainer: "T. Smith", weight: 58.0, barrier: 4, form: "3-1-2", stats: HorseStats(winPct: 35, trackWinPct: 30, distanceWinPct: 28, goodTrackWinPct: 32, recentFormScore: 0.7))
        let sampleSuggestion = BetSuggestion(horse: sampleHorse, predictedProb: 0.42, units: 3, reason: "Strong late speed and favorable post position.", raceInfo: "Belmont Park R5 • 6f")
        let sampleRace = Race(date: .now, track: "Belmont Park", raceNumber: 5, distance: "6f", condition: "Fast", weather: "Sunny", runners: [sampleHorse])
        return NavigationStack { RaceDetailView(race: sampleRace, suggestions: [sampleSuggestion]) }
    }
}
#endif

