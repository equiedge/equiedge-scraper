import SwiftUI
import SwiftData   // ← THIS IS THE MISSING IMPORT
import Charts

struct PerformanceView: View {
    
    @Query private var bets: [BetRecord]
    
    var totalStaked: Double {
        bets.reduce(0) { $0 + Double($1.unitsBet) * $1.unitSize }
    }
    
    var totalProfit: Double {
        bets.compactMap { $0.profit }.reduce(0, +)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("ROI: \(totalStaked > 0 ? (totalProfit / totalStaked * 100) : 0, specifier: "%.1f")%")
                    .font(.largeTitle.bold())
                
                if !bets.isEmpty {
                    Chart(bets.prefix(10)) { bet in
                        BarMark(
                            x: .value("Race", "\(bet.track) R\(bet.raceNumber)"),
                            y: .value("Profit", bet.profit ?? 0)
                        )
                    }
                    .frame(height: 200)
                    .padding()
                } else {
                    Text("No bets logged yet")
                        .foregroundStyle(.secondary)
                        .padding()
                }
                
                List(bets) { bet in
                    Text("\(bet.horseName) • \(bet.unitsBet) units")
                }
            }
            .navigationTitle("Performance")
        }
    }
}
