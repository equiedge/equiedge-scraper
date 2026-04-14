import SwiftUI

struct RunnerDetailView: View {
    let runner: Runner
    let race: Race
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EEColors.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Runner header
                    runnerHeader

                    // Speed Map section
                    if let sm = runner.speedMap {
                        speedMapSection(sm)
                    }

                    // Class Profile section
                    if let cp = runner.classProfile {
                        classProfileSection(cp)
                    }

                    // ML Prediction section
                    if let pred = runner.prediction {
                        predictionSection(pred)
                    }

                    // Stats breakdown
                    statsSection

                    // First-Up / Second-Up
                    if runner.stats?.firstUp != nil || runner.stats?.secondUp != nil {
                        freshStatsSection
                    }

                    // Badges / Decorators
                    if let badges = runner.decorators, !badges.isEmpty {
                        badgesSection(badges)
                    }

                    Spacer().frame(height: 40)
                }
                .padding()
            }
        }
        .navigationTitle("#\(runner.number) \(runner.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(EEColors.emerald)
            }
        }
    }

    // MARK: - Runner Header

    private var runnerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(runner.number) \(runner.name)")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(EEColors.textPrimary)

                    Text("J: \(runner.jockey) | T: \(runner.trainer)")
                        .font(.subheadline)
                        .foregroundStyle(EEColors.textSecondary)
                }
                Spacer()
                if let age = runner.age {
                    Text("\(age)yo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(EEColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                }
            }

            HStack(spacing: 12) {
                statPill(label: "Barrier", value: "\(runner.barrier)")
                statPill(label: "Weight", value: String(format: "%.1fkg", runner.weight))
                if let claim = runner.claim, claim > 0 {
                    statPill(label: "Claim", value: String(format: "-%.0fkg", claim))
                    statPill(label: "Effective", value: String(format: "%.1fkg", runner.effectiveWeight))
                }
            }

            // Form string
            VStack(alignment: .leading, spacing: 4) {
                Text("Form")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EEColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(runner.form.isEmpty ? "No form" : runner.form)
                    .font(.title3.weight(.bold).monospaced())
                    .foregroundStyle(EEColors.textPrimary)
                    .tracking(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - Speed Map

    private func speedMapSection(_ sm: SpeedMap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "Speed Map", color: EEColors.blue)

            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(sm.runningStyle)
                        .font(.title.weight(.heavy).monospaced())
                        .foregroundStyle(EEColors.blue)
                    Text(sm.runningStyleLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(EEColors.textSecondary)
                }
                .frame(width: 70)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Early Speed")
                            .font(.caption2)
                            .foregroundStyle(EEColors.textMuted)
                        Spacer()
                        Text(String(format: "%.1f", sm.earlySpeedIndex))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(EEColors.textPrimary)
                    }
                    ProgressView(value: sm.earlySpeedIndex, total: 10)
                        .tint(EEColors.blue)

                    HStack {
                        Text("Settling Pos")
                            .font(.caption2)
                            .foregroundStyle(EEColors.textMuted)
                        Spacer()
                        Text(String(format: "%.1f", sm.settlingPosition))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(EEColors.textPrimary)
                    }
                }
            }

            // Pace scenario context
            if let pace = race.paceScenario {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.caption2)
                        .foregroundStyle(EEColors.textMuted)
                    Text("Race pace: \(pace.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption2)
                        .foregroundStyle(EEColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - Class Profile

    private func classProfileSection(_ cp: ClassProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "Class Profile", color: EEColors.gold)

            // Rating bar visualization
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current: \(cp.currentRating)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)
                    Spacer()
                    Text("Peak: \(cp.peakRating)")
                        .font(.caption)
                        .foregroundStyle(EEColors.textMuted)
                }

                // Optimal range bar
                GeometryReader { geo in
                    let width = geo.size.width
                    let maxRating = max(cp.peakRating, 100)
                    let optMinX = width * CGFloat(cp.optimalRangeMin) / CGFloat(maxRating)
                    let optMaxX = width * CGFloat(cp.optimalRangeMax) / CGFloat(maxRating)
                    let currentX = width * CGFloat(cp.currentRating) / CGFloat(maxRating)

                    ZStack(alignment: .leading) {
                        // Full bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 8)

                        // Optimal range
                        RoundedRectangle(cornerRadius: 3)
                            .fill(EEColors.gold.opacity(0.3))
                            .frame(width: max(0, optMaxX - optMinX), height: 8)
                            .offset(x: optMinX)

                        // Current rating marker
                        Circle()
                            .fill(EEColors.gold)
                            .frame(width: 12, height: 12)
                            .offset(x: currentX - 6)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("Optimal: \(cp.optimalRangeMin)-\(cp.optimalRangeMax)")
                        .font(.caption2)
                        .foregroundStyle(EEColors.textMuted)
                    Spacer()
                    Text("Won up to: \(cp.highestClassWon)")
                        .font(.caption2)
                        .foregroundStyle(EEColors.textMuted)
                }

                // Trend indicator
                HStack(spacing: 6) {
                    Image(systemName: trendIcon(cp.trend))
                        .font(.caption2)
                        .foregroundStyle(trendColor(cp.trend))
                    Text("Trend: \(cp.trend.capitalized)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor(cp.trend))
                }
            }

            // Race fit
            if let fit = runner.raceClassFit {
                Divider().overlay(EEColors.borderSubtle)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Race Fit")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EEColors.textMuted)
                            .textCase(.uppercase)
                        Text(fit.assessmentLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(fitColor(fit.assessment))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Class Diff")
                            .font(.caption2)
                            .foregroundStyle(EEColors.textMuted)
                        Text("\(fit.classDifference > 0 ? "+" : "")\(fit.classDifference)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(fit.classDifference <= 0 ? EEColors.emerald : EEColors.red)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("In Range")
                            .font(.caption2)
                            .foregroundStyle(EEColors.textMuted)
                        Image(systemName: fit.withinOptimalRange ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(fit.withinOptimalRange ? EEColors.emerald : EEColors.red)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - ML Prediction

    private func predictionSection(_ pred: RacePrediction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "ML Prediction", color: EEColors.emerald)

            HStack(spacing: 16) {
                EEStatCard(
                    value: String(format: "%.1f%%", pred.winProb * 100),
                    label: "Win Prob",
                    valueColor: EEColors.emerald
                )
                EEStatCard(
                    value: String(format: "%.1f%%", pred.placeProb * 100),
                    label: "Place Prob",
                    valueColor: EEColors.blue
                )
                EEStatCard(
                    value: "#\(pred.modelRank)",
                    label: "Rank / \(race.runners.count)",
                    valueColor: pred.modelRank <= 3 ? EEColors.emerald : EEColors.textPrimary
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - Career Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "Career Stats")

            if let stats = runner.stats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    if let o = stats.overall {
                        statRow("Overall", o)
                    }
                    if let t = stats.track {
                        statRow("Track", t)
                    }
                    if let d = stats.distance {
                        statRow("Distance", d)
                    }
                    if let c = stats.condition {
                        statRow("Condition", c)
                    }
                }
            } else {
                Text("No stats available")
                    .font(.caption)
                    .foregroundStyle(EEColors.textMuted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    private func statRow(_ label: String, _ stat: RunnerStatCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(EEColors.textMuted)
                .textCase(.uppercase)

            HStack(spacing: 4) {
                Text("\(stat.starts): \(stat.wins)-\(stat.seconds)-\(stat.thirds)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(EEColors.textPrimary)
            }

            HStack(spacing: 8) {
                Text("W \(String(format: "%.0f", stat.winPercent))%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(EEColors.emerald)
                Text("P \(String(format: "%.0f", stat.placePercent))%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(EEColors.blue)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    // MARK: - First-Up / Second-Up

    private var freshStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "Fresh Stats")

            HStack(spacing: 12) {
                if let fu = runner.stats?.firstUp {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First-Up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EEColors.textMuted)
                            .textCase(.uppercase)
                        Text("\(fu.starts) starts, \(fu.wins)W")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EEColors.textPrimary)
                        HStack(spacing: 6) {
                            Text("W \(String(format: "%.0f", fu.winPercent))%")
                                .foregroundStyle(EEColors.emerald)
                            Text("P \(String(format: "%.0f", fu.placePercent))%")
                                .foregroundStyle(EEColors.blue)
                        }
                        .font(.caption2.weight(.bold))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                }

                if let su = runner.stats?.secondUp {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Second-Up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EEColors.textMuted)
                            .textCase(.uppercase)
                        Text("\(su.starts) starts, \(su.wins)W")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(EEColors.textPrimary)
                        HStack(spacing: 6) {
                            Text("W \(String(format: "%.0f", su.winPercent))%")
                                .foregroundStyle(EEColors.emerald)
                            Text("P \(String(format: "%.0f", su.placePercent))%")
                                .foregroundStyle(EEColors.blue)
                        }
                        .font(.caption2.weight(.bold))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - Badges

    private func badgesSection(_ badges: [FormBadge]) -> some View {
        let categories = Dictionary(grouping: badges, by: \.category)
        let sortedCategories = categories.keys.sorted()

        return VStack(alignment: .leading, spacing: 12) {
            EESectionHeader(title: "Form Badges (\(badges.count))")

            ForEach(sortedCategories, id: \.self) { category in
                if let catBadges = categories[category] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(EEColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        ForEach(catBadges) { badge in
                            HStack(alignment: .top, spacing: 8) {
                                Text(badge.sentiment)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(sentimentColor(badge.sentiment))
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(badge.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(EEColors.textPrimary)

                                    if !badge.detail.isEmpty {
                                        Text(badge.detail)
                                            .font(.caption2)
                                            .foregroundStyle(EEColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EEColors.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(EEColors.borderSubtle, lineWidth: 1))
        )
    }

    // MARK: - Helpers

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(EEColors.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(EEColors.textMuted)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment {
        case "+": return EEColors.emerald
        case "-": return EEColors.red
        default: return EEColors.textSecondary
        }
    }

    private func trendIcon(_ trend: String) -> String {
        switch trend.lowercased() {
        case "rising": return "arrow.up.right"
        case "dropping": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend.lowercased() {
        case "rising": return EEColors.emerald
        case "dropping": return EEColors.red
        default: return EEColors.textSecondary
        }
    }

    private func fitColor(_ assessment: String) -> Color {
        switch assessment {
        case "big_drop", "slight_drop": return EEColors.emerald
        case "comfort_zone": return EEColors.blue
        case "slight_rise": return EEColors.gold
        case "big_rise": return EEColors.red
        default: return EEColors.textSecondary
        }
    }
}
