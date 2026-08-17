import SwiftUI
import SwiftData

struct GameScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup
    @Environment(CoachPresenter.self) private var coach

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]

    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    @AppStorage(PlateFilter.key) private var filter = PlateFilter()
    /// See `TrackingHints`. A joined string rather than a set, so the view redraws
    /// the moment a card is dismissed.
    @AppStorage(TrackingHints.storeKey) private var dismissedHints = ""

    private let location = TripLocation.shared
    private let handoff = VoiceHandoff.shared

    @Environment(TourGuide.self) private var tour

    @State private var canadaExpanded = false
    @State private var query = ""
    @State private var searchOpen = false

    #if DEBUG
    /// `-search cactus` opens the grid with a search already running. The field
    /// needs a keyboard to reach otherwise, and the appearance matching this
    /// exercises is the whole reason the field stopped forcing capitals.
    private static var launchSearch: String {
        // The one place the "-" rule is applied, because a search term that looks
        // like a flag is far more likely to be the next flag. See `LaunchFlags.value`.
        guard let term = LaunchFlags.value(after: "-search"),
              !term.hasPrefix("-") else { return "" }
        return term
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
    @State private var namingMe = false
    /// Whether the "who's playing?" sheet has already had its turn this launch.
    ///
    /// The ask used to hang off `onAppear` alone, and `onAppear` fires every time
    /// this tab comes back — so cancelling the sheet and tapping Books bought you
    /// about four seconds of peace. A question you decline should stay declined
    /// until you have at least left and come back to the app.
    @State private var askedWhoIsPlaying = false
    @State private var notice: Notice?
    @State private var creatingTrip = false
    @State private var creatingBook = false

    /// The find currently being celebrated. The id restarts the animation even when
    /// the same plate is found twice in a row.
    @State private var celebrating: Celebration?
    /// When the un-check menu last opened. The long-press fires while the finger is
    /// still down, and the Button underneath fires when it lifts — so without a
    /// window the same press both opens the menu and logs another sighting, which
    /// is the exact mistake the menu exists to undo.
    /// The lift at the end of a long press that opened the un-check menu, waiting
    /// to be swallowed by the tap it would otherwise become.
    ///
    /// A one-shot rather than a window. It was a `Date` compared against 0.8s, and
    /// measured from when the menu *opened* — so a hold of more than about 1.25s
    /// fell outside it and logged a second sighting at the exact moment the user was
    /// being asked whether to take one away. It was also stamped before the
    /// ownership check, so a long press on somebody else's plate opened nothing and
    /// still ate the next tap anywhere on the grid.
    @State private var pressToSwallow: Date?

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

    /// Who is on *this* trip or book — not everyone the store has ever heard of.
    /// See `PlateCollection.participants`, which exists because the difference was
    /// a bug: every new trip opened showing everybody from every past party, at
    /// zero.
    private var participants: [Player] {
        guard let collection else { return [] }
        return collection.participants(
            from: players,
            me: DevicePlayer.resolve(from: players),
            alsoPlaying: PartySession.roster(for: collection.id))
    }

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
    /// it was claimed, and that is the number the found tile's pip is colored by.
    private func rarities(using index: PlateIndex) -> [String: Int] {
        guard let collection else { return [:] }
        // Was `?? [:]` with no route, which left every unbanked plate to fall through
        // to `Plate.points` at the tile — a scale that stops at 10, so nothing could
        // ever come out mythic. See `PlateRarity.table(on:)`.
        var table = PlateRarity.table(on: collection.route)
        for code in collection.seenCodes {
            if let claimed = index.banked(code) { table[code] = claimed }
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
        guard let state = trackingNeed else { return nil }
        guard !TrackingHints.isDismissed(state, collection: collection?.id,
                                         in: dismissedHints) else { return nil }
        return state
    }

    /// What is actually missing, before asking whether anybody wants to hear about
    /// it. Split from `trackingState` so the dismissal check has one place to live
    /// and cannot be forgotten by a fifth case added below.
    private var trackingNeed: TrackingHintCard.State? {
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

    private func dismissTrackingHint(_ state: TrackingHintCard.State) {
        guard let next = TrackingHints.adding(state, collection: collection?.id,
                                              to: dismissedHints) else { return }
        dismissedHints = next
        Haptics.undo()
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
                // Warm the road for the rarity model, which cannot ask for it itself:
                // it runs inside a render and only reads what is already cached. Until
                // something fetches it, the trip is scored against the straight line
                // between the pins, which cuts every corner the road takes. See
                // `PlateRarity.Route.path` for what that costs.
                //
                // Nothing here uses the result. It lands in `RouteCache`, and the next
                // time the grid renders, `Trip.route` finds it there.
                Task { _ = await RouteCache.shared.directions(from: origin, to: destination) }
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

    // The screen is assembled in three pieces rather than one chain: what is on
    // it (`screen`), what it listens to (`wired`), and what it presents (here).
    // Not a style choice — as one expression this hit the type-checker's ceiling
    // and stopped compiling. Anything long added below belongs in a piece, not in
    // the chain.
    var body: some View {
        NavigationStack {
            wired(screen)
        }
        .sheet(isPresented: $namingMe) {
            IdentityPrompt(saveLabel: "Start")
        }
        .sheet(isPresented: $creatingTrip) {
            TripEditor(trip: nil, onClear: nil, onDelete: nil)
        }
        .sheet(isPresented: $creatingBook) {
            BookEditor(book: nil, onClear: nil, onDelete: nil)
        }
        // Last in the chain, so the balloon draws over the grid and under the tab
        // bar. The copy sits here rather than in a table elsewhere: whoever changes
        // what the tip says is the person looking at the screen it appears on.
        .coachLayer(Self.coachCopy)
        .tourLayer(.game, Self.tourCopy)
        .onAppear { tour.offer(.game, stops: tourStops) }
        .onDisappear { tour.left(.game) }
    }

    /// Which stops this screen can host, in the order they sit on it.
    ///
    /// The fork is a different screen wearing the same tab, and it has exactly one
    /// thing to say. Offering the other four would be pointing at a search field, a
    /// filter and a grid that are not drawn.
    private var tourStops: [Tour.Stop] {
        guard target != nil else { return [.gameTarget] }
        // Voice and the filter ride in the fixed header above the scroll view, so
        // they cost no scrolling wherever they fall in the route. The grid goes last
        // on purpose: tapping a plate is the whole game, and it is the sentence
        // somebody should still have in their head when the scrim lifts.
        return [.gameTarget, .gameVoice, .gameFilter, .gameParty, .gameGrid]
    }

    private static let tourCopy: [Tour.Stop: LocalizedStringResource] = [
        .gameTarget: "This is what you are filling right now. Tap it to switch between a trip and a book, or to start another one.",
        .gameVoice: "Driving, or hands full of snacks? Tap this and just say the states out loud as you see them.",
        .gameFilter: "Hide the ones you have already found, or turn whole sets off. Canada and the bonus plates live in here.",
        .gameParty: "Everyone in the car keeps their own phone. Start a Party and every plate anybody spots lands in the same score.",
        .gameGrid: "And that is the game. See one on the road, tap its plate. The rarer it is where you're heading, the more it is worth."
    ]

    /// The grid, or the fork that offers to make something to fill.
    private var screen: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            if let target {
                content(for: target)
            } else {
                emptyState
            }
        }
        .overlay { celebration }
        // Somebody else's find. Deliberately a line at the top rather than the
        // full card treatment — see `PartySession.PeerFind`.
        .overlay(alignment: .top) { peerNotice }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to fill yet", systemImage: "car")
        } description: {
            // Two whole sentences rather than one plus a conditional
            // fragment. A `LocalizedStringKey` has to be a single literal
            // to be harvested into the catalog, so a line assembled from
            // parts is a line no translator ever sees.
            //
            // The extra sentence is for the first launch only: somebody
            // who has been here before knows they can have both, and by
            // then the choice is a choice rather than a fork in a
            // tutorial.
            if Coach.seen(.fork) {
                Text("A trip is one drive with a route and a finish. A book you just keep adding to.")
            } else {
                Text("A trip is one drive with a route and a finish. A book you just keep adding to. Pick one to start collecting. You can have both later.")
            }
        } actions: {
            VStack(spacing: 8) {
                Button("Start a trip") { creatingTrip = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.route)
                Button("Start a book") { creatingBook = true }
            }
            .tourAnchor(.gameTarget, prefersAbove: true)
        }
    }

    /// Above the grid but inside the tab. It clears itself on a timer, and a tap
    /// anywhere dismisses it early — a fact card you cannot skip becomes an
    /// obstacle the moment you have already read it.
    @ViewBuilder
    private var celebration: some View {
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

    @ViewBuilder
    private var peerNotice: some View {
        if let notice {
            NoticeToast(text: notice.text, tint: notice.tint)
                .id(notice.id)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Wiring

    /// Everything the screen listens to: arrivals from a peer, Siri, the location
    /// feed, and the coach.
    private func wired(_ view: some View) -> some View {
        view
            .onChange(of: PartySession.shared?.latestFromPeer) { _, arrival in
                guard let arrival else { return }
                notice = Notice(text: "\(arrival.finder) found \(arrival.plateName)",
                                tint: arrival.tier.color)
            }
            .onChange(of: notice?.id) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    guard notice?.id == id else { return }
                    withAnimation(.easeIn(duration: 0.3)) { notice = nil }
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
            .onChange(of: collection?.id) { _, _ in
                beginTracking()
                // The other half of the ask's trigger. On a fresh install there is
                // nothing to fill when this screen first appears, so the question
                // waits here for a trip or a book to exist.
                introduceThisPhoneOnce()
                offerGridTips()
                // Something exists to fill, so the fork has been used and its extra
                // line has done its job. Marked here rather than while the empty
                // state is on screen, which would delete the sentence out from under
                // somebody mid-read.
                if collection != nil { Coach.markSeen(.fork) }
            }
            // Warmed here rather than at launch: this is the screen where taps
            // happen, so the engine is armed when it is about to be used and not
            // several seconds before anything can possibly fire.
            .onAppear(perform: Haptics.warmUp)
            .onAppear(perform: introduceThisPhoneOnce)
            .onAppear(perform: offerGridTips)
            // A party joining, or a shared book delivering, changes the roster
            // under a screen nobody has left. That is the whole occasion for the
            // spotter tip, and no other trigger on this screen would notice it.
            .onChange(of: participants.count) { _, _ in offerGridTips() }
            // Leaving counts as shown. See `CoachPresenter.withdraw`.
            .onDisappear(perform: withdrawGridTips)
            #if DEBUG
            .onAppear(perform: applyLaunchArguments)
            #endif
    }

    #if DEBUG
    /// Screenshot hooks. Nothing here can be reached without a launch argument,
    /// and the whole thing compiles out of Release.
    ///
    ///   -search NEW      open the bar pre-filled
    ///   -popup switch    the trip / book switcher
    ///   -celebrate CA    fire a confetti burst on that plate
    ///   -filter left     only what's left
    ///   -filter states   states set only
    ///   -filter bonus    D.C. and Puerto Rico only
    ///   -filter panel    open the filter panel
    ///   -filter done     hide found with everything found
    private func applyLaunchArguments() {
        if let named = LaunchFlags.value(after: "-filter") {
            switch named {
            case "left":   filter = .init(hideFound: true, sets: Set(PlateRegion.allCases))
            case "states": filter = .init(hideFound: false, sets: [.state])
            // The Bonus section on its own, which is otherwise fifty tiles down.
            case "bonus":  filter = .init(hideFound: false, sets: [.federal, .territory])
            // Two sets, so the chip has to pluralise. The only spot where
            // automatic grammar agreement shows up somewhere a screenshot
            // can see it without first opening a popup.
            case "sets":   filter = .init(hideFound: false, sets: [.state, .province])
            // Pair with -foundAll, or there is always something left.
            case "done":   filter = .init(hideFound: true, sets: [.state])
            case "panel":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let collection { showFilter(for: collection) }
                }
            default: break
            }
        }
        if let term = LaunchFlags.value(after: "-search") {
            query = term
            searchOpen = true
        }
        // `-uncheck NJ` opens the removal menu on that plate — the menu is
        // behind a long-press, which no launch argument can perform.
        if let plate = LaunchFlags.value(after: "-uncheck").flatMap(Plate.plate(for:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let collection { uncheck(plate, in: collection) }
            }
        }
        // `-tapPlate NJ` taps that tile through the real handler, which is
        // the only way to reach the "remove this?" confirmation without a
        // finger. Deliberately `tap` and not `tapFound`, so the launch
        // argument goes through the same branch a tap does.
        if let plate = LaunchFlags.value(after: "-tapPlate")
            .flatMap({ Plate.plate(for: $0.uppercased()) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let collection { tap(plate, in: collection) }
            }
        }
        if let plate = LaunchFlags.value(after: "-celebrate").flatMap(Plate.plate(for:)) {
            // Re-fires on a loop: a one-shot is nearly impossible to catch
            // in a screenshot.
            Timer.scheduledTimer(withTimeInterval: 7.5, repeats: true) { _ in
                Task { @MainActor in celebrate(plate, in: collection) }
            }.fire()
        }
        if let kind = LaunchFlags.value(after: "-popup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                switch kind {
                case "trips", "switch":
                    if let target { showSwitcher(current: target) }
                default: break
                }
            }
        }
    }
    #endif

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
                    .tourAnchor(.gameVoice)

                    PlateFilterChip(filter: filter,
                                    leftCount: leftCount(in: collection)) {
                        showFilter(for: collection)
                    }
                    .tourAnchor(.gameFilter)
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
                        // Always tappable, even with one trip: it is how you move
                        // between the trip you are on and a book, which is not
                        // obvious from a card that looks like a heading.
                        Group {
                            switch target {
                            case .trip(let trip):
                                TripCard(trip: trip, onSwitch: { showSwitcher(current: target) })
                            case .book(let book):
                                BookCard(book: book, onSwitch: { showSwitcher(current: target) })
                            }
                        }
                        .tourAnchor(.gameTarget)
                        .tourStop(.gameTarget)

                        if let state = trackingState {
                            TrackingHintCard(state: state,
                                             isBook: target.isBook,
                                             onAllow: { location.requestAccess() },
                                             onDismiss: { dismissTrackingHint(state) })
                            .padding(.top, 12)
                        }

                        if participants.count > 1 {
                            PlayerStrip(standings: collection.standings(among: participants))
                                .padding(.top, 12)
                                .tourAnchor(.gameParty)
                                .tourStop(.gameParty)
                        } else {
                            // Solo still needs a way in, or the party is invisible to
                            // anyone who never opens the More tab. It used to offer to
                            // add a player *to this phone*; the answer to "playing with
                            // others?" is now that they bring their own.
                            NavigationLink { PartyScreen() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Playing with others? Start a Party")
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
                            .tourAnchor(.gameParty)
                            .tourStop(.gameParty)
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
                                in: collection,
                                hostsCoachMarks: true
                            )
                            .padding(.top, 18)
                            .tourStop(.gameGrid)
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
                .tourScrolling(proxy)
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

    private func section(title: LocalizedStringKey, detail: LocalizedStringKey,
                         plates: [Plate], in collection: any PlateCollection,
                         hostsCoachMarks: Bool = false) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: title, detail: detail)
            grid(plates: plates, in: collection, hostsCoachMarks: hostsCoachMarks)
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
                Text("You have found every plate you are hunting for.")
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

    /// The first tile actually wearing somebody else's color.
    ///
    /// Not merely the first found tile: the corner chip only appears on a plate
    /// somebody else called, so anchoring anywhere else would be describing a mark
    /// that is not on the thing being pointed at.
    private func firstSpottedByAnother(among plates: [Plate],
                                       using index: PlateIndex) -> String? {
        guard participants.count > 1 else { return nil }
        let mine = DevicePlayer.resolve(from: players)?.id
        for plate in plates where index.has(plate.code) {
            if let who = index.spotter(plate.code), who.id != mine { return plate.code }
        }
        return nil
    }

    /// `hostsCoachMarks` is set by exactly one caller — the states section — and this
    /// is not decoration. Every section draws through this same function, so without
    /// it all three register the same anchors. The key's reduce keeps the first,
    /// which looks correct right up until Alabama recycles out of the lazy grid: its
    /// anchor disappears, the bonus grid's is the only one left, and the balloon
    /// silently relocates to Washington D.C. halfway down the page.
    private func grid(plates: [Plate], in collection: any PlateCollection,
                      hostsCoachMarks: Bool = false) -> some View {
        // One pass over the sightings for the whole grid. Asking the collection
        // per tile was three linear scans each, so a full grid was O(plates x
        // sightings) and got slower the more you had spotted.
        let index = collection.plateIndex()
        // Built for the whole grid off the same index, for the same reason the index
        // itself is. This was a computed property read inside the tile builder, so the
        // entire table was rebuilt once per tile — sixty-five times a grid — and each
        // rebuild walked `seenCodes` calling `claimedRarity`, which filters every
        // sighting the collection has. Through the index it is a dictionary hit.
        let rarities = rarities(using: index)
        let unlimited = collection.scoringMode == .unlimited
        // What the "tap one" balloon points at. The first tile still to be found,
        // which on the grid this tip fires against is simply the first tile.
        let firstUnfound = hostsCoachMarks ? plates.first { !index.has($0.code) }?.code : nil
        // And what the long-press balloon points at: a plate that has actually been
        // counted, since the tip is about taking a count back. The two are mutually
        // exclusive by construction — `firstTap` needs an empty collection and this
        // one needs a non-empty one — so the grid never registers both.
        let firstCounted = hostsCoachMarks && unlimited
            ? plates.first { index.has($0.code) }?.code : nil
        // And what the "who called it" balloon points at. Computed outside the view
        // builder rather than inline: a third `let` with a closure in it was enough
        // to tip this function past what the type checker will attempt.
        let firstBySomebodyElse = hostsCoachMarks
            ? firstSpottedByAnother(among: plates, using: index) : nil

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
                    let shared = participants.count > 1 && found
                    let spotter = shared ? index.spotter(plate.code) : nil
                    PlateTile(
                        plate: plate,
                        isFound: found,
                        spotter: spotter,
                        claimants: shared ? index.claimants(plate.code) : [],
                        repeatCount: index.count(plate.code),
                        showsRepeats: unlimited,
                        rarity: rarities[plate.code],
                        showsProgressDot: true
                    )
                }
                .buttonStyle(TileButtonStyle())
                // The only way to un-count in unlimited mode, where a tap always
                // adds. Simultaneous rather than exclusive so it cannot delay the
                // ordinary tap, and a no-op in every other mode, where tapping the
                // tile again is already the undo.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        uncheck(plate, in: collection)
                    }
                )
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
                .coachAnchor(.firstTap, active: plate.code == firstUnfound)
                // Rides on the same "first still to find" tile the `firstTap` balloon
                // uses, and for the same reason: on a grid nobody has touched yet that
                // is simply the first tile, which is where the eye already is.
                .tourAnchor(.gameGrid, active: plate.code == firstUnfound)
                .coachAnchor(.uncheck, active: plate.code == firstCounted)
                .coachAnchor(.spotterChip, active: plate.code == firstBySomebodyElse)
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
        // Matches the panel's own VoiceOver hint word for word, so the same
        // control is not called two things.
        popup.present("Show", message: "Choose which plates to show.") {
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
        // The lift at the end of the long-press that just opened the un-check menu.
        // Not a sighting.
        if let opened = pressToSwallow {
            pressToSwallow = nil
            // Consumed once, and only for a lift that could plausibly belong to that
            // press — so a stale one cannot sit around eating a tap minutes later.
            if Date().timeIntervalSince(opened) < 5 { return }
        }

        // Unlimited counts every sighting, so a tap always adds. The other modes
        // toggle, which is how you undo a mistake. Unlimited's undo is a long-press
        // — see `uncheck`.
        if collection.scoringMode != .unlimited, collection.hasSeen(plate) {
            tapFound(plate, in: collection)
            return
        }
        // Always this phone's own player. The prompt that used to stand here — "who
        // spotted New Jersey?", listing everyone in the car — is gone with the
        // shared-device roster it belonged to: in a party the phone answers that
        // question by existing. See `DevicePlayer`.
        record(plate, by: DevicePlayer.resolve(from: players))
    }

    /// What a tap on an already-found plate means, which depends on the party.
    ///
    /// On one phone there was only one answer: you found it, so tapping again is
    /// undoing a mistake. With five phones the same tap can be three different
    /// things, and which one it is has to be the car's decision rather than ours.
    /// See `PartyRules`.
    private func tapFound(_ plate: Plate, in collection: any PlateCollection) {
        let me = DevicePlayer.resolve(from: players)
        let rules = PartySession.rules(for: collection.id)

        // Shared claims: somebody else got there first, and that no longer stops you
        // banking it too — at what it is worth from where *you* are sitting.
        if rules.sharedClaims, !collection.hasClaimed(plate.code, by: me) {
            record(plate, by: me)
            return
        }

        // Otherwise a tap is a take-back, and may not be yours to make.
        let mine = collection.removableSightings(of: plate.code, by: me,
                                                 protected: rules.protectsClaims)
        guard !mine.isEmpty else {
            // Spelled out rather than `who.map { … } ?? …`: a literal inside a
            // closure is not somewhere the compiler reliably looks for catalog
            // keys, and both of these are sentences somebody has to be able to
            // reword.
            let text: LocalizedStringKey
            if let who = collection.plateIndex().spotter(plate.code)?.name {
                text = "\(who) spotted that one."
            } else {
                text = "That one is not yours to take back."
            }
            notice = Notice(text: text, tint: Theme.inkMuted)
            Haptics.undo()
            return
        }
        askBeforeClearing(plate, in: collection, removing: mine)
    }

    /// Taking a plate off is the only thing on this grid that destroys anything.
    ///
    /// A tap adds a sighting and a second tap took it away again, instantly, which is
    /// a fine undo for the tap you meant to make and a bad one for the tap you did
    /// not. What goes with it is not just a tick: the date you first saw it, the
    /// rarity it was banked at, and where you were standing. None of that can be
    /// worked out again, and a book is a lifetime record where the first-seen date is
    /// most of the point.
    ///
    /// So the tap now asks. It costs one extra tap on a deliberate undo, which is the
    /// right way round: undoing is rare and losing a year-old find is permanent.
    /// Unlimited mode is unaffected — its removals already come through a long-press
    /// menu that asks, and a tap there means "seen another one".
    private func askBeforeClearing(_ plate: Plate,
                                   in collection: any PlateCollection,
                                   removing doomed: [Sighting]) {
        let first = collection.allSightings
            .filter { $0.plateCode == plate.code }
            .min { SightingOrder($0) < SightingOrder($1) }
        let since = first.map {
            $0.spottedAt.formatted(date: .abbreviated, time: .omitted)
        }

        let message: LocalizedStringKey
        if collection is Book, let since {
            message = "It has been in \(collection.name) since \(since). Removing it takes that date with it, and the app cannot work it out again."
        } else if let since {
            message = "Spotted \(since). Removing it takes back the points it scored."
        } else {
            message = "Removing it takes back the points it scored."
        }

        popup.present("Remove \(plate.name)?", message: message) {
            PopupButton(title: "Remove it", kind: .destructive) {
                clear(plate, in: collection, removing: doomed)
                popup.dismiss()
            }
            PopupButton(title: "Keep it") { popup.dismiss() }
        }
    }

    /// The undo unlimited mode otherwise lacks: long-press a counted plate to take
    /// sightings back.
    ///
    /// A popup rather than an instant removal, because a long-press is easy to make
    /// by accident while scrolling a grid — and because the count is the thing you
    /// need to see before deciding whether one sighting goes or all of them do.
    /// "Remove one" takes the most recent, which is the one the mistaken tap made.
    private func uncheck(_ plate: Plate, in collection: any PlateCollection) {
        guard collection.scoringMode == .unlimited, collection.hasSeen(plate) else { return }
        // Held a plate — which is the whole of what the tip was going to say.
        coach.dismiss(.uncheck)

        // The same ownership rules as a tap-to-clear: in a party with protected
        // claims, the sightings you can take back are your own.
        let me = DevicePlayer.resolve(from: players)
        let rules = PartySession.rules(for: collection.id)
        let mine = collection.removableSightings(of: plate.code, by: me,
                                                 protected: rules.protectsClaims)
        guard !mine.isEmpty else {
            // Spelled out rather than `who.map { … } ?? …`: a literal inside a
            // closure is not somewhere the compiler reliably looks for catalog
            // keys, and both of these are sentences somebody has to be able to
            // reword.
            let text: LocalizedStringKey
            if let who = collection.plateIndex().spotter(plate.code)?.name {
                text = "\(who) spotted that one."
            } else {
                text = "That one is not yours to take back."
            }
            notice = Notice(text: text, tint: Theme.inkMuted)
            Haptics.undo()
            return
        }

        let total = collection.sightingCount(for: plate)
        let message: LocalizedStringKey = mine.count == total
            ? "Counted ^[\(total) time](inflect: true). Removing takes back the most recent sighting and the points it scored."
            : "Counted \(total) times, \(mine.count) of them yours. You can only take back your own."

        // `verbatim:` — the title here is the plate's own name, which is data and
        // not one of the app's phrases. Passed as a key it would be looked up in
        // the catalog, and in another language a plate called "More" would come
        // back as the translation of the tab.
        // Armed here, where a menu is actually about to open. See `pressToSwallow`.
        pressToSwallow = Date()
        popup.present(verbatim: plate.name, message: message) {
            PopupButton(title: mine.count == 1 ? "Remove it" : "Remove one",
                        kind: .destructive) {
                if let latest = mine.max(by: { SightingOrder($0) < SightingOrder($1) }) {
                    clear(plate, in: collection, removing: [latest])
                }
                popup.dismiss()
            }
            if mine.count > 1 {
                PopupButton(title: "Remove all \(mine.count)", kind: .destructive) {
                    clear(plate, in: collection, removing: mine)
                    popup.dismiss()
                }
            }
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    private func record(_ plate: Plate, by player: Player?) {
        guard let collection else { return }

        // Doing the thing dismisses the tip about doing the thing — and the
        // celebration that follows is a far better explanation than the balloon was.
        // A no-op unless that balloon is actually up.
        coach.dismiss(.firstTap)

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

    /// Ask a phone that has never said who it is, at the first moment the answer
    /// could matter, and not again until it is relaunched.
    ///
    /// Anything with players already in the store had `markProfileSet` called at
    /// launch — those people chose their names months ago and asking again would be
    /// the app forgetting somebody it knows.
    ///
    /// Waiting for a collection is not politeness, it is what makes the answer
    /// trustworthy. A fresh install opens on the trip-or-book fork with an empty
    /// store, and asking a stranger their name over the top of the first choice the
    /// app has offered them is an ambush. More usefully, a *restored* install opens
    /// on that same empty fork because iCloud has not delivered anything yet — so
    /// holding the question until there is something to fill means it is asked at
    /// roughly the moment the rest of the account has landed, which is the difference
    /// between offering somebody their own name and inventing them a second one.
    /// `IdentityPrompt` is what does the offering.
    ///
    /// This used to also carry a one-time notice that the "who spotted it?" prompt
    /// had become the party, shown to installs with more than one player. It is gone:
    /// a popup explaining a prompt that no longer exists is itself the interruption it
    /// was apologising for, and it landed on people the moment they opened the screen
    /// they came to play on.
    /// Offer "tap one" to a grid that has never had a plate on it.
    ///
    /// The condition is the whole trigger: something to fill, and nothing filled in.
    /// It is a fact about state rather than a step in a sequence, which is why it can
    /// be called from two places and called repeatedly — `CoachPresenter.request`
    /// makes a redundant ask free. That also means it is right for somebody who
    /// starts a *second* collection a year in: an empty grid is an empty grid. The
    /// ledger, not the trigger, is what stops it happening twice.
    /// What this screen's three marks say.
    ///
    /// Beside the triggers that fire them rather than in a table in another file, so
    /// changing what a tip says never means editing two places. A stored property
    /// rather than a literal in the modifier chain for the same reason
    /// `offerGridTips` exists: three dictionary entries inline were enough to put
    /// `body` past what the type checker will attempt.
    private static let coachCopy: [Coach.Tip: LocalizedStringResource] = [
        .firstTap: "See one of these on the road? Tap it.",
        .uncheck: "Every tap counts again here. Hold a plate to take one back.",
        .spotterChip: "The colored corner is who called it."
    ]

    /// Ask on behalf of all three of this screen's marks, in the order they matter.
    ///
    /// One call site rather than three modifiers, which is not only tidiness: the
    /// body of this view is close enough to the type checker's ceiling that adding a
    /// third `.onAppear` to the chain was the change that pushed it over. Each ask is
    /// free when its trigger is false, so calling all three every time costs nothing.
    private func offerGridTips() {
        offerFirstTapTip()
        offerUncheckTip()
        offerSpotterTip()
    }

    private func withdrawGridTips() {
        coach.withdraw(.firstTap)
        coach.withdraw(.uncheck)
        coach.withdraw(.spotterChip)
    }

    private func offerFirstTapTip() {
        guard let collection else { return }
        coach.request(.firstTap, when: collection.allSightings.isEmpty)
    }

    /// The long press is the only gesture in the app with nothing on screen to
    /// suggest it, and it only exists in one scoring mode.
    ///
    /// Deliberately not offered the moment unlimited mode is chosen — offered after
    /// something has been counted. The tip is "take one back", and taking one back
    /// is meaningless until there is one. That is also the moment it starts
    /// mattering: the second tap on the same plate is when somebody first wonders
    /// whether they can undo the first.
    private func offerUncheckTip() {
        guard let collection, collection.scoringMode == .unlimited else { return }
        coach.request(.uncheck, when: !collection.allSightings.isEmpty)
    }

    /// The colored corner, explained the first time one is on screen.
    ///
    /// This is the only tip in the app about something that arrived rather than
    /// something you can do — a party landed, or a shared book synced, and suddenly
    /// tiles are wearing marks that were not there yesterday. There is no action to
    /// take and no "done" to reach, so it is spent by being shown and nothing else.
    ///
    /// Gated on a sighting by *somebody else*, not on the party being open. Your own
    /// chip needs no explaining, and in a two-person party the chips are invisible
    /// until the other person actually calls something.
    private func offerSpotterTip() {
        guard let collection, participants.count > 1 else { return }
        let me = DevicePlayer.resolve(from: players)
        coach.request(.spotterChip,
                      when: collection.allSightings.contains {
                          $0.player != nil && $0.player?.id != me?.id
                      })
    }

    private func introduceThisPhoneOnce() {
        guard !DevicePlayer.hasProfile, !askedWhoIsPlaying, collection != nil else { return }
        askedWhoIsPlaying = true
        // After the screen has settled, or it competes with the first render.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { namingMe = true }
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
        // The first find in an unlimited collection is the moment the long-press
        // tip becomes worth showing, and this is the moment that find is finished
        // being celebrated. Asked here rather than in `record` so the balloon
        // cannot arrive beside the find card — that card is not a popup, so
        // `CoachLayer` has no way to stand down under it.
        offerUncheckTip()
    }

    /// Takes back `doomed`, or everything of this plate when no list is given.
    ///
    /// The list exists because "un-tap this plate" and "delete every sighting of it"
    /// stopped being the same thing: under protected claims a tap takes back only
    /// your own, and under shared claims a plate can have four owners.
    private func clear(_ plate: Plate, in collection: any PlateCollection,
                       removing doomed: [Sighting]? = nil) {
        let going = doomed ?? collection.allSightings.filter { $0.plateCode == plate.code }
        PlateLogger.withdraw(going, from: collection, context: context)
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
                symbol: "suitcase.fill",
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
                symbol: "books.vertical.fill",
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

        // No "New trip" / "New book" here any more. This is the switch, and making
        // things belongs to the tabs that own them — a picker that also creates is
        // two controls wearing one coat, and it was the only place in the app where
        // a trip could be made without going to Trips. The cost is real for anybody
        // starting a drive from this screen, so both tabs keep a create button above
        // the fold as well as at the end of their list.
        popup.present("What are you filling?",
                      message: "Plates you tap go into whichever one you pick. Start new ones on the Trips and Books tabs.") {
            PopupPicker(groups: groups)
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

/// One line at the top of the grid, said once and quietly.
///
/// Two things use it and both are the same shape of message: somebody else called a
/// plate, or a tap did not do what it usually does. Neither earns the find card —
/// one belongs to whoever spotted it, and the other is a refusal, which should be
/// the smallest possible interruption to a car full of people looking out of the
/// window.
///
/// The color arrives as a dot rather than a word, because the interesting thing
/// about somebody else's plate is that it happened, not what it scored.
private struct NoticeToast: View {
    let text: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.plates(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.14), radius: 8, y: 3)
        )
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityLabel(text)
    }
}

/// A transient line for the grid to show. The id restarts the timer even when the
/// same message arrives twice running.
struct Notice: Identifiable, Equatable {
    let id = UUID()
    /// A key, like everything else the app says. `Equatable` still works —
    /// `LocalizedStringKey` compares by key and arguments, which is what the
    /// toast's animation identity needs anyway.
    let text: LocalizedStringKey
    let tint: Color
}
