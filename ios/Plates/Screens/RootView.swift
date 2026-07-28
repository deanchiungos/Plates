import SwiftUI

struct RootView: View {
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            PlateGallery()
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    @State private var selection = RootView.initialTab

    /// `-tab players` opens straight to a tab, so screens past the first can be
    /// screenshotted without driving the simulator by hand.
    private static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1].lowercased() {
            case "map": return 1
            case "badges": return 2
            case "trips": return 3
            case "players": return 4
            default: return 0
            }
        }
        #endif
        return 0
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            GameScreen()
                .tabItem { Label("Game", systemImage: "car.fill") }
                .tag(0)

            ComingSoon(title: "Map", symbol: "map",
                       note: "The state map, coloured by what you have found.")
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)

            ComingSoon(title: "Badges", symbol: "rosette",
                       note: "Milestones for streaks, rarities and completed trips.")
                .tabItem { Label("Badges", systemImage: "rosette") }
                .tag(2)

            ComingSoon(title: "Trips", symbol: "suitcase",
                       note: "Past roadtrips, with the plates and photos from each.")
                .tabItem { Label("Trips", systemImage: "suitcase") }
                .tag(3)

            PlayersScreen()
                .tabItem { Label("Players", systemImage: "person.2") }
                .tag(4)
        }
        .tint(Theme.route)
    }
}

struct ComingSoon: View {
    let title: String
    let symbol: String
    let note: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                ContentUnavailableView {
                    Label(title, systemImage: symbol)
                } description: {
                    Text(note)
                }
            }
            .navigationTitle(title)
        }
    }
}
