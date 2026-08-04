import SwiftUI
import SwiftData

struct GameScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]

    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    @AppStorage(PlateFilter.key) private var filter = PlateFilter()

    private let location = TripLocation.shared
    private let handoff = VoiceHandoff.shared

    @State private var canadaExpanded = false
    @State private var query = ""
    @State private var searchOpen = false

    #if DEBUG
    /// `-search cactus` opens the grid with a search already running. The field
    /// needs a keyboard to reach otherwise, and the appearance matching this
    /// exercises is the whole reason the field stopped forcing capitals.
    private static var launchSearch: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-search"), i + 1 < args.count,
              !args[i + 1].hasPrefix("-") else { return "" }
        return args[i + 1]
    }
    #endif
    #if DEBUG
    /// `-voice "new jersey ohio texas"` opens voice mode with that transcript already
    /// running. Set here rather than flipped in `onAppear`, which does not present a
    /// sheet reliably on the first render.
    @State private var listening = VoiceModeScreen.launchTranscript != nil
                                || VoiceModeScreen.launchPlate != nil
    #else
    // Never on launch. Voice mode opens from the waveform button or from Siri's
    // "log plates in Plates", and from nowhere else.
    @State private var listening = false
    #endif
    @State private var addingPlayer = false
    @State private var creatingTrip = false
    @State private var creatingBook = false

    /// The find currently being celebrated. The id restarts the animation even when
    /// the same plate is found twice in a row.
    @State private var celebrating: Celebration?

    private struct Celebration: Identifiable {
        let id = UUID()
        let plate: Plate
        let tier: RarityTier
        /// Drawn once, when the find happens. Asking `FactBook` from inside `body`
        /// would deal a new card on every re-render and burn through the unseen pile
        /// without anyone reading them.
        let fact: String?
    }

    /// Trip or book — whichever is being filled. Everything below reads from
    /// `target.collection`, so the grid does not care which it is.
    private var target: PlayTarget? {
        PlaySelection.current(kind: targetKind, tripID: currentTripID,
                              bookID: currentBookID, trips: trips, books: books)
    }

    private var collection: (any PlateCollection)? { target?.collection }

    /// Resolved once per render rather than per tile. `PlateRarity` memoises the
    /// table too, but 65 dictionary lookups still beat 65 calls through the route.
    /// Rarity for every plate at once, for the tile pips.
    ///
    /// The live table, then claimed plates overwritten with what they were banked
    /// at. Without that second step the grid would keep revaluing plates you have
    /// already collected as you drove past their home state.
    ///
    /// The banked half is applied even with no route to speak of — a book that has
    /// never had a location fix still knows what each plate was worth at the moment
    /// it was claimed, and that is the number the found tile's pip is coloured by.
    private var rarities: [String: Int] {
        guard let collection else { return [:] }
        var table = collection.route.map { PlateRarity.table(for: $0) } ?? [:]
        for code in collection.seenCodes {
            if let claimed = collection.claimedRarity(of: code) { table[code] = claimed }
        }
        return table
    }

    /// Why the car is not on the rail, if it is not.
    ///
    /// Every precondition here used to fail silently: no permission, no destination
    /// pinned, no fix yet — all of them just produced a rail with nothing on it and
    /// no way to tell which was missing. An invisible feature reads as a broken one.
    /// Books get this card too, minus the two states that are about a road.
    ///
    /// A book has no destination to pin and no rail to put a car on, so those two
    /// would be nonsense. What it does have is rarity, which is the reason the
    /// permission is worth granting at all — so the ask has to be offered somewhere,
    /// and this is the only place it exists.
    private var trackingState: TrackingHintCard.State? {
        guard let target else { return nil }
        if !location.hasBeenAsked { return .needsPermission }
        if !location.isAuthorized { return .denied }
        switch target {
        case .trip(let trip):
            guard trip.isActive else { return nil }
            if trip.destinationCoordinate == nil { return .needsDestination }
            if trip.currentCoordinate == nil { return .locating }
        case .book(let book):
            if book.currentLat == nil { return .locating }
        }
        return nil          // everything is in place; the rail speaks for itself
    }

    /// Started while the Drive screen is up and stopped when it is not, so the GPS
    /// is never running because the app merely happens to be installed.
    /// Books track too.
    ///
    /// This used to bail unless the collection was a `Trip` with a pinned route, on
    /// the reasoning that only a trip has a road to move along. But the rail is not
    /// the only thing a fix feeds — rarity is the other, and rarity is the whole
    /// scoring system. A book that never asked for a fix could only ever be scored
    /// against the national table, which knows how many cars a state has registered
    /// and nothing whatever about where you are standing.
    private func beginTracking() {
        guard let target else { return }
        switch target {
        case .trip(let trip):
            guard trip.route != nil, trip.isActive else { return }
            // Deliberately does *not* request. The system prompt is a one-shot —
            // answer it once and it never comes back — so firing it unannounced the
            // first time someone opens a trip spends the only chance on a moment
            // when they have no idea what it is for. `TrackingHintCard` asks, in
            // words, first.
            //
            // Re-tuned per trip, because how often the car should move depends
            // entirely on how long the drive is.
            if let origin = trip.originCoordinate, let destination = trip.destinationCoordinate {
                location.tune(forRouteLength: GreatCircle.metres(origin, destination))
            }
        case .book:
            // No route, so no length to tune against — the default filter is the
            // right one. Only starts if permission has already been granted, since a
            // book has no hint card to ask on its behalf.
            guard location.isAuthorized else { return }
            location.tune(forRouteLength: nil)
        }
        location.start()
    }

    /// Writes the fix onto whatever is being filled, so the rail and the rarity
    /// survive a relaunch.
    private func persistLocation() {
        guard let target, let here = location.coordinate else { return }
        switch target {
        case .trip(let trip):
            guard trip.isActive else { return }
            trip.currentLat = here.latitude
            trip.currentLon = here.longitude
            trip.locatedAt = Date()
        case .book(let book):
            book.currentLat = here.latitude
            book.currentLon = here.longitude
            book.locatedAt = Date()
        }
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if let target {
                    content(for: target)
                } else {
                    ContentUnavailableView {
                        Label("Nothing to fill yet", systemImage: "car")
                    } description: {
                        Text("A trip is one drive with a route and a finish. A book you just keep adding to.")
                    } actions: {
                        VStack(spacing: 8) {
                            Button("Start a trip") { creatingTrip = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.route)
                            Button("Start a book") { creatingBook = true }
                        }
                    }
                }
            }
            // Above the grid but inside the tab. It clears itself on a timer, and a
            // tap anywhere dismisses it early — a fact card you cannot skip becomes
            // an obstacle the moment you have already read it.
            .overlay {
                if let party = celebrating {
                    ZStack {
                        if party.tier.flashesScreen {
                            RarityFlash(tier: party.tier).id(party.id)
                        }

                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { dismissCelebration() }

                        FindBanner(tier: party.tier,
                                   plateName: party.plate.name,
                                   fact: party.fact)
                            .id(party.id)
                            .padding(.horizontal, 22)
                            .allowsHitTesting(false)
                    }
                    .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            // Siri's way in. The intent cannot present a sheet from outside the view
            // hierarchy, so it raises a flag and this is what watches for it —
            // including the case where the app was already open and forward, which
            // `onAppear` alone would miss.
            .onChange(of: handoff.wantsVoiceMode) { _, wants in
                guard wants else { return }
                handoff.wantsVoiceMode = false
                listening = true
            }
            .onAppear {
                if handoff.wantsVoiceMode {
                    handoff.wantsVoiceMode = false
                    listening = true
                }
                // Nothing else opens the microphone. Launching the app by tapping its
                // icon is indistinguishable from launching it by saying "open Plates"
                // — no intent runs in either case — so an auto-start keyed on launch
                // would open the microphone every time the app is opened at all. The
                // Siri phrase below is the route that can actually tell the difference.
            }
            .sheet(isPresented: $listening) {
                if let collection {
                    VoiceModeScreen(collection: collection, players: players)
                }
            }
            .onAppear(perform: beginTracking)
            .onDisappear { location.stop() }
            .onChange(of: location.updatedAt) { _, _ in persistLocation() }
            .onChange(of: collection?.id) { _, _ in beginTracking() }
            // Warmed here rather than at launch: this is the screen where taps
            // happen, so the engine is armed when it is about to be used and not
            // several seconds before anything can possibly fire.
            .onAppear(perform: Haptics.warmUp)
            #if DEBUG
            // Screenshot hooks. Nothing here can be reached without a launch
            // argument, and the whole block compiles out of Release.
            //
            //   -search NEW      open the bar pre-filled
            //   -popup who       the "who spotted it" prompt
            //   -popup switch    the trip / book switcher
            //   -celebrate CA    fire a confetti burst on that plate
            //   -filter left     only what's left
            //   -filter states   states set only
            //   -filter panel    open the filter panel
            //   -filter done     hide found with everything found
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-filter"), i + 1 < args.count {
                    switch args[i + 1] {
                    case "left":   filter = .init(hideFound: true, sets: Set(PlateRegion.allCases))
                    case "states": filter = .init(hideFound: false, sets: [.state])
                    // Pair with -foundAll, or there is always something left.
                    case "done":   filter = .init(hideFound: true, sets: [.state])
                    case "panel":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let collection { showFilter(for: collection) }
                        }
                    default: break
                    }
                }
                if let i = args.firstIndex(of: "-search"), i + 1 < args.count {
                    query = args[i + 1]
                    searchOpen = true
                }
                if let i = args.firstIndex(of: "-celebrate"), i + 1 < args.count,
                   let plate = Plate.plate(for: args[i + 1]) {
                    // Re-fires on a loop: a one-shot is nearly impossible to catch
                    // in a screenshot.
                    Timer.scheduledTimer(withTimeInterval: 7.5, repeats: true) { _ in
                        Task { @MainActor in celebrate(plate, in: collection) }
                    }.fire()
                }
                if let i = args.firstIndex(of: "-popup"), i + 1 < args.count {
                    let kind = args[i + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        switch kind {
                        case "who":
                            if let plate = Plate.plate(for: "NJ") { askWhoSpotted(plate) }
                        case "trips", "switch":
                            if let target { showSwitcher(current: target) }
                        default: break
                        }
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $addingPlayer) {
            PlayerEditor(player: nil,
                         usedColors: Set(players.map(\.colorIndex)),
                         onDelete: nil)
        }
        .sheet(isPresented: $creatingTrip) {
            TripEditor(trip: nil, onClear: nil, onDelete: nil)
        }
        .sheet(isPresented: $creatingBook) {
            BookEditor(book: nil, onClear: nil, onDelete: nil)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for target: PlayTarget) -> some View {
        let collection = target.collection

        VStack(spacing: 0) {
            PlateSearchBar(query: $query,
                           isOpen: $searchOpen,
                           matchCount: PlateSearch.matchCount(query: query)) {
                HStack(spacing: 10) {
                    // Left of the filter, because it is the one control here you
                    // reach for while moving. Rides in the search bar's accessory
                    // slot so it gets out of the way when the field opens.
                    Button {
                        listening = true
                        Haptics.selection()
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.route)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Theme.surface)
                                .shadow(color: Theme.ink.opacity(0.10), radius: 6, y: 2))
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voice mode")
                    .accessibilityHint("Listens and logs plates as you say them")

                    PlateFilterChip(filter: filter,
                                    leftCount: leftCount(in: collection)) {
                        showFilter(for: collection)
                    }
                }
            }
            #if DEBUG
            .onAppear {
                guard !Self.launchSearch.isEmpty, query.isEmpty else { return }
                searchOpen = true
                query = Self.launchSearch
            }
            #endif

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Always tappable, even with one trip — the switcher is
                        // also where you start a new trip or book.
                        switch target {
                        case .trip(let trip):
                            TripCard(trip: trip, onSwitch: { showSwitcher(current: target) })
                        case .book(let book):
                            BookCard(book: book, onSwitch: { showSwitcher(current: target) })
                        }

                        if let state = trackingState {
                            TrackingHintCard(state: state,
                                             isBook: target.isBook) {
                                location.requestAccess()
                            }
                            .padding(.top, 12)
                        }

                        if players.count > 1 {
                            PlayerStrip(standings: collection.standings(among: players))
                                .padding(.top, 12)
                        } else {
                            // Solo still needs a way in, or local multiplayer is
                            // invisible to anyone who never opens the Players tab.
                            Button { addingPlayer = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Playing with others? Add players")
                                        .font(.plates(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Theme.route)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Theme.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(Theme.line, lineWidth: 1))
                                )
                            }
                            .padding(.top, 12)
                        }

                        // A section renders exactly when it has tiles to draw, which
                        // covers both reasons it might not: its set is switched off,
                        // or everything in it is found and hidden.
                        //
                        // The "N / M found" detail never follows the filter, though —
                        // the denominator is a fact about the catalog, so hiding tiles
                        // must not appear to move the goal.
                        let shown = filter.standingDown(while: PlateSearch.isActive(query))
                        let states = shown.visible(Plate.states, isFound: collection.hasSeen)
                        let bonus = shown.visible(Plate.bonus, isFound: collection.hasSeen)
                        let provinces = shown.visible(Plate.provinces, isFound: collection.hasSeen)

                        if !states.isEmpty {
                            section(
                                title: "States",
                                detail: "\(collection.statesFound) / \(Plate.stateTotal) found",
                                plates: states,
                                in: collection
                            )
                            .padding(.top, 18)
                        }

                        // D.C. and Puerto Rico are one section on screen but two sets
                        // in the filter, so this carries whichever of them is on.
                        if !bonus.isEmpty {
                            section(
                                title: "Bonus plates",
                                detail: "\(collection.bonusFound) / \(Plate.bonus.count) found",
                                plates: bonus,
                                in: collection
                            )
                            .padding(.top, 22)
                        }

                        if !provinces.isEmpty {
                            canadaSection(provinces, in: collection)
                                .padding(.top, 22)
                        }

                        if states.isEmpty && bonus.isEmpty && provinces.isEmpty {
                            nothingLeftCard()
                                .padding(.top, 44)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .onChange(of: query) { _, q in
                    guard let hit = PlateSearch.firstMatch(query: q),
                          !q.trimmingCharacters(in: .whitespaces).isEmpty else { return }

                    // A province match is useless if the section is shut — but the
                    // province tiles do not exist in the hierarchy until it has
                    // expanded, so scrolling in the same frame is a silent no-op.
                    // Expand first, then scroll once the tiles are laid out.
                    if hit.region == .province, !canadaExpanded {
                        withAnimation(.snappy(duration: 0.25)) { canadaExpanded = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            withAnimation(.snappy(duration: 0.3)) {
                                proxy.scrollTo(hit.code, anchor: .center)
                            }
                        }
                    } else {
                        withAnimation(.snappy(duration: 0.3)) {
                            proxy.scrollTo(hit.code, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func section(title: String, detail: String,
                         plates: [Plate], in collection: any PlateCollection) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: title, detail: detail)
            grid(plates: plates, in: collection)
        }
    }

    /// Canada stays its own collapsible section rather than folding into the main
    /// list — it is a different country, and 13 provinces would otherwise bury the
    /// states you are actually hunting.
    private func canadaSection(_ provinces: [Plate],
                               in collection: any PlateCollection) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { canadaExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Canada")
                        .font(.plates(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkMuted)
                        .rotationEffect(.degrees(canadaExpanded ? 90 : 0))
                    Spacer()
                    Text("\(collection.provincesFound) / \(Plate.provinces.count) found")
                        .font(.plates(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canadaExpanded {
                // Fade only — a move from the top edge draws the grid over the
                // section header for the length of the animation.
                grid(plates: provinces, in: collection)
                    .transition(.opacity)
            }
        }
    }

    /// What the grid becomes when the filter leaves nothing.
    ///
    /// Reachable two ways, and it matters which: you have genuinely found every plate
    /// in the sets you are hunting, or you have narrowed things until only found
    /// plates remain. Either way the way out is the same button, because an empty
    /// screen with no action on it is a dead end.
    private func nothingLeftCard() -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.found)

            VStack(spacing: 5) {
                Text("Nothing left to find")
                    .font(.plates(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Every plate in the sets you are hunting is already found.")
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }

            Button("Show everything") {
                filter = PlateFilter()
                Haptics.selection()
            }
            .font(.plates(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(Theme.route))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private func grid(plates: [Plate], in collection: any PlateCollection) -> some View {
        // One pass over the sightings for the whole grid. Asking the collection
        // per tile was three linear scans each, so a full grid was O(plates x
        // sightings) and got slower the more you had spotted.
        let index = collection.plateIndex()
        let unlimited = collection.scoringMode == .unlimited

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.tileMinWidth,
                                         maximum: Theme.tileMaxWidth),
                               spacing: Theme.gridGap)],
            spacing: Theme.gridGap
        ) {
            let searching = PlateSearch.isActive(query)
            ForEach(plates) { plate in
                let found = index.has(plate.code)
                let hit = PlateSearch.matches(plate, query: query)
                Button {
                    tap(plate, in: collection)
                } label: {
                    let spotter = players.count > 1 && found ? index.spotter(plate.code) : nil
                    PlateTile(
                        plate: plate,
                        isFound: found,
                        spotterColor: spotter.map { Theme.playerColor($0.colorIndex) },
                        spotterInitial: spotter?.initial,
                        repeatCount: index.count(plate.code),
                        showsRepeats: unlimited,
                        rarity: rarities[plate.code],
                        showsProgressDot: true
                    )
                }
                .buttonStyle(TileButtonStyle())
                // Confetti is layered on rather than built into PlateTile so the
                // tile stays a pure presentation view. It draws outside its frame
                // on purpose, which is why the celebrating tile takes the top
                // zIndex below.
                .overlay {
                    if let party = celebrating, party.plate.code == plate.code {
                        ConfettiBurst(tier: party.tier).id(party.id)
                    }
                }
                // A highlight behind the tile, not on it — dimming the others is
                // not enough on its own, because an unfound plate is white and
                // stays white however faint its neighbours get.
                .background(
                    // kept narrower than the 8pt grid gap, otherwise neighbouring
                    // matches bleed into one another and read as a single blob
                    RoundedRectangle(cornerRadius: Theme.tileRadius + 3, style: .continuous)
                        .fill(Theme.paint.opacity(searching && hit ? 0.30 : 0))
                        .shadow(color: Theme.paint.opacity(searching && hit ? 0.45 : 0),
                                radius: 4)
                        .padding(-3)
                )
                .scaleEffect(searching && hit ? 1.05 : 1)
                .zIndex(celebrating?.plate.code == plate.code ? 2 : (searching && hit ? 1 : 0))
                .id(plate.code)
                // Non-matches fade back rather than disappearing, so the grid
                // never reflows under your thumb mid-search.
                .opacity(hit ? 1 : 0.18)
                .saturation(hit ? 1 : 0.2)
                .animation(.snappy(duration: 0.22), value: hit)
                .animation(.snappy(duration: 0.22), value: searching)
            }
        }
    }

    // MARK: - Filtering

    /// Unfound plates across the sets currently switched on — what the chip reports.
    private func leftCount(in collection: any PlateCollection) -> Int {
        let index = collection.plateIndex()
        return filter.sets.reduce(0) { total, region in
            total + region.plates.filter { !index.has($0.code) }.count
        }
    }

    private func showFilter(for collection: any PlateCollection) {
        popup.present("Show", message: "Choose what the grid draws.") {
            // `leftInRegion` is a closure rather than a snapshot so the per-set counts
            // stay live while the panel is open — collecting via Siri or a repeat tap
            // behind the popup should not leave stale numbers on screen. Indexing
            // inside the closure keeps that liveness and still costs one pass per
            // call rather than one per plate.
            PlateFilterPanel(
                leftInRegion: { region in
                    let index = collection.plateIndex()
                    return region.plates.filter { !index.has($0.code) }.count
                },
                onDone: { popup.dismiss() }
            )
        }
    }

    // MARK: - Actions

    private func tap(_ plate: Plate, in collection: any PlateCollection) {
        // Unlimited counts every sighting, so a tap always adds. The other modes
        // toggle, which is how you undo a mistake.
        if collection.scoringMode != .unlimited, collection.hasSeen(plate) {
            clear(plate, in: collection)
            return
        }
        if players.count > 1 {
            askWhoSpotted(plate)
        } else {
            record(plate, by: players.first)
        }
    }

    private func askWhoSpotted(_ plate: Plate) {
        popup.present("Who spotted \(plate.name)?", message: plate.code) {
            ForEach(players) { player in
                PopupChoice(title: player.name,
                            dotColor: Theme.playerColor(player.colorIndex),
                            dotInitial: player.initial) {
                    record(plate, by: player)
                    popup.dismiss()
                }
            }
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    private func record(_ plate: Plate, by player: Player?) {
        guard let collection else { return }

        let outcome = PlateLogger.record(plate, in: collection, by: player,
                                         at: location.coordinate, context: context)

        guard outcome.isFirstFind else {
            Haptics.repeatSighting()
            return
        }

        celebrate(plate, in: collection)

        // Completing all fifty outranks whatever the plate itself was worth.
        if plate.region == .state, collection.statesFound == Plate.stateTotal {
            Haptics.milestone()
        }
    }

    private func celebrate(_ plate: Plate, in collection: (any PlateCollection)?) {
        let tier = RarityTier.forRarity(PlateRarity.rarity(plate.code, on: collection?.route))
        let party = Celebration(plate: plate,
                                tier: tier,
                                fact: FactBook.fact(for: plate.code))
        withAnimation(.snappy(duration: 0.2)) { celebrating = party }
        tier.playHaptic()

        // The screen owns the card's lifetime rather than the card owning its own,
        // so that the timer and the tap-to-dismiss cannot disagree about whether it
        // is still up. Guarded by the id in case another find has replaced it.
        let dwell = FindBanner.dwell(fact: party.fact)
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) {
            if celebrating?.id == party.id { dismissCelebration() }
        }
    }

    private func dismissCelebration() {
        withAnimation(.easeIn(duration: 0.28)) { celebrating = nil }
    }

    private func clear(_ plate: Plate, in collection: any PlateCollection) {
        // Collected before the delete, because afterwards there is nothing left to
        // ask which sightings went — and a party has to name them individually so a
        // peer that never heard of them can still record that they are gone.
        var withdrawn: [UUID] = []
        for sighting in collection.allSightings where sighting.plateCode == plate.code {
            withdrawn.append(sighting.id)
            context.delete(sighting)
        }
        try? context.save()
        if let trip = collection as? Trip {
            PartySession.shared?.broadcastRemoval(withdrawn, in: trip.id)
        }
        Haptics.undo()
    }

    /// One switcher for both kinds, because from the grid's point of view they are
    /// the same choice: what am I filling in right now.
    private func showSwitcher(current: PlayTarget) {
        // Only trips that will actually take a plate. A finished one listed here
        // would be a dead end: picking it puts you on a grid that cannot record
        // anything. They are still on the Trips screen and still on the Trail.
        // Pinned first, then newest. Almost every switch is back to something used
        // in the last few days, so only the first few are shown and the rest sit
        // behind "Show all" — see `PopupPicker.Group.collapseTo`.
        let openTrips = trips.collectable.pinnedFirst
        let groups = [
            PopupPicker.Group(
                title: openTrips.isEmpty ? nil : "TRIPS",
                entries: openTrips.map { candidate in
                    PopupPicker.Entry(
                        id: candidate.id,
                        title: candidate.name,
                        subtitle: candidate.routeLabel
                            ?? "\(candidate.platesFound) plate\(candidate.platesFound == 1 ? "" : "s") found",
                        count: candidate.statesFound,
                        isSelected: !current.isBook && candidate.id == current.id,
                        // So typing where you are going finds the trip that goes
                        // there, even when the name says nothing about it.
                        keywords: [candidate.origin, candidate.destination]
                            .compactMap { $0 }.joined(separator: " "),
                        action: { choose(.trip(candidate)) }
                    )
                },
                collapseTo: 4),
            PopupPicker.Group(
                title: books.isEmpty ? nil : "BOOKS",
                entries: books.map { candidate in
                    PopupPicker.Entry(
                        id: candidate.id,
                        title: candidate.name,
                        subtitle: candidate.sinceLabel,
                        count: candidate.statesFound,
                        isSelected: current.isBook && candidate.id == current.id,
                        action: { choose(.book(candidate)) }
                    )
                },
                // Books are not collapsed. People keep one or two of them for years,
                // where trips accumulate — the problem this solves is not there.
                collapseTo: nil)
        ].filter { !$0.entries.isEmpty }

        popup.present("What are you filling?",
                      message: "Plates are saved against whichever of these is picked.") {
            PopupPicker(groups: groups)

            PopupButton(title: "New trip", kind: .primary) {
                popup.dismiss()
                creatingTrip = true
            }
            PopupButton(title: "New book") {
                popup.dismiss()
                creatingBook = true
            }
        }
    }

    private func choose(_ target: PlayTarget) {
        PlaySelection.select(target)
        Haptics.selection()
        popup.dismiss()
    }
}

/// A press effect that matches the mockup — scale only, no opacity dip, so the
/// plate never looks faded.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.13), value: configuration.isPressed)
    }
}
