import SwiftUI
import SwiftData

struct MyBetsView: View {
    @Query(sort: \BetRecord.date, order: .reverse) private var bets: [BetRecord]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(bets) { bet in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(bet.horseName)
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
                                Text(result)
                                    .font(.caption.bold())
                                    .foregroundStyle(result == "Won" ? .green : .red)
                            } else {
                                HStack {
                                    Button("Won") {
                                        bet.result = "Won"
                                        bet.profit = bet.amount * 2.0   // simple example payout
                                        try? modelContext.save()
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
        }
    }
}
