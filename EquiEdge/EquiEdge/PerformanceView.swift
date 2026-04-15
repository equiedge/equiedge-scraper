import SwiftUI
import SwiftData

struct PerformanceView: View {
    @Query private var bets: [BetRecord]
    @Environment(\.modelContext) private var modelContext

    private var totalStaked: Double {
        bets.reduce(0) { $0 + $1.amount }
    }

    private var totalProfit: Double {
        bets.reduce(0) { $0 + ($1.profit ?? 0) }
    }

    private var winRate: Double {
        let settled = bets.filter { $0.result != nil }
        guard !settled.isEmpty else { return 0 }
        let wins = settled.filter { $0.result == "Won" }.count
        return Double(wins) / Double(settled.count) * 100
    }

    private var roi: Double {
        guard totalStaked > 0 else { return 0 }
        return (totalProfit / totalStaked) * 100
    }

    private var bestStreak: Int {
        var maxStreak = 0
        var current = 0
        let sorted = bets.sorted { $0.date < $1.date }
        for bet in sorted {
            if bet.result == "Won" {
                current += 1
                maxStreak = max(maxStreak, current)
            } else if bet.result == "Lost" {
                current = 0
            }
        }
        return maxStreak
    }

    /// Running P&L over time for sparkline
    private var pnlHistory: [Double] {
        let sorted = bets
            .filter { $0.result != nil }
            .sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [0] }

        var running: Double = 0
        var points: [Double] = [0]
        for bet in sorted {
            running += bet.profit ?? 0
            points.append(running)
        }
        return points
    }

    private var sortedBets: [BetRecord] {
        bets.sorted { a, b in
            let dayA = Calendar.current.startOfDay(for: a.date)
            let dayB = Calendar.current.startOfDay(for: b.date)
            if dayA != dayB { return dayA > dayB }
            let (trackA, numA) = Self.parseRaceInfo(a.raceInfo)
            let (trackB, numB) = Self.parseRaceInfo(b.raceInfo)
            if trackA != trackB { return trackA < trackB }
            return numA < numB
        }
    }

    private static func parseRaceInfo(_ info: String) -> (String, Int) {
        guard let range = info.range(of: " R", options: .backwards) else {
            return (info, 0)
        }
        let track = String(info[info.startIndex..<range.lowerBound])
        let num = Int(info[range.upperBound...]) ?? 0
        return (track, num)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EEColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Hero P&L
                        VStack(spacing: 4) {
                            Text("TOTAL PROFIT / LOSS")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(EEColors.textMuted)
                                .tracking(1)

                            Text("\(totalProfit >= 0 ? "+" : "")$\(String(format: "%.2f", totalProfit))")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(totalProfit >= 0 ? EEColors.emerald : EEColors.red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Sparkline
                        if pnlHistory.count > 1 {
                            SparklineChart(
                                dataPoints: pnlHistory,
                                lineColor: totalProfit >= 0 ? EEColors.emerald : EEColors.red,
                                height: 60
                            )
                            .padding(.horizontal, 16)
                        }

                        // Stats Grid 2x2
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            EEStatCard(
                                value: "\(String(format: "%.1f", winRate))%",
                                label: "Win Rate",
                                valueColor: EEColors.emerald
                            )
                            EEStatCard(
                                value: "\(roi >= 0 ? "+" : "")\(String(format: "%.1f", roi))%",
                                label: "ROI",
                                valueColor: roi >= 0 ? EEColors.blue : EEColors.red
                            )
                            EEStatCard(
                                value: "$\(String(format: "%.0f", totalStaked))",
                                label: "Staked",
                                valueColor: EEColors.textPrimary
                            )
                            EEStatCard(
                                value: "\(bestStreak)🔥",
                                label: "Best Streak",
                                valueColor: EEColors.gold
                            )
                        }
                        .padding(.horizontal, 16)

                        // Recent Bets
                        if !sortedBets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                EESectionHeader(title: "All Bets (\(bets.count))")
                                    .padding(.horizontal, 16)

                                LazyVStack(spacing: 8) {
                                    ForEach(sortedBets) { bet in
                                        PerformanceBetRow(bet: bet)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        Spacer().frame(height: 100)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EEBrandedTitle()
                }
            }
        }
    }
}

// MARK: - Performance Bet Row

struct PerformanceBetRow: View {
    let bet: BetRecord

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bet.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EEColors.textPrimary)
                    .lineLimit(1)

                Text(bet.raceInfo)
                    .font(.caption2)
                    .foregroundStyle(EEColors.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let result = bet.result {
                    EEBadge(
                        text: result,
                        color: result == "Won" ? EEColors.emerald : EEColors.red
                    )

                    if let profit = bet.profit {
                        Text("\(profit >= 0 ? "+" : "")$\(String(format: "%.2f", profit))")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(profit >= 0 ? EEColors.emerald : EEColors.red)
                    }
                } else {
                    EEBadge(text: "Pending", color: EEColors.gold)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
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
