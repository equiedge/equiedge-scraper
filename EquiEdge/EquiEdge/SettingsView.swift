import SwiftUI

private enum SettingsDestination: Hashable {
    case trackSelector
}

struct SettingsView: View {
    @Binding var navigationPath: NavigationPath
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.41
    @StateObject private var dataService = DataService.shared
    private var trackSelection = TrackSelection.shared

    init(navigationPath: Binding<NavigationPath>) {
        self._navigationPath = navigationPath
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                EEColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Betting Units
                        VStack(alignment: .leading, spacing: 12) {
                            EESectionHeader(title: "Betting Units")

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Unit Amount")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(EEColors.textPrimary)

                                Slider(value: $unitSize, in: 5...50, step: 5)
                                    .tint(EEColors.emerald)

                                Text("$\(Int(unitSize)) per unit")
                                    .font(.title3.weight(.heavy).monospacedDigit())
                                    .foregroundStyle(EEColors.emerald)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(EEColors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(EEColors.borderSubtle, lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)

                        // Racetrack Selector
                        VStack(alignment: .leading, spacing: 12) {
                            EESectionHeader(title: "Racetracks")

                            NavigationLink(value: SettingsDestination.trackSelector) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(EEColors.emerald)
                                    Text("Select Tracks")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(EEColors.textPrimary)
                                    Spacer()
                                    Text("\(trackSelection.selectedSlugs.count) of \(TrackSelection.totalTrackCount)")
                                        .font(.caption)
                                        .foregroundStyle(EEColors.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(EEColors.textMuted)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(EEColors.bgCard)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(EEColors.borderSubtle, lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)

                        // Server Logs
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                EESectionHeader(title: "Server Logs")
                                Spacer()
                                Button("Clear") {
                                    dataService.clearLogs()
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(EEColors.textMuted)
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                if dataService.logs.isEmpty {
                                    Text("No logs yet")
                                        .font(.caption)
                                        .foregroundStyle(EEColors.textMuted)
                                        .padding(12)
                                } else {
                                    ScrollViewReader { proxy in
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 4) {
                                                ForEach(Array(dataService.logs.suffix(150).enumerated()), id: \.offset) { index, line in
                                                    Text(line)
                                                        .font(.caption2)
                                                        .textSelection(.enabled)
                                                        .monospaced()
                                                        .foregroundStyle(EEColors.textSecondary)
                                                        .id(index)
                                                }
                                            }
                                            .padding(12)
                                        }
                                        .frame(minHeight: 120, maxHeight: 240)
                                        .onChange(of: dataService.logs.count) {
                                            if let last = dataService.logs.suffix(150).indices.last {
                                                proxy.scrollTo(last - dataService.logs.suffix(150).startIndex, anchor: .bottom)
                                            }
                                        }
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(EEColors.bgCard)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(EEColors.borderSubtle, lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)

                        // Version
                        Text("EquiEdge v1.0")
                            .font(.caption)
                            .foregroundStyle(EEColors.textMuted)
                            .padding(.top, 8)

                        Spacer().frame(height: 100)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EEBrandedTitle()
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .trackSelector:
                    TrackSelectorView()
                }
            }
        }
    }
}
