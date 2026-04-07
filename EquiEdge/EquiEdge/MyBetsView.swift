import SwiftUI
import SwiftData

struct MyBetsView: View {
    @Query(sort: \BetRecord.date, order: .reverse) private var bets: [BetRecord]
    @Environment(\.modelContext) private var modelContext
    
    @State private var betAwaitingOdds: BetRecord?
    @State private var oddsText: String = ""
    @State private var selectedDate: String = "All"
    
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    
    private var dateOptions: [String] {
        let days = Set(bets.map { Self.dayFormatter.string(from: $0.date) })
        return ["All"] + days.sorted { a, b in
            // Sort date strings by parsing back to dates (most recent first)
            guard let da = Self.dayFormatter.date(from: a),
                  let db = Self.dayFormatter.date(from: b) else { return a < b }
            return da > db
        }
    }
    
    private var filteredBets: [BetRecord] {
        if selectedDate == "All" {
            return bets
        }
        return bets.filter { Self.dayFormatter.string(from: $0.date) == selectedDate }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if dateOptions.count > 2 {
                    Picker("Date", selection: $selectedDate) {
                        ForEach(dateOptions, id: \.self) { date in
                            Text(date).tag(date)
                        }
                    }
                }
                
                ForEach(filteredBets) { bet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(bet.displayName)
                                .font(.headline)
                            Text(bet.raceInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(bet.units) units • $\(Int(bet.amount))")
                                .font(.subheadline)
                            if let result = bet.result {
                                HStack(spacing: 4) {
                                    Text(result)
                                        .font(.caption.bold())
                                        .foregroundStyle(result == "Won" ? .green : .red)
                                    if result == "Won", let odds = bet.odds {
                                        Text("@ $\(odds, specifier: "%.2f")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                HStack {
                                    Button("Won") {
                                        oddsText = ""
                                        betAwaitingOdds = bet
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    
                                    Button("Lost") {
                                        bet.result = "Lost"
                                        bet.profit = -bet.amount
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Bets")
            .toolbar {
                Button("Clear All") {
                    for bet in bets {
                        modelContext.delete(bet)
                    }
                }
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
