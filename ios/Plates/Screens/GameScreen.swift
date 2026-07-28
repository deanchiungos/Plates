import SwiftUI
import SwiftData

struct GameScreen: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Trip> { $0.endedAt == nil },
           sort: \Trip.startedAt, order: .reverse)
    private var activeTrips: [Trip]

    @Query(sort: \Player.joinedAt) private var players: [Player]

    /// Set when a tap needs attributing and more than one person is playing.
    @State private var attributing: Plate?
    @State private var canadaExpanded = false
    @State private var query = ""
    @State private var searchOpen = false
    @State private var addingPlayer = false

    private var trip: Trip? { activeTrips.first }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if let trip {
                    content(for: trip)
                } else {
                    ContentUnavailableView {
                        Label("No active trip", systemImage: "car")
                    } description: {
                        Text("Start a trip to begin spotting plates.")
                    } actions: {
                        Button("Start a trip") { startTrip() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.route)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            #if DEBUG
            // `-search NEW` opens the bar pre-filled, so the filter and the
            // scroll-to-match can be exercised without typing.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-search"), i + 1 < args.count {
                    query = args[i + 1]
                    searchOpen = true
                }
            }
            #endif
        }
        .confirmationDialog(
            attributing.map { "Who spotted \($0.code)?" } ?? "",
            isPresented: Binding(get: { attributing != nil },
                                 set: { if !$0 { attributing = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(players) { player in
                Button(player.name) {
                    if let plate = attributing { record(plate, by: player) }
                    attributing = nil
                }
            }
            Button("Cancel", role: .cancel) { attributing = nil }
        }
        .sheet(isPresented: $addingPlayer) {
            PlayerEditor(player: nil,
                         usedColors: Set(players.map(\.colorIndex)),
                         onDelete: nil)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for trip: Trip) -> some View {
        VStack(spacing: 0) {
            PlateSearchBar(query: $query,
                           isOpen: $searchOpen,
                           matchCount: PlateSearch.matchCount(query: query))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        TripCard(trip: trip)

                        if players.count > 1 {
                            PlayerStrip(standings: trip.standings(among: players))
                                .padding(.top, 12)
                        } else {
                            // Solo still needs a way in, or local multiplayer is
                            // invisible to anyone who never opens the Players tab.
                            Button { addingPlayer = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Playing with others? Add players")
                                        .font(.system(size: 13, weight: .semibold))
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

                        section(
                            title: "States",
                            detail: "\(trip.statesFound) / \(Plate.stateTotal) found",
                            plates: Plate.states,
                            trip: trip
                        )
                        .padding(.top, 18)

                        section(
                            title: "Bonus plates",
                            detail: "\(trip.bonusFound) / \(Plate.bonus.count) found",
                            plates: Plate.bonus,
                            trip: trip
                        )
                        .padding(.top, 22)

                        canadaSection(trip: trip)
                            .padding(.top, 22)
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
                         plates: [Plate], trip: Trip) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: title, detail: detail)
            grid(plates: plates, trip: trip)
        }
    }

    /// Canada stays its own collapsible section rather than folding into the main
    /// list — it is a different country, and 13 provinces would otherwise bury the
    /// states you are actually hunting.
    private func canadaSection(trip: Trip) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { canadaExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Canada")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkMuted)
                        .rotationEffect(.degrees(canadaExpanded ? 90 : 0))
                    Spacer()
                    Text("\(trip.provincesFound) / \(Plate.provinces.count) found")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canadaExpanded {
                grid(plates: Plate.provinces, trip: trip)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func grid(plates: [Plate], trip: Trip) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.tileMinWidth,
                                         maximum: Theme.tileMaxWidth),
                               spacing: Theme.gridGap)],
            spacing: Theme.gridGap
        ) {
            let searching = PlateSearch.isActive(query)
            ForEach(plates) { plate in
                let found = trip.hasSeen(plate)
                let hit = PlateSearch.matches(plate, query: query)
                Button {
                    tap(plate, in: trip)
                } label: {
                    let spotter = players.count > 1 && found ? trip.spotter(of: plate) : nil
                    PlateTile(
                        plate: plate,
                        isFound: found,
                        spotterColor: spotter.map { Theme.playerColor($0.colorIndex) },
                        spotterInitial: spotter?.initial,
                        repeatCount: trip.sightingCount(for: plate),
                        showsRepeats: trip.scoringMode == .unlimited
                    )
                }
                .buttonStyle(TileButtonStyle())
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
                .zIndex(searching && hit ? 1 : 0)
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

    // MARK: - Actions

    private func tap(_ plate: Plate, in trip: Trip) {
        // Unlimited counts every sighting, so a tap always adds. The other modes
        // toggle, which is how you undo a mistake.
        if trip.scoringMode != .unlimited, trip.hasSeen(plate) {
            clear(plate, in: trip)
            return
        }
        if players.count > 1 {
            attributing = plate
        } else {
            record(plate, by: players.first)
        }
    }

    private func record(_ plate: Plate, by player: Player?) {
        guard let trip else { return }
        context.insert(Sighting(plateCode: plate.code, trip: trip, player: player))
        try? context.save()
    }

    private func clear(_ plate: Plate, in trip: Trip) {
        for sighting in trip.allSightings where sighting.plateCode == plate.code {
            context.delete(sighting)
        }
        try? context.save()
    }

    private func startTrip() {
        let trip = Trip(name: "Summer Roadtrip")
        context.insert(trip)
        try? context.save()
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
