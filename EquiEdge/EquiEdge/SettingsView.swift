import SwiftUI

struct SettingsView: View {
    @AppStorage("unitSize") private var unitSize: Double = 10.0
    @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.41
    @AppStorage("useAI") private var useAI: Bool = true
    @StateObject private var dataService = DataService.shared
    
    @State private var isRefreshing = false
    @State private var refreshMessage: String = ""
    @State private var showRefreshConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Betting Units") {
                    VStack(alignment: .leading) {
                        Text("Unit Amount ($)")
                            .font(.headline)
                        Slider(value: $unitSize, in: 5...50, step: 5)
                        Text("$\(Int(unitSize)) per unit")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                    }
                }
                
                
                Section("Data Source") {
                    Toggle("Use AI Analysis (recommended)", isOn: $useAI)
                    
                    Button {
                        showRefreshConfirmation = true
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
                            .foregroundStyle(refreshMessage.contains("OK") ? .green : .red)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App Logs")
                                .font(.headline)
                            Spacer()
                            Button("Clear") {
                                dataService.clearLogs()
                            }
                            .font(.caption)
                        }
                        .padding(.top, 4)

                        if dataService.logs.isEmpty {
                            Text("No logs yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(dataService.logs.suffix(150).enumerated()), id: \.offset) { index, line in
                                            Text(line)
                                                .font(.caption2)
                                                .textSelection(.enabled)
                                                .monospaced()
                                                .id(index)
                                        }
                                    }
                                }
                                .frame(minHeight: 120, maxHeight: 240)
                                .onChange(of: dataService.logs.count) {
                                    if let last = dataService.logs.suffix(150).indices.last {
                                        proxy.scrollTo(last - dataService.logs.suffix(150).startIndex, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Text("App Version 1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Refresh Race Data",
                isPresented: $showRefreshConfirmation,
                titleVisibility: .visible
            ) {
                Button("Refresh Now") {
                    performRefresh()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will trigger a new scrape from the server. Existing data for today will be replaced.")
            }
        }
    }
    
    private func performRefresh() {
        Task {
            isRefreshing = true
            refreshMessage = ""
            
            do {
                try await dataService.refreshScrape()
                refreshMessage = "OK — Scrape refreshed successfully"
            } catch {
                refreshMessage = "Failed: \(error.localizedDescription)"
            }
            
            isRefreshing = false
        }
    }
}
