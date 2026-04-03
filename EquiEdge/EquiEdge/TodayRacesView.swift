import SwiftUI
import SwiftData

struct TodayRacesView: View {
    
    @State private var races: [Race] = []
    @State private var selectedRace: Race?
    @State private var suggestions: [BetSuggestion] = []
    @State private var showingDetail = false
    @State private var isLoading = false
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                // Load Button Section
                Section("Actions") {
                    Button {
                        Task {
                            isLoading = true
                            races = await DataService.shared.loadTodayRaces()
                            isLoading = false
                        }
                    } label: {
                        HStack {
                            Text("Load Today's Races (Sky Racing World)")
                            if isLoading {
                                ProgressView()
                            }
                        }
                    }
                }
                
                // List of Races
                Section("Available Races") {
                    ForEach(races) { race in
                        Button {
                            selectedRace = race
                            suggestions = AnalysisService.shared.analyze(race: race)
                            showingDetail = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(race.track) R\(race.raceNumber)")
                                    .font(.headline)
                                Text("\(race.distance) • \(race.condition) • \(race.weather)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("EquiEdge")
            .navigationBarTitleDisplayMode(.inline)
            
            // Sheet for Race Detail
            .sheet(isPresented: $showingDetail) {
                if let race = selectedRace {
                    RaceDetailView(race: race, suggestions: suggestions)
                }
            }
        }
    }
}
