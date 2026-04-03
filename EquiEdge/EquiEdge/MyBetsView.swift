import SwiftUI
import SwiftData

struct MyBetsView: View {
    @Query private var bets: [BetRecord]
    
    var body: some View {
        NavigationStack {
            List(bets) { bet in
                VStack(alignment: .leading) {
                    Text("\(bet.track) R\(bet.raceNumber) - \(bet.horseName)")
                    Text("Predicted: \(Int(bet.predictedProb * 100))% • \(bet.unitsBet) units")
                    if let result = bet.result {
                        Text("Result: \(result) • Profit: \(bet.profit ?? 0, specifier: "$%.0f")")
                    }
                }
            }
            .navigationTitle("Logged Bets")
        }
    }
}
