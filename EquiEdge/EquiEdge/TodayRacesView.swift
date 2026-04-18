import SwiftUI
import SwiftData

private enum RacesDestination: Hashable {
    case edgePicks
}

struct TodayRacesView: View {
    @Binding var navigationPath: NavigationPath
    @StateObject private var dataService = DataService.shared
    @AppStorage("selectedTrackFilter") private var selectedTrack: String = "All"
    @State private var showAnalysisModal = false
    @State private var progressTimer: Task<Void, Never>?
    @State private var showCompletedRaces = true
    @State private var showNoRacesAlert = false
    @State private var showTooEarlyAlert = false
    @AppStorage("showSelectionsOnly") private var showSelectionsOnly = false
    @Environment(\.scenePhase) private var scenePhase

    private var isAnalysing: Bool { dataService.isAnalysing }

    /// Whether there's cached data for today with future races still remaining
    private var hasCachedDataToday: Bool {
        guard !dataService.cachedTrackSlugs(for: DataService.startOfToday).isEmpty else { return false }
        // If we have race times, check if any races are still upcoming
        let now = Date()
        let hasUpcoming = dataService.allRaces.contains { race in
            guard let start = race.raceStartTime else { return true } // no time = assume upcoming
            return start > now
        }
        return hasUpcoming
    }

    private var titleText: String {
        if dataService.isShowingToday {
            return "Today's Races"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: dataService.selectedDate)
    }

    private var trackNames: [String] {
        let tracks = Set(dataService.allRaces.map(\.track)).sorted()
        return ["All"] + tracks
    }

    private func sortedRaces(_ races: [Race]) -> [Race] {
        races.sorted {
            if let t0 = $0.raceStartTime, let t1 = $1.raceStartTime {
                if t0 != t1 { return t0 < t1 }
            }
            if $0.raceStartTime != nil && $1.raceStartTime == nil { return true }
            if $0.raceStartTime == nil && $1.raceStartTime != nil { return false }
            if $0.track == $1.track { return $0.raceNumber < $1.raceNumber }
            return $0.track < $1.track
        }
    }

    private var allFilteredRaces: [Race] {
        var base = selectedTrack == "All" ? dataService.allRaces : dataService.allRaces.filter { $0.track == selectedTrack }
        if showSelectionsOnly {
            let sugMap = dataService.suggestionsByRaceID
            base = base.filter { !(sugMap[String(describing: $0.id)]?.isEmpty ?? true) }
        }
        return sortedRaces(base)
    }

    /// Upcoming races (start time is in the future, or no start time known)
    private var upcomingRaces: [Race] {
        guard dataService.isShowingToday else { return allFilteredRaces }
        let now = Date()
        return allFilteredRaces.filter { race in
            guard let start = race.raceStartTime else { return true }
            return start > now
        }
    }

    /// Races that have already started
    private var completedRaces: [Race] {
        guard dataService.isShowingToday else { return [] }
        let now = Date()
        return allFilteredRaces.filter { race in
            guard let start = race.raceStartTime else { return false }
            return start <= now
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                EEColors.bgPrimary.ignoresSafeArea()

                mainContent

                // Custom centered modal overlay
                if showAnalysisModal {
                    analysisModalOverlay
                }

                if showNoRacesAlert {
                    noRacesModalOverlay
                }

                if showTooEarlyAlert {
                    tooEarlyModalOverlay
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Button {
                            dataService.goToPreviousDay()
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(dataService.canGoBack ? EEColors.emerald : EEColors.textMuted)
                        }
                        .disabled(!dataService.canGoBack)

                        Button {
                            dataService.goToNextDay()
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(dataService.canGoForward ? EEColors.emerald : EEColors.textMuted)
                        }
                        .disabled(!dataService.canGoForward)

                        if !dataService.isShowingToday {
                            Button {
                                dataService.goToToday()
                            } label: {
                                Text("Today")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(EEColors.emerald))
                            }
                        }
                    }
                }
                if dataService.isShowingToday {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            handleEdgeAITap()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption)
                                Text(isAnalysing ? "Analysing..." : "Edge AI")
                                    .font(.caption.weight(.bold))
                                if isAnalysing {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(.white)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    isAnalysing
                                        ? LinearGradient(colors: [EEColors.emerald.opacity(0.6), EEColors.blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                                        : EEColors.edgeGradient
                                )
                            )
                        }
                        .disabled(isAnalysing)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: RacesDestination.edgePicks) {
                        Text("Edge Picks")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(EEColors.edgeGradient)
                            )
                    }
                }
            }
            .onAppear {
                dataService.loadCachedRaces()
                Task {
                    await dataService.fetchLiveOdds()
                }
            }
            .navigationDestination(for: Race.self) { race in
                RaceDetailView(race: race)
            }
            .navigationDestination(for: RacesDestination.self) { destination in
                switch destination {
                case .edgePicks:
                    AISelectionsView(races: dataService.allRaces)
                }
            }
        }
        .onChange(of: dataService.allRaces) {
            if !trackNames.contains(selectedTrack) {
                selectedTrack = "All"
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active && !Calendar.current.isDateInToday(dataService.selectedDate) {
                dataService.goToToday()
                Task {
                    await dataService.fetchLiveOdds()
                }
            }
        }
    }

    // MARK: - Edge AI Tap Handler

    private func handleEdgeAITap() {
        if hasCachedDataToday {
            // Show modal with options
            withAnimation(.easeInOut(duration: 0.25)) {
                showAnalysisModal = true
            }
        } else {
            // No cached data — go straight to full analysis
            performAnalysis(fullRefresh: true)
        }
    }

    // MARK: - Custom Analysis Modal

    private var analysisModalOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAnalysisModal = false
                    }
                }

            // Modal card
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32))
                        .foregroundStyle(EEColors.edgeGradient)

                    Text("Edge AI Analysis")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(EEColors.textPrimary)

                    Text("Run Edge AI Analysis on your selected tracks to generate picks and insights.")
                        .font(.subheadline)
                        .foregroundStyle(EEColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Option buttons
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAnalysisModal = false }
                        performAnalysis(fullRefresh: false)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analyse New Tracks")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(EEColors.textPrimary)
                                Text("Only tracks without data today")
                                    .font(.caption2)
                                    .foregroundStyle(EEColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(EEColors.emerald)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(EEColors.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                                )
                        )
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAnalysisModal = false }
                        performAnalysis(fullRefresh: true)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Re-analyse All Tracks")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(EEColors.textPrimary)
                                Text("Refresh all selected tracks")
                                    .font(.caption2)
                                    .foregroundStyle(EEColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(EEColors.blue)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(EEColors.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                                )
                        )
                    }
                }

                // Cancel
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAnalysisModal = false
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EEColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(EEColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(EEColors.borderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    // MARK: - No Races Modal

    private var noRacesModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNoRacesAlert = false
                    }
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("No Races Available")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(EEColors.textPrimary)

                    Text("No races for Edge AI to analyse based on the racetracks selected in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(EEColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNoRacesAlert = false
                    }
                } label: {
                    Text("OK")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(EEColors.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                                )
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(EEColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(EEColors.borderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private var tooEarlyModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTooEarlyAlert = false
                    }
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("Too Early to Analyse")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(EEColors.textPrimary)

                    let names = dataService.tooEarlyTrackNames.joined(separator: ", ")
                    Text("\(names) not analysed. AI Analysis is available 1 hour before the first race to ensure up-to-date data is utilised.")
                        .font(.subheadline)
                        .foregroundStyle(EEColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTooEarlyAlert = false
                    }
                } label: {
                    Text("OK")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(EEColors.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                                )
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(EEColors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(EEColors.borderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    // MARK: - Analysis Action

    private func performAnalysis(fullRefresh: Bool) {
        guard !dataService.isAnalysing else { return }
        dataService.isAnalysing = true
        dataService.analysisProgressMessage = ""
        dataService.tooEarlyTrackNames = []
        Task {
            startProgressSimulation()

            do {
                try await dataService.refreshScrape(forceFullScrape: fullRefresh)

                if dataService.allRaces.isEmpty {
                    completeProgress()
                    dataService.analysisProgressMessage = "No races available"
                    dataService.isAnalysing = false
                    showNoRacesAlert = true
                } else {
                    completeProgress()
                    dataService.analysisProgressMessage = "\(dataService.allRaces.count) races analysed"
                    dataService.isAnalysing = false
                    await dataService.fetchLiveOdds()
                }
            } catch {
                completeProgress()
                dataService.analysisProgressMessage = "Failed: \(error.localizedDescription)"
                dataService.isAnalysing = false
            }

            // Show alert for tracks that were too early to analyse
            if !dataService.tooEarlyTrackNames.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTooEarlyAlert = true
                }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if dataService.allRaces.isEmpty && !dataService.isLoading && !isAnalysing {
            // Empty state with prominent analysis button
            VStack(spacing: 20) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(EEColors.edgeGradient)

                Text(dataService.isShowingToday ? "No Races Analysed" : "No Races Loaded")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(EEColors.textPrimary)

                Text(dataService.isShowingToday
                    ? "Set Race Tracks in Settings and then run Edge AI Analysis to get today's picks and insights."
                    : "No analysed races for this date.")
                    .font(.subheadline)
                    .foregroundStyle(EEColors.textSecondary)
                    .multilineTextAlignment(.center)

                if dataService.isShowingToday {
                    Button {
                        handleEdgeAITap()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                            Text("Run Edge AI Analysis")
                        }
                    }
                    .buttonStyle(EEGradientButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                }
            }
            .padding(40)
        } else {
            ScrollView {
                VStack(spacing: 12) {

                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Selections only toggle
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showSelectionsOnly.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showSelectionsOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .font(.caption2)
                                    Text("Picks Only")
                                }
                                .eeChip(isActive: showSelectionsOnly)
                            }

                            if trackNames.count > 2 {
                                ForEach(trackNames, id: \.self) { track in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedTrack = track
                                        }
                                    } label: {
                                        Text(track)
                                            .eeChip(isActive: selectedTrack == track)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 4)

                    // Upcoming race cards
                    LazyVStack(spacing: 10) {
                        ForEach(upcomingRaces) { race in
                            NavigationLink(value: race) {
                                RaceRowCard(race: race, dataService: dataService)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Completed races (collapsible)
                    if !completedRaces.isEmpty {
                        VStack(spacing: 10) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showCompletedRaces.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Completed")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(EEColors.textMuted)
                                        .textCase(.uppercase)
                                        .tracking(1)

                                    Text("\(completedRaces.count)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(EEColors.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.white.opacity(0.06)))

                                    Spacer()

                                    Image(systemName: showCompletedRaces ? "chevron.up" : "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(EEColors.textMuted)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }

                            if showCompletedRaces {
                                LazyVStack(spacing: 10) {
                                    ForEach(completedRaces) { race in
                                        NavigationLink(value: race) {
                                            RaceRowCard(race: race, dataService: dataService)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Bottom spacer for tab bar
                    Spacer().frame(height: 100)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Progress Simulation

    private func startProgressSimulation() {
        dataService.analysisProgress = 0
        dataService.showProgressBar = true
        dataService.analysisProgressMessage = ""
        dataService.isAnalysisComplete = false
        progressTimer?.cancel()
        progressTimer = Task {
            var elapsed: Double = 0
            while !Task.isCancelled && !dataService.isAnalysisComplete {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled && !dataService.isAnalysisComplete else { break }
                elapsed += 1
                let target = min(0.9, 1.0 - 1.0 / (1.0 + elapsed / 40.0))
                dataService.analysisProgress = target
            }
        }
    }

    private func completeProgress() {
        dataService.isAnalysisComplete = true
        progressTimer?.cancel()
        progressTimer = nil
        dataService.analysisProgress = 1.0
    }

    private func stopProgressSimulation() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}

// MARK: - Race Row Card

struct RaceRowCard: View {
    let race: Race
    let dataService: DataService

    private var suggestions: [BetSuggestion] {
        dataService.suggestionsByRaceID[String(describing: race.id)] ?? []
    }

    private func paceColor(_ pace: String) -> Color {
        switch pace.uppercased() {
        case "SLOW": return EEColors.blue
        case "MODERATE": return EEColors.textSecondary
        case "FAST": return EEColors.gold
        case "VERY_FAST": return EEColors.red
        default: return EEColors.textMuted
        }
    }

    private var topPick: BetSuggestion? {
        suggestions.max(by: { $0.confidence < $1.confidence })
    }

    private var hasHighConfidence: Bool {
        (topPick?.confidence ?? 0) >= 75
    }

    private var raceTimeText: String? {
        guard let time = race.raceStartTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        return formatter.string(from: time)
    }

    private var hasPick: Bool { topPick != nil }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: hasPick ? 6 : 4) {
                HStack(spacing: 8) {
                    Text("\(race.track) R\(race.raceNumber)")
                        .font(hasPick ? .headline.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundStyle(hasPick ? EEColors.textPrimary : EEColors.textSecondary)

                    if let time = raceTimeText {
                        Text(time)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EEColors.blue)
                    }
                }

                HStack(spacing: 6) {
                    Text(race.distance)
                    Text("•")
                    Text(race.condition)
                    if let raceClass = race.raceClass {
                        Text("•")
                        Text(raceClass)
                            .foregroundStyle(EEColors.blue)
                    }
                    Text("•")
                    Text("\(race.runners.count) runners")
                }
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)

                if hasPick {
                    // Pace scenario indicator
                    if let pace = race.paceScenario {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(paceColor(pace))
                                .frame(width: 6, height: 6)
                            Text(pace.replacingOccurrences(of: "_", with: " "))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(paceColor(pace))
                        }
                    }

                    if let pick = topPick {
                        HStack(spacing: 6) {
                            let runner = race.runners.first { $0.name == pick.horseName }
                            EEBadge(text: "#\(runner?.number ?? 0) \(pick.horseName)", color: EEColors.emerald)

                            if let odds = pick.fixedWinOdds {
                                EEBadge(text: "$\(String(format: "%.2f", odds))", color: EEColors.blue)
                            }
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Text("No Selection — no clear edge")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(EEColors.textMuted)
                        .italic()
                }
            }

            Spacer()

            if let pick = topPick {
                VStack(spacing: 0) {
                    ConfidenceBar(confidence: pick.confidence)

                    if let result = pick.result {
                        Spacer()
                        EEBadge(
                            text: result == "Won" ? "Won" : "Lost",
                            color: result == "Won" ? EEColors.emerald : EEColors.red
                        )
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(EEColors.textMuted)
        }
        .padding(.vertical, hasPick ? 14 : 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: hasPick ? 16 : 12)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: hasPick ? 16 : 12)
                        .stroke(hasPick ? EEColors.emerald.opacity(0.35) : EEColors.borderSubtle, lineWidth: hasPick ? 1.5 : 1)
                )
        )
        .overlay(alignment: .leading) {
            if hasPick {
                RoundedRectangle(cornerRadius: 2)
                    .fill(EEColors.emerald)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
    }
}
