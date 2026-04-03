import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayRacesView().tabItem { Label("Today's Races", systemImage: "flag.fill") }.tag(0)
            MyBetsView().tabItem { Label("My Bets", systemImage: "banknote") }.tag(1)
            PerformanceView().tabItem { Label("Performance", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }.tag(3)
        }
        .tint(.green)
        .preferredColorScheme(.dark)
    }
}
