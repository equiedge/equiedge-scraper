import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var racesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @StateObject private var dataService = DataService.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selectedTab {
                case 0: TodayRacesView(navigationPath: $racesPath)
                case 1: MyBetsView()
                case 2: PerformanceView()
                case 3: SettingsView(navigationPath: $settingsPath)
                default: TodayRacesView(navigationPath: $racesPath)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Persistent analysis progress bar (above tab bar)
            if dataService.showProgressBar {
                VStack {
                    Spacer()
                    AnalysisProgressBar(dataService: dataService)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80) // above tab bar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: dataService.showProgressBar)
            }

            // Custom Tab Bar
            EETabBar(selectedTab: $selectedTab, onReselect: handleTabReselect)
        }
        .background(EEColors.bgPrimary)
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.keyboard)
    }

    private func handleTabReselect(_ tab: Int) {
        withAnimation {
            switch tab {
            case 0: racesPath = NavigationPath()
            case 3: settingsPath = NavigationPath()
            default: break
            }
        }
    }
}

// MARK: - Persistent Analysis Progress Bar

struct AnalysisProgressBar: View {
    @ObservedObject var dataService: DataService

    private var progressColor: Color {
        if !dataService.isAnalysing && dataService.analysisProgressMessage.contains("Failed") { return EEColors.red }
        if !dataService.isAnalysing && dataService.analysisProgressMessage.contains("No races") { return .orange }
        return EEColors.emerald
    }

    private var progressLabel: String {
        if dataService.isAnalysing {
            return "Analysing races... \(Int(dataService.analysisProgress * 100))%"
        }
        if dataService.analysisProgressMessage.contains("Failed") {
            return "Analysis failed"
        }
        if dataService.analysisProgressMessage.contains("No races") {
            return "No races available"
        }
        return dataService.analysisProgressMessage.isEmpty ? "Analysis complete" : dataService.analysisProgressMessage
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if dataService.isAnalysing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(EEColors.emerald)
                } else {
                    Image(systemName: dataService.analysisProgressMessage.contains("Failed") ? "exclamationmark.triangle.fill" : dataService.analysisProgressMessage.contains("No races") ? "info.circle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(progressColor)
                }

                Text(progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dataService.isAnalysing ? EEColors.textPrimary : progressColor)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dataService.showProgressBar = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(EEColors.textMuted)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
            }

            ProgressView(value: dataService.analysisProgress, total: 1.0)
                .tint(progressColor)
                .scaleEffect(y: 1.5)
                .animation(.easeInOut(duration: 0.4), value: dataService.analysisProgress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.3), value: dataService.isAnalysing)
    }
}

// MARK: - Custom Tab Bar

struct EETabBar: View {
    @Binding var selectedTab: Int
    var onReselect: ((Int) -> Void)?

    private let tabs: [(icon: String, label: String)] = [
        ("flag.checkered", "Races"),
        ("target", "Bets"),
        ("chart.line.uptrend.xyaxis", "Stats"),
        ("gearshape", "Settings"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    if selectedTab == index {
                        onReselect?(index)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = index
                        }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: selectedTab == index ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)

                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == index ? EEColors.emerald : EEColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(.bottom, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(EEColors.bgSecondary.opacity(0.85))
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(EEColors.borderSubtle)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }
}
