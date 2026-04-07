import SwiftUI
import SwiftData

struct RaceDetailView: View {
    let race: Race
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSuggestion: BetSuggestion?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Race info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(race.condition)
                        Text("• \(race.distance)")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .font(.headline)
                }
                .padding(.horizontal)
                
                if race.suggestions.isEmpty {
                    ContentUnavailableView("No High-Confidence Picks", systemImage: "flag.fill")
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("High-Confidence Selections")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(race.suggestions) { suggestion in
                            SuggestionCard(suggestion: suggestion, unitSize: unitSize) {
                                let bet = BetRecord(
                                    raceInfo: suggestion.raceInfo,
                                    horseName: suggestion.horseName,
                                    units: suggestion.units,
                                    amount: Double(suggestion.units) * unitSize,
                                    confidence: suggestion.confidence,
                                    reason: suggestion.reason
                                )
                                modelContext.insert(bet)
                                selectedSuggestion = suggestion
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("\(race.track) R\(race.raceNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Bet Logged!", isPresented: .constant(selectedSuggestion != nil)) {
            Button("OK") { selectedSuggestion = nil }
        } message: {
            if let suggestion = selectedSuggestion {
                Text("\(suggestion.horseName) – \(suggestion.units) units logged")
            }
        }
    }
}

struct SuggestionCard: View {
    let suggestion: BetSuggestion
    let unitSize: Double
    let onLogBet: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(suggestion.horseName)
                    .font(.title3.bold())
                Spacer()
                Text("\(suggestion.confidence)%")
                    .font(.title.bold())
                    .foregroundStyle(.green)
            }
            
            Text(suggestion.reason)
                .font(.body)
                .foregroundStyle(.secondary)
            
            HStack {
                Text("\(suggestion.units) units • $\(Int(Double(suggestion.units) * unitSize))")
                    .font(.headline)
                Spacer()
                Button("Log Bet", action: onLogBet)
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
