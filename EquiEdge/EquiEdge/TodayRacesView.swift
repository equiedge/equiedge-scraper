import SwiftUI
import SwiftData

struct TodayRacesView: View {
    @StateObject private var dataService = DataService.shared
    @State private var selectedTrack: String = "All"
    
    private var titleText: String {
        if dataService.isShowingToday {
            return "Today's Races"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dataService.selectedDate)
    }
    
    private var trackNames: [String] {
        let tracks = Set(dataService.races.map(\.track)).sorted()
        return ["All"] + tracks
    }
    
    private var filteredRaces: [Race] {
        let sorted = dataService.races.sorted {
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
        NavigationStack {
            mainContent
                .navigationTitle(titleText)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 4) {
                            Button {
                                dataService.goToPreviousDay()
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(!dataService.canGoBack)
                            
                            Button {
                                dataService.goToNextDay()
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(!dataService.canGoForward)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: AISelectionsView(races: dataService.allRaces)) {
                            Label("AI", systemImage: "brain")
                        }
                    }
                }
                .task { @MainActor in
                    await dataService.loadCachedRaces()
                }
                .navigationDestination(for: Race.self) { race in
                    RaceDetailView(race: race)
                }
        }
        .onChange(of: dataService.races) {
            if !trackNames.contains(selectedTrack) {
                selectedTrack = "All"
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if dataService.races.isEmpty && !dataService.isLoading {
            ContentUnavailableView(
                "No Races Loaded",
                systemImage: "hare",
                description: Text(dataService.isShowingToday
                    ? "Go to Settings to refresh races"
                    : "No cached races for this date")
            )
        } else {
            List {
                if trackNames.count > 2 {
                    Picker("Track", selection: $selectedTrack) {
                        ForEach(trackNames, id: \.self) { track in
                            Text(track).tag(track)
                        }
                    }
                }
                
                ForEach(filteredRaces) { race in
                    NavigationLink(value: race) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(race.track) R\(race.raceNumber)")
                                    .font(.headline)
                                Text("\(race.distance) • \(race.condition)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let count = dataService.suggestionsByRaceID[String(describing: race.id)]?.count ?? 0
                            if count > 0 {
                                Text("\(count) picks")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
