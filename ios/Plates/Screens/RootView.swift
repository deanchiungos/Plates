import SwiftUI

struct RootView: View {
    #if DEBUG
    /// The text after `-lookup`, if any.
    static var launchQuery: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-lookup"), i + 1 < args.count,
              !args[i + 1].hasPrefix("-") else { return "" }
        return args[i + 1]
    }
    #endif

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-gallery") {
            PlateGallery()
        } else if ProcessInfo.processInfo.arguments.contains("-bench") {
            PlateBench()
        } else if ProcessInfo.processInfo.arguments.contains("-lookup") {
            // `-lookup "palm tree"` opens the lookup with the query already
            // typed. The screen is three taps deep and the results depend on
            // text input, neither of which a launch argument can otherwise reach.
            NavigationStack {
                PlateLookupScreen(initialQuery: Self.launchQuery)
            }
        } else if ProcessInfo.processInfo.arguments.contains("-history") {
            // Two taps deep, behind More. Same reason as `-lookup`.
            NavigationStack { HistoricalPlatesScreen() }
        } else if ProcessInfo.processInfo.arguments.contains("-iconLab") {
            IconLab()
        } else if ProcessInfo.processInfo.arguments.contains("-fontLab") {
            FontLab()
        } else if ProcessInfo.processInfo.arguments.contains("-exportIcons") {
            IconExportView()
        } else {
            shell
        }
        #else
        shell
        #endif
    }

    @State private var selection = RootView.initialTab
    @State private var popup = PopupHost()

    /// The popup layer sits outside the `TabView`, so a prompt covers the tab bar
    /// instead of floating above it. Anything inside a tab reaches it through the
    /// environment.
    private var shell: some View {
        ZStack {
            tabs
            PopupLayer(host: popup)
        }
        .environment(popup)
    }

    /// `-tab players` opens straight to a tab, so screens past the first can be
    /// screenshotted without driving the simulator by hand.
    private static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1].lowercased() {
            case "map": return 1
            case "book", "badges": return 2
            case "trips": return 3
            case "players", "more": return 4
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

            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)

            CollectionScreen()
                .tabItem { Label("Book", systemImage: "books.vertical") }
                .tag(2)

            TripsScreen()
                .tabItem { Label("Trips", systemImage: "suitcase") }
                .tag(3)

            MoreScreen()
                .tabItem { Label("More", systemImage: "ellipsis") }
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
