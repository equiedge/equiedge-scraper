import SwiftUI
import SwiftData

@main
struct EquiEdgeApp: App {
    
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Race.self,
            BetSuggestion.self,
            BetRecord.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed — delete the old store and retry
            let url = modelConfiguration.url
            let related = [
                url,
                url.deletingPathExtension().appendingPathExtension("store-shm"),
                url.deletingPathExtension().appendingPathExtension("store-wal")
            ]
            for file in related {
                try? FileManager.default.removeItem(at: file)
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
