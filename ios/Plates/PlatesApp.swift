import SwiftUI
import SwiftData

@main
struct PlatesApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Trip.self, Player.self, Sighting.self)
        } catch {
            fatalError("Could not open the plates store: \(error)")
        }
        Self.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    /// First launch gets one player and one open trip, so the game screen has
    /// something real to show rather than an empty state.
    @MainActor
    private static func seedIfNeeded(_ context: ModelContext) {
        #if DEBUG
        if DemoData.isRequested {
            DemoData.install(into: context)
            return
        }
        #endif

        let playerCount = (try? context.fetchCount(FetchDescriptor<Player>())) ?? 0
        if playerCount == 0 {
            context.insert(Player(name: "Me", colorIndex: 0))
        }

        let tripCount = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0
        if tripCount == 0 {
            context.insert(Trip(name: "Summer Roadtrip"))
        }

        try? context.save()
    }
}
