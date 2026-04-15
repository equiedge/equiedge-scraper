import SwiftUI
import SwiftData

// MARK: - Swipe to Delete Modifier

struct SwipeToDeleteModifier: ViewModifier {
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var showDelete = false

    private let deleteWidth: CGFloat = 80
    private let triggerThreshold: CGFloat = 120

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Delete background
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        offset = -500
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(EEColors.red))
                }
                .frame(width: deleteWidth)
            }

            // Main content
            content
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let translation = value.translation.width
                            if translation < 0 {
                                offset = translation
                            } else if showDelete {
                                offset = min(0, -deleteWidth + translation)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if -offset > triggerThreshold {
                                    // Full swipe — delete
                                    offset = -500
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onDelete()
                                    }
                                } else if -offset > deleteWidth * 0.5 {
                                    // Partial swipe — reveal delete button
                                    offset = -deleteWidth
                                    showDelete = true
                                } else {
                                    // Snap back
                                    offset = 0
                                    showDelete = false
                                }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func swipeToDelete(onDelete: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(onDelete: onDelete))
    }
}

struct MyBetsView: View {
    @Query(sort: \BetRecord.date, order: .reverse) private var bets: [BetRecord]
    @Environment(\.modelContext) private var modelContext

    @ObservedObject private var dataService = DataService.shared
    @State private var betAwaitingOdds: BetRecord?
    @State private var oddsText: String = ""
    @State private var selectedDate: String = "All"
    @State private var isCheckingResults = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var dateOptions: [String] {
        let days = Set(bets.map { Self.dayFormatter.string(from: $0.date) })
        return ["All"] + days.sorted { a, b in
            guard let da = Self.dayFormatter.date(from: a),
                  let db = Self.dayFormatter.date(from: b) else { return a < b }
            return da > db
        }
    }

    // MARK: - Filtered & Grouped

    private var filteredBets: [BetRecord] {
        let filtered = selectedDate == "All" ? Array(bets) : bets.filter { Self.dayFormatter.string(from: $0.date) == selectedDate }
        return filtered.sorted { a, b in
            let dayA = Calendar.current.startOfDay(for: a.date)
            let dayB = Calendar.current.startOfDay(for: b.date)
            if dayA != dayB { return dayA > dayB }
            let (trackA, numA) = Self.parseRaceInfo(a.raceInfo)
            let (trackB, numB) = Self.parseRaceInfo(b.raceInfo)
            if trackA != trackB { return trackA < trackB }
            return numA < numB
        }
    }

    private var activeBets: [BetRecord] {
        filteredBets.filter { $0.result == nil }
    }

    private var pendingWinBets: [BetRecord] {
        filteredBets.filter { $0.isPendingWin }
    }

    private var settledBets: [BetRecord] {
        filteredBets.filter { $0.result == "Won" || $0.result == "Lost" }
    }

    // Today's P&L
    private var todayPnL: Double {
        let todayBets = bets.filter { Calendar.current.isDateInToday($0.date) }
        return todayBets.reduce(0) { $0 + ($1.profit ?? 0) }
    }

    private static func parseRaceInfo(_ info: String) -> (String, Int) {
        guard let range = info.range(of: " R", options: .backwards) else {
            return (info, 0)
        }
        let track = String(info[info.startIndex..<range.lowerBound])
        let num = Int(info[range.upperBound...]) ?? 0
        return (track, num)
    }

    private func checkResults() async {
        let unsettled = bets.filter { $0.result == nil }
        guard !unsettled.isEmpty else { return }
        isCheckingResults = true
        await dataService.fetchRaceResults(bets: unsettled, in: modelContext)
        isCheckingResults = false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EEColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Quick P&L bar
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("TODAY'S P&L")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(EEColors.textMuted)
                                    .tracking(0.5)
                                Text("\(todayPnL >= 0 ? "+" : "")$\(String(format: "%.2f", todayPnL))")
                                    .font(.title3.weight(.heavy).monospacedDigit())
                                    .foregroundStyle(todayPnL >= 0 ? EEColors.emerald : EEColors.red)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("ACTIVE BETS")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(EEColors.textMuted)
                                    .tracking(0.5)
                                Text("\(activeBets.count)")
                                    .font(.title3.weight(.heavy).monospacedDigit())
                                    .foregroundStyle(EEColors.textPrimary)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [EEColors.emerald.opacity(0.08), EEColors.blue.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(EEColors.emerald.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 16)

                        // Date filter chips
                        if dateOptions.count > 2 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(dateOptions, id: \.self) { date in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedDate = date
                                            }
                                        } label: {
                                            Text(date)
                                                .eeChip(isActive: selectedDate == date)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Active Bets
                        if !activeBets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                EESectionHeader(title: "Active", color: EEColors.gold)
                                    .padding(.horizontal, 16)

                                ForEach(activeBets) { bet in
                                    ActiveBetRow(
                                        bet: bet,
                                        onWon: {
                                            oddsText = bet.odds != nil ? String(format: "%.2f", bet.odds!) : ""
                                            betAwaitingOdds = bet
                                        },
                                        onLost: {
                                            bet.result = "Lost"
                                            bet.profit = -bet.amount
                                            try? modelContext.save()
                                        },
                                        onDelete: {
                                            modelContext.delete(bet)
                                        }
                                    )
                                    .swipeToDelete { modelContext.delete(bet) }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Pending Wins (TAB confirmed winner, awaiting odds confirmation)
                        if !pendingWinBets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                EESectionHeader(title: "Pending Wins", color: EEColors.emerald)
                                    .padding(.horizontal, 16)

                                ForEach(pendingWinBets) { bet in
                                    PendingWinRow(
                                        bet: bet,
                                        onConfirmOdds: {
                                            oddsText = bet.odds != nil ? String(format: "%.2f", bet.odds!) : ""
                                            betAwaitingOdds = bet
                                        },
                                        onDelete: {
                                            modelContext.delete(bet)
                                        }
                                    )
                                    .swipeToDelete { modelContext.delete(bet) }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        // Settled Bets
                        if !settledBets.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                EESectionHeader(title: "Settled (\(settledBets.count))")
                                    .padding(.horizontal, 16)

                                ForEach(settledBets) { bet in
                                    SettledBetRow(bet: bet, onDelete: {
                                        modelContext.delete(bet)
                                    })
                                    .swipeToDelete { modelContext.delete(bet) }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if filteredBets.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "target")
                                    .font(.system(size: 40))
                                    .foregroundStyle(EEColors.textMuted)
                                Text("No Bets Yet")
                                    .font(.headline)
                                    .foregroundStyle(EEColors.textSecondary)
                                Text("Log your first bet from a race detail screen")
                                    .font(.subheadline)
                                    .foregroundStyle(EEColors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await checkResults() }
                    } label: {
                        if isCheckingResults {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isCheckingResults)
                }
            }
            .task {
                await checkResults()
            }
            .alert("Enter Winning Odds", isPresented: Binding(
                get: { betAwaitingOdds != nil },
                set: { if !$0 { betAwaitingOdds = nil } }
            )) {
                TextField("e.g. 3.50", text: $oddsText)
                    .keyboardType(.decimalPad)
                Button("Confirm") {
                    if let bet = betAwaitingOdds, let odds = Double(oddsText), odds > 0 {
                        bet.result = "Won"
                        bet.odds = odds
                        bet.profit = (bet.amount * odds) - bet.amount
                        try? modelContext.save()
                    }
                    betAwaitingOdds = nil
                }
                Button("Cancel", role: .cancel) {
                    betAwaitingOdds = nil
                }
            } message: {
                Text("Enter the decimal odds (e.g. 3.50 means $3.50 return per $1)")
            }
            .onChange(of: bets.count) {
                if !dateOptions.contains(selectedDate) {
                    selectedDate = "All"
                }
            }
        }
    }
}

// MARK: - Active Bet Row

struct ActiveBetRow: View {
    let bet: BetRecord
    let onWon: () -> Void
    let onLost: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bet.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(bet.raceInfo)
                        Text("•")
                        Text("\(bet.units)u")
                        Text("•")
                        Text("$\(Int(bet.amount))")
                    }
                    .font(.caption)
                    .foregroundStyle(EEColors.textMuted)
                }
                Spacer()
                if let odds = bet.odds {
                    EEBadge(text: "$\(String(format: "%.2f", odds))", color: EEColors.blue)
                }
            }

            HStack(spacing: 10) {
                Button(action: onLost) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Lost")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EEColors.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(EEColors.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(EEColors.red.opacity(0.25), lineWidth: 1)
                            )
                    )
                }

                Button(action: onWon) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Won")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(EEColors.edgeGradient)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(EEColors.borderSubtle, lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(EEColors.gold)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Bet", systemImage: "trash")
            }
        }
    }
}

// MARK: - Pending Win Row

struct PendingWinRow: View {
    let bet: BetRecord
    let onConfirmOdds: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bet.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(EEColors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(bet.raceInfo)
                        Text("\u{2022}")
                        Text("\(bet.units)u")
                        Text("\u{2022}")
                        Text("$\(Int(bet.amount))")
                    }
                    .font(.caption)
                    .foregroundStyle(EEColors.textMuted)
                }
                Spacer()
                if let odds = bet.odds {
                    EEBadge(text: "$\(String(format: "%.2f", odds))", color: EEColors.blue)
                }
            }

            Button(action: onConfirmOdds) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirm Win & Odds")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(EEColors.edgeGradient)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(EEColors.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(EEColors.emerald.opacity(0.3), lineWidth: 1)
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(EEColors.emerald)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Bet", systemImage: "trash")
            }
        }
    }
}

// MARK: - Settled Bet Row

struct SettledBetRow: View {
    let bet: BetRecord
    let onDelete: () -> Void

    private var isWin: Bool { bet.result == "Won" }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bet.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EEColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(bet.raceInfo)
                    Text("•")
                    Text("\(bet.units)u • $\(Int(bet.amount))")
                }
                .font(.caption2)
                .foregroundStyle(EEColors.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    EEBadge(
                        text: isWin ? "Won" : "Lost",
                        color: isWin ? EEColors.emerald : EEColors.red
                    )
                    if isWin, let odds = bet.odds {
                        Text("@ $\(String(format: "%.2f", odds))")
                            .font(.caption2)
                            .foregroundStyle(EEColors.textMuted)
                    }
                }
                if let profit = bet.profit {
                    Text("\(profit >= 0 ? "+" : "")$\(String(format: "%.2f", profit))")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(profit >= 0 ? EEColors.emerald : EEColors.red)
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
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isWin ? EEColors.emerald : EEColors.red)
                .frame(width: 3)
                .padding(.vertical, 8)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Bet", systemImage: "trash")
            }
        }
    }
}
