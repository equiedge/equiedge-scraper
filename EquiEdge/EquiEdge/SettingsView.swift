import SwiftUI

struct SettingsView: View {
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.28
    @State private var isRefreshing = false
    @State private var refreshMessage = ""
    
    var body: some View {
        Form {
            Section("Betting") {
                HStack {
                    Text("Unit Size ($)")
                    Spacer()
                    TextField("Unit", value: $unitSize, format: .number)
                        .keyboardType(.decimalPad)           // This now works on iOS
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)      // Optional: makes it look nicer
                }
            }
            
            Section("Analysis") {
                VStack(alignment: .leading) {
                    Text("Confidence Threshold: \(Int(confidenceThreshold * 100))%")
                    Slider(value: $confidenceThreshold, in: 0.15...0.45, step: 0.01)
                }
            }
            
            Section("Data Source") {
                Button {
                    Task {
                        isRefreshing = true
                        refreshMessage = "Triggering scrape..."
                        let success = await DataService.shared.refreshScrape()
                        isRefreshing = false
                        refreshMessage = success ? "✅ Scrape refreshed successfully" : "❌ Refresh failed"
                    }
                } label: {
                    HStack {
                        Text("Manual Refresh Scrape (Sky Racing World)")
                        if isRefreshing {
                            ProgressView()
                        }
                    }
                }
                
                if !refreshMessage.isEmpty {
                    Text(refreshMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Text("This forces the backend to re-scrape today's races immediately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Section("About") {
                Text("EquiEdge only suggests high-certainty bets.\nStakes scale with confidence (1-5 units).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
