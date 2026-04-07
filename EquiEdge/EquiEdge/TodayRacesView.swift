import SwiftUI

struct TodayRacesView: View {
    @State private var races: [Race] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading today's races...")
                        .padding()
                } else if races.isEmpty {
                    ContentUnavailableView(
                        "No High-Confidence Races",
                        systemImage: "flag.fill",
                        description: Text("No strong bets today.\nPull down to refresh.")
                    )
                } else {
                    List {
                        Section(header: Text("Races with High-Confidence Selections (\(races.count))")) {
                            ForEach(races) { race in
                                NavigationLink(value: race) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("\(race.track) R\(race.raceNumber)")
                                                .font(.headline)
                                            HStack(spacing: 4) {
                                                Text(race.condition)
                                                Text("•")
                                                Text("\(race.runners.count) runners • \(race.distance)")
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Today's Races")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshRaces() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .task { await loadRaces() }
            .refreshable { await refreshRaces() }
        }
    }
    
    private func loadRaces() async {
        isLoading = true
        do {
            races = try await DataService.shared.loadTodayRaces()
        } catch {
            print("❌ Failed to load races: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func refreshRaces() async {
        isLoading = true
        do {
            try await DataService.shared.refreshScrape()
            try await Task.sleep(for: .seconds(2))
            races = try await DataService.shared.loadTodayRaces()
        } catch {
            print("❌ Refresh failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}
