import SwiftUI
import SwiftData

struct PerformanceView: View {
    @Query(sort: \BetRecord.date, order: .reverse) private var bets: [BetRecord]
    @Environment(\.modelContext) private var modelContext
    
    private var totalStaked: Double {
        bets.reduce(0.0) { $0 + $1.amount }
    }
    
    private var totalProfit: Double {
        bets.reduce(0.0) { $0 + ($1.profit) }
    }
    
    private var winRate: Double {
        let wins = bets.filter { $0.result == "Won" }.count
        return bets.isEmpty ? 0 : Double(wins) / Double(bets.count) * 100
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    VStack {
                        Text("$\(Int(totalStaked))")
                            .font(.title.bold())
                        Text("Total Staked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack {
                        Text("$\(Int(totalProfit))")
                            .font(.title.bold())
                            .foregroundStyle(totalProfit >= 0 ? .green : .red)
                        Text("Total Profit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                
                VStack {
                    Text("\(Int(winRate))%")
                        .font(.largeTitle.bold())
                    Text("Win Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                
                List {
                    Section("Recent Bets") {
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
                                    Text("\(bet.units) units")
                                        .font(.subheadline)
                                    Text("$\(Int(bet.amount))")
                                        .font(.subheadline.bold())
                                    if let result = bet.result {
                                        Text(result)
                                            .font(.caption)
                                            .foregroundStyle(result == "Won" ? .green : .red)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Performance")
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
