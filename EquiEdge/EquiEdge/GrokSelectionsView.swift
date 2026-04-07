import SwiftUI

struct AISelectionsView: View {
    let races: [Race]
    @State private var selectedTrack: String = "All"
    
    private var trackNames: [String] {
        let tracks = Set(races.map(\.track)).sorted()
        return ["All"] + tracks
    }
    
    private var filteredRaces: [Race] {
        let sorted = races.sorted {
            if $0.track == $1.track {
                return $0.raceNumber < $1.raceNumber
            }
            return $0.track < $1.track
        }
        if selectedTrack == "All" {
            return sorted
        }
        return sorted.filter { $0.track == selectedTrack }
    }
    
    var body: some View {
        List {
            if races.isEmpty {
                ContentUnavailableView(
                    "No Analysis Yet",
                    systemImage: "brain",
                    description: Text("Run a scrape with AI enabled")
                )
            } else {
                if trackNames.count > 2 {
                    Picker("Track", selection: $selectedTrack) {
                        ForEach(trackNames, id: \.self) { track in
                            Text(track).tag(track)
                        }
                    }
                }
                
                ForEach(filteredRaces) { race in
                    Section(header: Text("\(race.track) R\(race.raceNumber)")) {
                        if race.suggestions.isEmpty {
                            Text("No confident selection for this race")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            ForEach(race.suggestions) { suggestion in
                                let runner = race.runners.first { $0.name == suggestion.horseName }
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(runnerDisplayName(suggestion: suggestion, runner: runner))
                                            .font(.headline)
                                        Spacer()
                                        Text("\(suggestion.confidence)%")
                                            .font(.title2.bold())
                                            .foregroundStyle(.green)
                                    }
                                    
                                    HStack {
                                        Text("Bet \(suggestion.units) units")
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                        Spacer()
                                    }
                                    
                                    Text(suggestion.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(6)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Selections")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func runnerDisplayName(suggestion: BetSuggestion, runner: Runner?) -> String {
        guard let r = runner else { return suggestion.horseName }
        return "#\(r.number) \(suggestion.horseName) (B: \(r.barrier), W: \(String(format: "%.1f", r.weight))kg)"
    }
}
