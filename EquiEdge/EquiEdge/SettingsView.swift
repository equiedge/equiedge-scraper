import SwiftUI

struct SettingsView: View {
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.41
    @AppStorage("useGrokAI") private var useGrokAI: Bool = true   // ← Added this
    
    @State private var isRefreshing = false
    @State private var refreshMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Betting Units") {
                    VStack(alignment: .leading) {
                        Text("Unit Amount ($)")
                            .font(.headline)
                        Slider(value: $unitSize, in: 5...50, step: 1)
                        Text("$\(Int(unitSize)) per unit")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                    }
                }
                
                
                Section("Data Source") {
                    Toggle("Use Grok AI Analysis (recommended)", isOn: $useGrokAI)
                    
                    Button {
                        Task {
                            isRefreshing = true
                            refreshMessage = "Triggering scrape..."
                            
                            do {
                                try await DataService.shared.refreshScrape()
                                refreshMessage = "✅ Scrape refreshed successfully"
                            } catch {
                                refreshMessage = "❌ Refresh failed: \(error.localizedDescription)"
                            }
                            
                            isRefreshing = false
                        }
                    } label: {
                        HStack {
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isRefreshing ? "Refreshing..." : "Manual Refresh Scrape")
                        }
                    }
                    .disabled(isRefreshing)
                    
                    if !refreshMessage.isEmpty {
                        Text(refreshMessage)
                            .font(.caption)
                            .foregroundStyle(refreshMessage.contains("✅") ? .green : .red)
                    }
                }
                
                Section {
                    Text("App Version 1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
