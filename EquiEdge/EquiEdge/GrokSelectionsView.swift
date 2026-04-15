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
        ZStack {
            EEColors.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if races.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "brain")
                                .font(.system(size: 40))
                                .foregroundStyle(EEColors.textMuted)
                            Text("No Edge AI Analysis")
                                .font(.headline)
                                .foregroundStyle(EEColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        // Track chips
                        if trackNames.count > 2 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
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
                                .padding(.horizontal, 16)
                            }
                        }

                        // Races
                        LazyVStack(spacing: 16) {
                            ForEach(filteredRaces) { race in
                                AIRaceCard(race: race)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Edge Picks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Race Card

struct AIRaceCard: View {
    let race: Race
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("\(race.track) R\(race.raceNumber)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)

                    Spacer()

                    if !race.suggestions.isEmpty {
                        Text("\(race.suggestions.count) pick\(race.suggestions.count > 1 ? "s" : "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EEColors.emerald)
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(EEColors.textMuted)
                }
            }

            if expanded {
                // AI Analysis text
                if !race.aiAnalysis.isEmpty {
                    Text(race.aiAnalysis)
                        .font(.caption)
                        .foregroundStyle(EEColors.textSecondary)
                }

                if race.suggestions.isEmpty {
                    if race.aiAnalysis.isEmpty {
                        Text("No AI analysis available")
                            .font(.caption)
                            .foregroundStyle(EEColors.textMuted)
                            .italic()
                    }
                } else {
                    ForEach(race.suggestions) { suggestion in
                        let runner = race.runners.first { $0.name == suggestion.horseName }
                        AIPickRow(suggestion: suggestion, runner: runner)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - AI Pick Row

struct AIPickRow: View {
    let suggestion: BetSuggestion
    let runner: Runner?

    private var displayName: String {
        guard let r = runner else { return suggestion.horseName }
        return "#\(r.number) \(suggestion.horseName)"
    }

    private var details: String {
        guard let r = runner else { return "" }
        return "B:\(r.barrier) \(String(format: "%.1f", r.weight))kg"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ConfidenceRing(confidence: suggestion.confidence, size: 40, lineWidth: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)

                    // ML rank badge
                    if let rank = suggestion.mlModelRank, rank > 0, rank <= 3 {
                        Text("ML #\(rank)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EEColors.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(EEColors.blueDim))
                    }
                }

                if !details.isEmpty {
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(EEColors.textMuted)
                }

                if let flags = suggestion.redFlagsChecked, flags != "None", !flags.isEmpty {
                    Text("Flags: \(flags)")
                        .font(.caption2)
                        .foregroundStyle(EEColors.red.opacity(0.8))
                }

                if let bias = suggestion.trackBias, bias != "None identified", !bias.isEmpty {
                    Text("Bias: \(bias)")
                        .font(.caption2)
                        .foregroundStyle(EEColors.blue.opacity(0.8))
                }

                // Key badges
                if let badges = suggestion.keyBadges, !badges.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(badges.prefix(4), id: \.self) { badge in
                            let sentiment = badge.contains("(+)") ? "+" : badge.contains("(-)") ? "-" : "/"
                            let label = badge.replacingOccurrences(of: " (+)", with: "").replacingOccurrences(of: " (-)", with: "").replacingOccurrences(of: " (/)", with: "")
                            // Trim long badge text (e.g. "Weight Drop (54.0kg (avg 58.2kg, down 4.2kg))")
                            let shortLabel = label.count > 30 ? String(label.prefix(30)) + "…" : label
                            BadgePill(text: shortLabel, sentiment: sentiment)
                        }
                    }
                }
            }
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 4) {
                if let result = suggestion.result {
                    EEBadge(
                        text: result == "Won" ? "Won" : "Lost",
                        color: result == "Won" ? EEColors.emerald : EEColors.red
                    )
                }
                if let odds = suggestion.fixedWinOdds {
                    EEBadge(text: "$\(String(format: "%.2f", odds))", color: EEColors.blue)
                }
                EEBadge(text: "\(suggestion.units)u", color: EEColors.gold)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.02))
        )
    }
}
