import SwiftUI
import SwiftData

struct RaceDetailView: View {
    let race: Race
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @Environment(\.modelContext) private var modelContext
    @Query private var allBets: [BetRecord]
    @State private var selectedRunner: Runner?

    private var raceTimeText: String? {
        guard let time = race.raceStartTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        return formatter.string(from: time)
    }

    var body: some View {
        ZStack {
            EEColors.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Race Header
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(race.track) R\(race.raceNumber)")
                                .font(.largeTitle.weight(.heavy))
                                .foregroundStyle(EEColors.textPrimary)

                            if let time = raceTimeText {
                                Text(time)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(EEColors.blue)
                            }
                        }

                        // Race info chips with Pro data
                        HStack(spacing: 8) {
                            InfoChip(text: race.distance)
                            InfoChip(text: race.condition)
                            InfoChip(text: race.weather)
                            if let raceClass = race.raceClass {
                                InfoChip(text: raceClass, color: EEColors.blue)
                            }
                            if let pace = race.paceScenario {
                                PaceChip(pace: pace)
                            }
                        }

                        if let name = race.raceName, !name.isEmpty {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(EEColors.textMuted)
                        }
                    }
                    .padding(.horizontal)

                    // AI Suggestions
                    VStack(alignment: .leading, spacing: 16) {
                        EESectionHeader(title: "AI Picks", color: EEColors.emerald)
                            .padding(.horizontal)

                        if race.suggestions.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "brain")
                                    .font(.system(size: 36))
                                    .foregroundStyle(EEColors.textMuted)
                                Text("No High-Confidence Picks")
                                    .font(.headline)
                                    .foregroundStyle(EEColors.textSecondary)
                                Text("AI didn't find a strong edge in this race")
                                    .font(.subheadline)
                                    .foregroundStyle(EEColors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            let raceInfo = "\(race.track) R\(race.raceNumber)"
                            ForEach(race.suggestions) { suggestion in
                                let runner = race.runners.first { $0.name == suggestion.horseName }
                                let existingBet = allBets.first {
                                    $0.raceInfo == raceInfo && $0.horseName == suggestion.horseName
                                }
                                SuggestionCard(
                                    suggestion: suggestion,
                                    runner: runner,
                                    unitSize: unitSize,
                                    fieldSize: race.runners.count,
                                    isLogged: existingBet != nil,
                                    onToggleBet: {
                                        if let bet = existingBet {
                                            modelContext.delete(bet)
                                        } else {
                                            let bet = BetRecord(
                                                raceInfo: raceInfo,
                                                horseName: suggestion.horseName,
                                                runnerNumber: runner?.number ?? 0,
                                                barrier: runner?.barrier ?? 0,
                                                weight: runner?.weight ?? 0,
                                                units: suggestion.units,
                                                amount: Double(suggestion.units) * unitSize,
                                                confidence: suggestion.confidence,
                                                reason: suggestion.reason,
                                                odds: suggestion.fixedWinOdds,
                                                date: race.date
                                            )
                                            modelContext.insert(bet)
                                        }
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Runners list (tappable to RunnerDetailView)
                    VStack(alignment: .leading, spacing: 12) {
                        EESectionHeader(title: "Field (\(race.runners.count) runners)", color: EEColors.textSecondary)
                            .padding(.horizontal)

                        LazyVStack(spacing: 8) {
                            ForEach(race.runners) { runner in
                                Button {
                                    selectedRunner = runner
                                } label: {
                                    RunnerRowCard(runner: runner, fieldSize: race.runners.count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer().frame(height: 100)
                }
                .padding(.top)
            }
        }
        .navigationTitle("\(race.track) R\(race.raceNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRunner) { runner in
            NavigationStack {
                RunnerDetailView(runner: runner, race: race)
            }
        }
    }
}

// MARK: - Info Chip

private struct InfoChip: View {
    let text: String
    var color: Color = EEColors.textSecondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
            )
    }
}

// MARK: - Pace Chip

private struct PaceChip: View {
    let pace: String

    private var color: Color {
        switch pace.uppercased() {
        case "SLOW": return EEColors.blue
        case "MODERATE": return EEColors.textSecondary
        case "FAST": return EEColors.gold
        case "VERY_FAST": return EEColors.red
        default: return EEColors.textMuted
        }
    }

    var body: some View {
        Text(pace.replacingOccurrences(of: "_", with: " "))
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Runner Row Card (for field list)

private struct RunnerRowCard: View {
    let runner: Runner
    let fieldSize: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(runner.number)")
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(EEColors.textMuted)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(runner.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(EEColors.textPrimary)

                HStack(spacing: 6) {
                    Text("B:\(runner.barrier)")
                    Text("\(String(format: "%.1f", runner.weight))kg")
                    Text(runner.jockey)
                }
                .font(.caption2)
                .foregroundStyle(EEColors.textSecondary)
                .lineLimit(1)
            }

            Spacer()

            // Speed map style indicator
            if let sm = runner.speedMap {
                Text(sm.runningStyle)
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(EEColors.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(EEColors.blueDim))
            }

            // ML rank
            if let pred = runner.prediction {
                Text("#\(pred.modelRank)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(pred.modelRank <= 3 ? EEColors.emerald : EEColors.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(pred.modelRank <= 3 ? EEColors.emeraldDim : Color.white.opacity(0.04)))
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
    }
}

// MARK: - Badge Pill

struct BadgePill: View {
    let text: String
    let sentiment: String

    private var color: Color {
        switch sentiment {
        case "+": return EEColors.emerald
        case "-": return EEColors.red
        default: return EEColors.textSecondary
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
    let suggestion: BetSuggestion
    let runner: Runner?
    let unitSize: Double
    var fieldSize: Int = 0
    let isLogged: Bool
    let onToggleBet: () -> Void

    private var displayName: String {
        guard let r = runner else { return suggestion.horseName }
        return "#\(r.number) \(suggestion.horseName)"
    }

    private var runnerDetails: String {
        guard let r = runner else { return "" }
        return "B:\(r.barrier) \(String(format: "%.1f", r.weight))kg \(r.jockey)"
    }

    private var betAmount: Double {
        Double(suggestion.units) * unitSize
    }

    private var expectedReturn: Double? {
        guard let odds = suggestion.fixedWinOdds else { return nil }
        return betAmount * odds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Confidence Ring + Horse Name + ML Rank
            HStack(spacing: 14) {
                ConfidenceRing(confidence: suggestion.confidence, size: 52, lineWidth: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)

                    if !runnerDetails.isEmpty {
                        Text(runnerDetails)
                            .font(.caption)
                            .foregroundStyle(EEColors.textSecondary)
                    }
                }

                Spacer()

                // ML rank badge
                if let rank = suggestion.mlModelRank, rank > 0 {
                    VStack(spacing: 2) {
                        Text("ML")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(EEColors.textMuted)
                        Text("#\(rank)")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(rank <= 3 ? EEColors.blue : EEColors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(EEColors.blueDim))
                }
            }

            // Badges row: Odds, Units, Expected Return
            HStack(spacing: 8) {
                if let odds = suggestion.fixedWinOdds {
                    EEBadge(text: "$\(String(format: "%.2f", odds)) Fixed", color: EEColors.blue)
                }
                EEBadge(text: "\(suggestion.units) unit\(suggestion.units > 1 ? "s" : "")", color: EEColors.gold)
                if let ret = expectedReturn {
                    EEBadge(text: "\u{2192} $\(String(format: "%.2f", ret)) return", color: EEColors.emerald, style: .subtle)
                }
            }

            // ML win probability
            if let prob = suggestion.mlWinProb, prob > 0 {
                Text("ML Win: \(String(format: "%.1f", prob * 100))%\(fieldSize > 0 ? " | Rank \(suggestion.mlModelRank ?? 0)/\(fieldSize)" : "")")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(EEColors.blue)
            }

            // Pace and class assessment
            if let pace = suggestion.paceAssessment, !pace.isEmpty {
                Text("Pace: \(pace)")
                    .font(.caption2)
                    .foregroundStyle(EEColors.textSecondary)
            }
            if let classA = suggestion.classAssessment, !classA.isEmpty {
                Text("Class: \(classA)")
                    .font(.caption2)
                    .foregroundStyle(EEColors.textSecondary)
            }

            // AI reasoning
            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(EEColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Key badges pills
            if let badges = suggestion.keyBadges, !badges.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        let sentiment = badge.contains("(+)") ? "+" : badge.contains("(-)") ? "-" : "/"
                        BadgePill(text: badge.replacingOccurrences(of: " (+)", with: "").replacingOccurrences(of: " (-)", with: "").replacingOccurrences(of: " (/)", with: ""), sentiment: sentiment)
                    }
                }
            }

            // Log Bet Button
            if isLogged {
                Button(action: onToggleBet) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Bet Logged")
                    }
                }
                .buttonStyle(EEOutlineButtonStyle(color: EEColors.textMuted))
            } else {
                Button(action: onToggleBet) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Log Bet — $\(String(format: "%.0f", betAmount))")
                    }
                }
                .buttonStyle(EEGradientButtonStyle())
            }
        }
        .eeGlassCard(accent: EEColors.confidenceColor(for: suggestion.confidence))
    }
}

// MARK: - FlowLayout (for badge pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
