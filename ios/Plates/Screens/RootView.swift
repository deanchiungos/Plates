import SwiftData
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
            harness(NavigationStack {
                PlateLookupScreen(initialQuery: Self.launchQuery)
            })
        } else if ProcessInfo.processInfo.arguments.contains("-history") {
            // Two taps deep, behind More. Same reason as `-lookup`.
            harness(NavigationStack { HistoricalPlatesScreen() })
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

    @State private var router = Router(tab: RootView.initialTab)
    @State private var popup = PopupHost()
    /// Only the arbiter lives at the root. The balloons themselves are drawn by a
    /// `CoachLayer` inside each screen, because a mark has to move with the row or
    /// tile it points at — see the note on `CoachLayer`.
    @State private var coach = CoachPresenter()
    /// The guided walk, one tab at a time. Lives beside the coach rather than inside
    /// it because they are opposites that happen to share a subject — see `Tour`.
    @State private var tour = TourGuide()
    private let deepLink = DeepLink.shared

    #if DEBUG
    /// The environment a screen needs, for the debug branches that render one directly
    /// instead of through `shell`.
    ///
    /// These used to be plain screens with no dependencies, so the branches above could
    /// hand back a bare `NavigationStack`. They are not any more: a screen that hosts a
    /// tour reads the guide and the popup host out of the environment, and a missing
    /// `@Environment` of an observable type is a crash on the first render rather than a
    /// nil. So the flags get the same furniture the app does.
    private func harness(_ screen: some View) -> some View {
        screen
            .environment(popup)
            .environment(router)
            .environment(coach)
            .environment(tour)
    }
    #endif

    @State private var welcoming = false
    @State private var namingAfterWelcome = false
    /// Whether the card was dismissed with Skip, read once by `afterWelcome`.
    @State private var skipped = false

    /// Whether this launch is somebody's first.
    ///
    /// Three conditions, and the third is not redundant. `hasProfile` is false on a
    /// *restored* install too — a new phone signed into an old iCloud account has
    /// never said who it is on this device — and that person is emphatically not new
    /// to the app. Their players arrive from sync, so an empty roster is the thing
    /// that actually separates "new" from "not delivered yet", and `IdentityPrompt`
    /// handles the second case on its own.
    ///
    /// Read from the store directly rather than through a `@Query`, because this is
    /// asked once, at launch, and a live query on the root would re-evaluate the
    /// whole shell every time anybody joined a party.
    private var shouldWelcome: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-welcome") { return true }
        #endif
        guard !Coach.seen(.welcome), !DevicePlayer.hasProfile else { return false }
        return ((try? PlatesStore.context.fetchCount(FetchDescriptor<Player>())) ?? 0) == 0
    }

    private func closeWelcome(skipping: Bool) {
        skipped = skipping
        Coach.markSeen(.welcome)
        // Skip stands down the fork's extra line too. Somebody who declined the one
        // sentence of introduction is not asking for a second one.
        if skipping { Coach.markSeen(.fork) }
        welcoming = false
    }

    /// The second beat, once the card is off screen.
    ///
    /// A sheet cannot be presented while a `fullScreenCover` is still going away, so
    /// this hangs off `onDismiss` rather than following the button.
    ///
    /// Skipping does not skip the name — it only skips being asked *here*. The Game
    /// screen asks anyway the moment there is a trip or a book to fill, which is a
    /// better moment for it, and this is simply the one place the flow can offer it
    /// before that. Nothing depends on having a name: a sighting with no owner is a
    /// legal, ordinary thing in this app.
    private func afterWelcome() {
        guard !skipped, !DevicePlayer.hasProfile else { return }
        namingAfterWelcome = true
    }

    /// Taken, not read. A destination left sitting would re-navigate every time the
    /// app came back from the background.
    private func consumeDeepLink() {
        switch deepLink.take() {
        case .collect: router.tab = RootView.gameTab
        case nil: break
        }
    }

    /// The popup layer sits outside the `TabView`, so a prompt covers the tab bar
    /// instead of floating above it. Anything inside a tab reaches it through the
    /// environment.
    private var shell: some View {
        ZStack {
            tabs
            PopupLayer(host: popup)
        }
        .environment(popup)
        .environment(router)
        .environment(coach)
        .environment(tour)
        // Full-screen rather than a sheet: a card you can swipe away by accident
        // before reading the one sentence it exists to show is not a welcome, and a
        // sheet leaves the tab bar visible underneath, which gives away the whole
        // shape of the app before anybody has been told what it is for.
        .fullScreenCover(isPresented: $welcoming, onDismiss: afterWelcome) {
            WelcomeCard(onPlay: { closeWelcome(skipping: false) },
                        onSkip: { closeWelcome(skipping: true) })
        }
        .sheet(isPresented: $namingAfterWelcome) {
            IdentityPrompt(saveLabel: "Continue")
        }
        .onAppear { if shouldWelcome { welcoming = true } }
        // No tour underneath the welcome card, or the name sheet that follows it. The
        // card is the app introducing itself and the sheet is it asking who you are;
        // the tour is the app showing you around. In that order, or they talk over
        // each other on the one screen where a first impression is made.
        //
        // The tour is deferred rather than dropped, and picks itself up the moment
        // this goes false. See `TourGuide.deferred`.
        .onChange(of: welcoming || namingAfterWelcome, initial: true) { _, busy in
            tour.isSuspended = busy
        }
        // "Replay the tour", from Settings. Watched rather than called, because the
        // card belongs to the root and the button is four levels down a tab.
        .onChange(of: coach.replayRequest) { _, _ in
            tour.replay()
            router.tab = RootView.gameTab
            welcoming = true
        }
        // The clean slate at the end of the last tab's tour. Each tour puts its own
        // screen back where it found it; this is the one extra beat the whole
        // sequence gets, and only once every tab has actually been walked through.
        .onChange(of: tour.finishedEverything) { _, done in
            guard done else { return }
            tour.clearFinishedFlag()
            withAnimation(.snappy(duration: 0.35)) { router.tab = RootView.gameTab }
        }
        // The widget's one tap. `plates://collect` puts the grid up, which is the
        // whole promise of tapping a progress bar on a home screen — anything else
        // would be an app launch with extra steps.
        //
        // Watched rather than handled: the URL arrives at the app delegate, which is
        // outside this hierarchy, so `DeepLink` is where the two meet.
        .onChange(of: deepLink.pending) { _, _ in consumeDeepLink() }
        .onAppear { consumeDeepLink() }
    }

    /// Where the More tab sits — the `Router` needs to name it to jump there.
    static let gameTab = 0
    static let moreTab = 4

    /// `-tab players` opens straight to a tab, so screens past the first can be
    /// screenshotted without driving the simulator by hand.
    static var initialTab: Int {
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
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            GameScreen()
                .tabItem { Label("Game", systemImage: "car.fill") }
                .tag(0)

            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(1)

            CollectionScreen()
                .tabItem { Label("Books", systemImage: "books.vertical") }
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

