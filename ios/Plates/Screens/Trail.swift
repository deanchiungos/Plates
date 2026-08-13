import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// The Trail — where you were when you logged each plate.
///
/// `MapScreen` answers "which states have I collected". This answers "where was I",
/// which is the more personal question: the shape it draws is the shape of your
/// drives, and the line through the pins is the road you actually took.
///
/// It is its own page rather than a card on the map, because the framing is the
/// point. A trail wants the whole screen and a camera derived from the pins — a
/// fixed national frame would reduce a weekend's sightings to a smudge somewhere
/// over Pennsylvania.
///
/// **Every sighting gets its own plate on the map.** An earlier version bucketed
/// pins to a kilometre and drew "2" in a coloured bubble wherever two landed in the
/// same bucket, which threw away the only thing worth looking at — *which* plates.
/// Two plates a kilometre apart are separate pins at any zoom you would actually
/// read them at, so the merge was solving a problem the map did not have. Sightings
/// that really do share a fix are fanned out like a hand of cards instead, and each
/// card is tappable in its own right.
struct TrailScreen: View {
    @Environment(PopupHost.self) private var popup
    @Environment(Router.self) private var router
    @Environment(CoachPresenter.self) private var coach

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Sighting.spottedAt) private var allSightings: [Sighting]

    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"
    @State private var scope: Scope?
    @State private var selected: UUID?
    /// The plates at a stop whose list is open, by id. Big bundles do not unfold on
    /// the map at all — see `TrailBundleView.listThreshold`.
    ///
    /// The pins themselves rather than a group key, because which pins are grouped
    /// together now depends on the zoom. A key would stop matching anything the
    /// moment the map moved under the open sheet.
    @State private var stop: [UUID]?

    /// Opens on whatever you are playing, not on everything.
    ///
    /// All-time is the wider view but it cannot draw the road — a line joining a
    /// sighting in Maine in 2024 to one in Arizona in 2026 is not a journey anyone
    /// took. Defaulting to what is already on the Game screen means the pins you
    /// were just adding are the pins you land on, without going through a menu first.
    ///
    /// Resolved through `PlaySelection` rather than by reading the trip id directly.
    /// Reading the id was the bug: a book selected on the Game screen left this
    /// falling back to whichever trip happened to be first, so filling in a book and
    /// then opening the Trail showed you someone else's road. Going through
    /// `PlaySelection` is what every other screen does, and it is the only thing that
    /// knows the *kind* — trip or book — is part of the answer.
    private var effectiveScope: Scope {
        if let scope { return scope }
        switch PlaySelection.current(kind: targetKind, tripID: currentTripID,
                                     bookID: currentBookID, trips: trips, books: books) {
        case .trip(let trip): return .trip(trip.id)
        case .book(let book): return .book(book.id)
        case nil:             return .allTime
        }
    }

    enum Scope: Hashable {
        case allTime
        case trip(UUID)
        case book(UUID)
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                scopeBar

                if pins.isEmpty {
                    Spacer()
                    empty
                    Spacer()
                } else {
                    TrailMap(pins: pins, path: pathCoordinates,
                             selected: $selected, stop: $stop)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) { summary }
                }
            }
        }
        .navigationTitle("Trail")
        .navigationBarTitleDisplayMode(.inline)
        // A jump from elsewhere — "View trail" on a trip's record — lands here
        // with the scope it wants already chosen. Consumed, not just read, so a
        // later visit through the More tab opens on the usual default.
        .onAppear {
            if let handed = router.pendingTrail {
                scope = handed
                router.pendingTrail = nil
            }
        }
        .onChange(of: router.pendingTrail) { _, handed in
            if let handed {
                scope = handed
                router.pendingTrail = nil
            }
        }
        .onAppear(perform: offerScopeTip)
        // Leaving counts as shown. See `CoachPresenter.withdraw`.
        .onDisappear { coach.withdraw(.trailScope) }
        // One sheet, two things it can be showing. Two `.sheet` modifiers on the same
        // view cannot both present, and a stop's list has to be able to push a plate's
        // detail rather than stack a second sheet on top of itself.
        .sheet(item: Binding(get: { presented }, set: { if $0 == nil { clearSheet() } })) {
            switch $0 {
            case .pin(let pin):       TrailPinDetail(pin: pin)
            case .stop(let atStop):   TrailStopSheet(pins: atStop)
            }
        }
        #if DEBUG
        // `-trailSelect` opens the detail sheet on the newest pin. Map annotations
        // cannot be tapped from a launch argument, and this sheet is otherwise only
        // reachable by hand. `-trailScope` opens the scope picker, same reason.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if args.contains("-trailSelect") { selected = pins.last?.id }
                if args.contains("-trailScope") { showScopePicker() }
            }
        }
        #endif
        // Last in the chain, so the balloon draws over the map and under the tab
        // bar. Copy lives here rather than in a table elsewhere: whoever changes
        // what the tip says is the person looking at the screen it appears on.
        .coachLayer([
            .trailScope: "This is one drive. Tap here to see another, or everything ever."
        ])
    }

    /// What the one sheet is showing, if anything.
    private enum Presented: Identifiable {
        case pin(TrailPin)
        case stop(pins: [TrailPin])

        var id: String {
            switch self {
            case .pin(let pin):   return "pin-" + pin.id.uuidString
            case .stop(let pins): return "stop-" + (pins.first?.id.uuidString ?? "")
            }
        }
    }

    private var presented: Presented? {
        if let stop {
            let wanted = Set(stop)
            let atStop = pins.filter { wanted.contains($0.id) }
            if !atStop.isEmpty { return .stop(pins: atStop) }
        }
        if let pin = pins.first(where: { $0.id == selected }) { return .pin(pin) }
        return nil
    }

    private func clearSheet() {
        selected = nil
        stop = nil
    }

    // MARK: - Scope

    private var scopeBar: some View {
        // A popup rather than a system Menu. A Menu of twenty trips is a wall of
        // near-identical names with no way to narrow it — you scroll it looking for
        // one word. `PopupPicker` puts a search field above the list once it is long
        // enough to need one, and it is the same control the Game and Book screens
        // use for the same question.
        Button { showScopePicker() } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(scopeName)
                    .font(.plates(size: 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.route)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .coachAnchor(.trailScope)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 10)
    }

    /// The bar names what you are looking at, which is exactly why it does not read
    /// as a control — "Summer Roadtrip" in a capsule is a title until you learn it
    /// is a button. The tip is the one thing that says so.
    ///
    /// Only worth saying when there is somewhere else to go: all-time plus one trip
    /// is two scopes and a real choice; a phone with nothing on it is neither.
    private func offerScopeTip() {
        coach.request(.trailScope,
                      when: !pins.isEmpty && trips.count + books.count >= 1)
    }

    private func showScopePicker() {
        // Opening the picker is the whole of what the tip was asking for.
        coach.dismiss(.trailScope)
        // `playable`, not `collectable`. This picks what you are *looking at*, and a
        // trip you have finished is exactly the kind of thing you come here to look
        // at.
        //
        // Which is why the archived trips get a group of their own below rather than
        // staying out entirely. Marking a trip done *files it under Archived*, so
        // excluding archived trips here meant finishing a trip removed its road from
        // the one screen built for looking back at it. Collapsed hard, because the
        // whole point of the archive is to stop seeing these until you ask.
        let openTrips = trips.playable.pinnedFirst
        let archived = trips.archived
        let groups = [
            PopupPicker.Group(entries: [
                // The one entry in this picker that is the app's words rather than
                // a trip somebody named, so it localises itself before going in.
                // `Entry.title` stays a plain `String` because the search field
                // matches against it.
                PopupPicker.Entry(id: allTimeID,
                                  title: String(localized: "All time"),
                                  subtitle: String(localized: "Every plate ever logged"),
                                  isSelected: effectiveScope == .allTime,
                                  action: { pick(.allTime) })
            ]),
            PopupPicker.Group(
                title: openTrips.isEmpty ? nil : "TRIPS",
                entries: openTrips.map { trip in
                    PopupPicker.Entry(id: trip.id,
                                      title: trip.name,
                                      subtitle: trip.routeLabel ?? trip.startedAt
                                          .formatted(.dateTime.month(.abbreviated).day().year()),
                                      isSelected: effectiveScope == .trip(trip.id),
                                      keywords: [trip.origin, trip.destination]
                                          .compactMap { $0 }.joined(separator: " "),
                                      action: { pick(.trip(trip.id)) })
                },
                collapseTo: 5),
            PopupPicker.Group(
                title: books.isEmpty ? nil : "BOOKS",
                entries: books.map { book in
                    PopupPicker.Entry(id: book.id,
                                      title: book.name,
                                      subtitle: book.sinceLabel,
                                      isSelected: effectiveScope == .book(book.id),
                                      action: { pick(.book(book.id)) })
                }),
            PopupPicker.Group(
                title: archived.isEmpty ? nil : "FINISHED",
                entries: archived.map { trip in
                    PopupPicker.Entry(id: trip.id,
                                      title: trip.name,
                                      subtitle: trip.routeLabel ?? trip.startedAt
                                          .formatted(.dateTime.month(.abbreviated).day().year()),
                                      isSelected: effectiveScope == .trip(trip.id),
                                      keywords: [trip.origin, trip.destination]
                                          .compactMap { $0 }.joined(separator: " "),
                                      action: { pick(.trip(trip.id)) })
                },
                collapseTo: 2)
        ].filter { !$0.entries.isEmpty }

        popup.present("Show which drive?") {
            PopupPicker(groups: groups)
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    /// A stable id for the one entry that is not backed by a model object.
    private var allTimeID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-00000000A11E") ?? UUID()
    }

    private func pick(_ next: Scope) {
        scope = next
        clearSheet()
        Haptics.selection()
        popup.dismiss()
    }

    private var scopeName: String {
        switch effectiveScope {
        case .allTime:       return "All time"
        case .trip(let id):  return trips.first { $0.id == id }?.name ?? "Trip"
        case .book(let id):  return books.first { $0.id == id }?.name ?? "Book"
        }
    }

    private var scopedSightings: [Sighting] {
        switch effectiveScope {
        case .allTime:      return allSightings
        case .trip(let id): return allSightings.filter { $0.trip?.id == id }
        case .book(let id): return allSightings.filter { $0.book?.id == id }
        }
    }

    private var pins: [TrailPin] { TrailPin.from(scopedSightings) }

    /// The road, in the order you drove it.
    ///
    /// Drawn only for a single trip. An all-time line would join a sighting in Maine
    /// in 2024 to one in Arizona in 2026 and call it a journey, which is not a road
    /// anyone drove — the pins are still true, the line between them would not be.
    private var pathCoordinates: [CLLocationCoordinate2D] {
        guard case .trip = effectiveScope else { return [] }
        let located = scopedSightings
            .filter { $0.spottedLat != nil && $0.spottedLon != nil }
            .sorted { $0.spottedAt < $1.spottedAt }
        guard located.count > 1 else { return [] }
        return located.map { .init(latitude: $0.spottedLat!, longitude: $0.spottedLon!) }
    }

    // MARK: - Chrome

    private var summary: some View {
        let plates = Set(pins.map(\.code)).count
        let stops = Set(pins.map(\.stopKey)).count
        return HStack(spacing: 14) {
            stat("\(plates)", plates == 1 ? "plate" : "plates")
            stat("\(stops)", stops == 1 ? "stop" : "stops")
            if let spread = spanLabel { stat(spread, "across") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: Theme.ink.opacity(0.16), radius: 10, y: 4)
        )
        .padding(.bottom, 22)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(Theme.PlateFont.condensed(19))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.plates(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    /// How far apart the two furthest-apart pins are — a rough sense of the ground
    /// covered without pretending to know the road distance between them.
    private var spanLabel: String? {
        let coords = pins.map(\.coordinate)
        guard coords.count > 1,
              let minLat = coords.map(\.latitude).min(),
              let maxLat = coords.map(\.latitude).max(),
              let minLon = coords.map(\.longitude).min(),
              let maxLon = coords.map(\.longitude).max() else { return nil }

        let metres = GreatCircle.metres(.init(latitude: minLat, longitude: minLon),
                                        .init(latitude: maxLat, longitude: maxLon))
        guard metres > 1_000 else { return nil }

        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: metres, unit: UnitLength.meters))
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
            Text("No trail yet")
                .font(.plates(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Turn on location and every plate you spot drops a pin here. Ones you collected before then have no pin to show.")
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
    }
}

// MARK: - Pins

/// One sighting, on the map, as itself.
struct TrailPin: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let code: String
    let spottedAt: Date
    let rarity: Int
    let spotter: String?
    let spotterColorIndex: Int?
    let collection: String?

    /// Which stop this belongs to, for counting them. Three decimals, about a
    /// hundred metres.
    ///
    /// Deliberately *not* what decides how pins are bundled on the map. Bundling is
    /// a question about pixels — do these two cards overlap — and the answer changes
    /// with the zoom, so it lives in `TrailMap.bundles`. This is only ever the
    /// "19 stops" in the summary bar, which should not change when you pinch.
    let stopKey: String

    var tier: RarityTier { RarityTier.forRarity(rarity) }
    var plate: Plate? { Plate.plate(for: code) }

    static func == (a: TrailPin, b: TrailPin) -> Bool { a.id == b.id }

    static func from(_ sightings: [Sighting]) -> [TrailPin] {
        sightings
            .sorted { $0.spottedAt < $1.spottedAt }
            .compactMap { s in
                guard let lat = s.spottedLat, let lon = s.spottedLon else { return nil }
                return TrailPin(
                    id: s.id,
                    coordinate: .init(latitude: lat, longitude: lon),
                    code: s.plateCode,
                    spottedAt: s.spottedAt,
                    rarity: s.rarityWhenSpotted ?? Plate.plate(for: s.plateCode)?.points ?? 1,
                    spotter: s.player?.name,
                    spotterColorIndex: s.player?.colorIndex,
                    collection: s.trip?.name ?? s.book?.name,
                    stopKey: String(format: "%.3f_%.3f", lat, lon)
                )
            }
    }
}

// MARK: - Map

struct TrailMap: View {
    let pins: [TrailPin]
    var path: [CLLocationCoordinate2D] = []
    @Binding var selected: UUID?
    @Binding var stop: [UUID]?

    @State private var camera: MapCameraPosition = .automatic

    /// The id of the bundle currently standing up as a column, if any. One
    /// at a time: two open columns on the same screen would overlap each other and
    /// undo the thing they exist to fix.
    @State private var expanded: String?

    /// When a marker last took a tap.
    ///
    /// The map's own tap gesture and an annotation's both fire for a tap that lands
    /// on an annotation, in an order SwiftUI does not promise. Without this the
    /// background handler would collapse a bundle in the same frame the marker
    /// opened it, and a bundle could never be expanded at all.
    @State private var markerTappedAt = Date.distantPast

    /// How far out the camera is, as a whole number of doublings of the visible
    /// longitude span — `floor(log2(span))`, the same ladder map tiles use.
    ///
    /// **This used to be the live `MKCoordinateRegion`, and that is what made the
    /// screen come apart in your hands.** Two things read the camera: the marker
    /// scale, and the grid `bundles` groups pins on. Both were computed from a span
    /// that a continuous camera callback rewrote sixty times a second, so a pinch
    /// meant sixty new grid spacings a second — and the grid cell *is* the bundle's
    /// identity. Every frame, markers that had been sharing a cell stopped sharing
    /// it, `ForEach` tore down annotations and built new ones, half-finished fold
    /// animations were interrupted by their own replacements, and around the zoom
    /// where pins sit near a cell boundary the whole thing thrashed between two
    /// groupings and never settled. Layered on top, a 0.18s size animation was being
    /// restarted sixty times a second on a value that never stopped moving.
    ///
    /// Discrete steps fix it by construction. Grouping changes exactly once per
    /// doubling — which is what every clustering map does — and between those points
    /// there is nothing to recompute, so a pinch is just a pinch.
    ///
    /// Seeded at 5, matching the continental span the camera opens on, so the first
    /// frame is not grouped at some other zoom's spacing.
    @State private var zoomStep = 5

    /// The longitude span this step stands for.
    private var stepSpan: Double { pow(2, Double(zoomStep)) }

    /// How much a whole doubling the camera has to travel *past* the step it is in
    /// before the step changes.
    ///
    /// Without this the deadband is zero, and a camera parked exactly on a boundary
    /// — which is precisely where a pinch tends to come to rest — can be flipped
    /// back and forth across it by the last few pixels of finger movement, which is
    /// the original bug again in miniature.
    private static let stepHysteresis = 0.12

    /// 1 when you are down at street level, 0.55 when the whole country is in frame.
    /// Below that the state code stops being readable, which is the floor.
    ///
    /// Six values across the whole range rather than a continuum, so the size
    /// animation fires on a real change and has time to finish.
    private var zoomScale: CGFloat {
        let t = min(max((Double(zoomStep) + 1) / 5, 0), 1)
        return 1.0 - 0.45 * t
    }

    /// The map's own size in points, so overlap can be reasoned about in pixels.
    @State private var mapSize: CGSize = .zero

    var body: some View {
        Map(position: $camera) {
            // A wash over the basemap, under everything else.
            //
            // Apple's standard map is built to be read on its own, so every park,
            // river and motorway is at full strength, and a 48pt plate has to compete
            // with cartography that was not expecting company. A sheet of the app's
            // own paper colour knocks it back to a ghost of itself: coastlines and
            // motorways still legible enough to place a pin, nothing loud enough to
            // fight one.
            //
            // Paper, not ink. Taking the ground toward navy did make the plates the
            // brightest thing on screen, but it also turned a road-trip map into a
            // night-mode dashboard, which is not what this app is.
            //
            // **Fixed, and far bigger than the screen.** This is where the cheap look
            // came from the first time. The wash was sized to the visible region and
            // rebuilt on every camera frame, and a polygon is drawn in map
            // coordinates — so it travels with the ground under your finger, and a
            // rebuild that lands a frame late leaves a bright unwashed margin along
            // the edge you are dragging away from, until the gesture stops and the
            // wash snaps back to fill the screen. A box that already covers the
            // hemisphere has no edge to expose and nothing to recompute: there is
            // nothing left to lag, and nothing left to snap.
            MapPolygon(coordinates: TrailMap.veil)
                .foregroundStyle(Theme.ground.opacity(0.5))

            if path.count > 1 {
                // Cased in white so it stays visible crossing motorways and
                // coastline, and rounded at every joint so a trail that doubles
                // back does not draw a spike.
                MapPolyline(coordinates: path)
                    .stroke(.white.opacity(0.95), style: .init(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: path)
                    .stroke(Theme.route.opacity(0.9),
                            style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            // ONE annotation per fix, not one per plate.
            //
            // Every plate at a stop used to be its own annotation, displaced by
            // padding so its bounds followed it. That fixed the drawing and broke
            // the touches: five annotations at one coordinate means five frames
            // stacked on the same point, each tall enough to reach its own card, so
            // the topmost card's frame lies across every card below it. A tap on a
            // lower card landed in a higher one's transparent padding, and from
            // there fell through to the map — which closes the group. The top of a
            // column worked; everything under it did not.
            //
            // A bundle is one annotation now, and the cards inside it are ordinary
            // sibling views in an ordinary layout. Nothing overlaps that is not
            // meant to, and hit-testing is SwiftUI's own.
            // Keyed on whether it is open, so opening one mints a *new* annotation.
            // MapKit does not re-apply an anchor when an existing annotation's content
            // grows — it leaves the column hanging about 90pt below the fix it belongs
            // to. A new identity is sized and anchored from scratch.
            ForEach(bundles) { bundle in
                Annotation("", coordinate: bundle.coordinate, anchor: .bottom) {
                    TrailBundleView(pins: bundle.pins,
                                    isExpanded: bundle.id.hasSuffix("-open"),
                                    selectedID: selected,
                                    scale: zoomScale) { tapped($0, in: bundle) }
                }
                .annotationTitles(.hidden)
            }
        }
        // `.automatic`, not `.muted`. Muting desaturates the basemap at render time,
        // and stacking the cream wash on top of that took the land to a pale mint and
        // the sea to almost nothing: a road-trip map with no country in it. What
        // actually needed knocking back was the *clutter* — every park, motorway and
        // shop competing with a 48pt plate — and `pointsOfInterest: .excludingAll`
        // does that on its own, without draining the green out of the continent.
        //
        // So the colour comes from MapKit at full strength and the cream wash is the
        // only thing softening it. The wash is the dial: at 0.34 the map came back
        // fully saturated and read as raw Apple Maps with plates dropped on it; 0.5
        // keeps land green and water blue while still holding them a step behind. The
        // plates read regardless, because what makes them read is that they are white,
        // sharp-edged and casting a shadow, not that everything under them is grey.
        .mapStyle(.standard(elevation: .flat,
                            emphasis: .automatic,
                            pointsOfInterest: .excludingAll,
                            showsTraffic: false))
        .mapControlVisibility(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        // Tapping bare map puts an open bundle back down. The guard is the tap-order
        // problem described on `markerTappedAt`.
        .onTapGesture {
            guard Date().timeIntervalSince(markerTappedAt) > 0.35 else { return }
            collapse()
        }
        .onAppear {
            camera = .region(TrailMap.fit(pins))
            #if DEBUG
            // `-trailExpand` stands the first bundle up. Map annotations cannot be
            // tapped from a launch argument, so this is the only way to see the
            // expanded column without a finger.
            if ProcessInfo.processInfo.arguments.contains("-trailExpand") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        expanded = bundles.first { $0.pins.count > 1 }?.id
                    }
                }
            }
            #endif
        }
        // Still continuous, so the markers do resize while your fingers are moving —
        // but it writes state only when the camera crosses a whole step, which over a
        // full zoom from street to continent is six times rather than several hundred.
        .onMapCameraChange(frequency: .continuous) { context in
            let raw = log2(max(context.region.span.longitudeDelta, 1e-6))
            let low = Double(zoomStep) - Self.stepHysteresis
            let high = Double(zoomStep) + 1 + Self.stepHysteresis
            guard raw < low || raw > high else { return }
            zoomStep = Int(raw.rounded(.down))
            // The open bundle's key belongs to the old grid and does not exist in the
            // new one, so it would sit there un-closable until the next tap.
            expanded = nil
        }
        // Panning or zooming away from an open column is also a way of dismissing it,
        // and leaving it standing while the map moves under it looks like a bug.
        .onMapCameraChange(frequency: .onEnd) { _ in
            if expanded != nil { collapse() }
        }
        // A new filter is a new set of pins and therefore a new frame; without this
        // the camera would keep whatever the previous selection framed.
        .onChange(of: pins.map(\.id)) { _, _ in
            selected = nil
            expanded = nil
            withAnimation(.snappy(duration: 0.45)) { camera = .region(TrailMap.fit(pins)) }
        }
    }

    /// Pins grouped by whether their cards would land on top of each other.
    ///
    /// This used to group on a fixed eleven-metre bucket, which is the resolution of
    /// a single GPS fix and nothing like the resolution of a *stop*. Standing in one
    /// car park for five minutes produces fixes scattered over tens of metres, so a
    /// stop almost never grouped — you got a deck for the handful that happened to
    /// agree to four decimal places and a scatter of loose cards sitting on top of
    /// it, with the deck nearly impossible to hit.
    ///
    /// Overlap is a question about pixels, so it is answered in pixels: the grid is
    /// one marker wide at the current zoom, converted into degrees. Zoom out and
    /// neighbours merge; zoom in and they separate, which is what every map does and
    /// what makes the bundles reachable at any scale.
    ///
    /// The grid is absolute rather than relative to the camera's centre, so *panning*
    /// never changes the grouping — only zooming does. Regrouping mid-drag would make
    /// cards merge and split under the finger.
    ///
    /// And it is sized from `zoomStep`, not from the live span, so *zooming* only
    /// changes it at the six places the step changes. See `zoomStep` for what
    /// happened when this recomputed on every camera frame.
    /// **Distance from a neighbour, not a square on a lattice.**
    ///
    /// The lattice is why stacks took so long to form. Two pins a hand's breadth
    /// apart merge only if they happen to fall inside the same square, and a boundary
    /// running between them keeps them apart no matter how close they are — so
    /// collecting eight scattered pins into one bundle meant zooming out until the
    /// whole scatter landed in a single cell, which for a cross-country trip was a
    /// span of 128°, most of a hemisphere. Half the neighbours merged and half did
    /// not, at every zoom, with nothing on screen to explain which.
    ///
    /// Measuring the distance instead means anything within `radius` of a bundle
    /// joins it, wherever the pins happen to sit. The same route now decks at 64°
    /// — a full doubling sooner — and the counts on the way down are steadier too:
    /// 21 bundles at 16° becomes 13, and 13 at 32° becomes 8.
    ///
    /// First-match rather than a full clustering pass, which is what keeps it cheap
    /// and, more importantly, deterministic: pins arrive in spotting order, the first
    /// pin of a group is its anchor, and a group can never grow wider than twice the
    /// radius — so a long route cannot chain itself into one bundle.
    private var bundles: [TrailBundle] {
        // 60pt, against a card that runs 26 to 48pt wide. Deliberately a little more
        // than a card: markers should merge just before they collide, because a pair
        // caught halfway through overlapping is the messiest thing this map can draw.
        //
        // Not scaled by the card size, which shrinks as you zoom out. That would make
        // grouping *less* eager exactly where the map most needs summarising.
        let radius = 60.0 * stepSpan / Double(max(mapSize.width, 1))

        var order: [String] = []
        var anchors: [(key: String, at: CLLocationCoordinate2D)] = []
        var byKey: [String: [TrailPin]] = [:]
        for pin in pins {
            let near = anchors.first { anchor in
                let dLon = pin.coordinate.longitude - anchor.at.longitude
                // A degree of latitude covers 1/cos(lat) as much screen as a degree
                // of longitude does in Mercator, so the two have to be brought to the
                // same units before they can be one distance. Taken at 40°N, the
                // middle of the ground this game is played on.
                let dLat = (pin.coordinate.latitude - anchor.at.latitude) / 0.766
                return (dLon * dLon + dLat * dLat).squareRoot() <= radius
            }
            if let near {
                byKey[near.key, default: []].append(pin)
            } else {
                let key = pin.id.uuidString
                order.append(key)
                anchors.append((key, pin.coordinate))
                byKey[key] = [pin]
            }
        }
        // The open one last, so it is added to the map after its neighbours. A
        // standing column is much taller than the markers around it and would
        // otherwise have their annotations lying across its lower cards — the same
        // overlap that made this unclickable in the first place, one level up.
        return order
            .sorted { ($0 == expanded ? 1 : 0) < ($1 == expanded ? 1 : 0) }
            .map { TrailBundle(id: $0 == expanded ? $0 + "-open" : $0, pins: byKey[$0]!) }
    }

    /// One tap, three meanings, decided by what the pin is part of.
    ///
    /// A lone pin opens its detail straight away. A pin in a collapsed bundle stands
    /// the whole bundle up instead — trying to hit one card in a fan is the thing
    /// this is here to avoid. Once the bundle is a column, every card is a full-width
    /// target and a tap means what it usually means.
    private func tapped(_ pin: TrailPin, in bundle: TrailBundle) {
        markerTappedAt = Date()
        Haptics.selection()
        if bundle.pins.count >= TrailBundleView.listThreshold {
            // Too many to stand up. Ten cards is a column taller than the screen and
            // fifty is not a shape at all, so a big stop is a list instead.
            stop = bundle.pins.map(\.id)
        } else if bundle.pins.count > 1 && !bundle.id.hasSuffix("-open") {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                expanded = bundle.id
            }
        } else {
            withAnimation(.snappy(duration: 0.22)) { selected = pin.id }
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { expanded = nil }
    }


    /// The wash, as one fixed box over the western hemisphere.
    ///
    /// Deliberately far larger than any camera this screen will reach — every plate
    /// in the game lies between Puerto Rico and the Yukon — because the whole point
    /// is that its edges are never on screen and it never has to be recomputed.
    /// Corners only: a latitude/longitude rectangle is still a rectangle once
    /// projected, so intermediate vertices would buy nothing.
    static let veil: [CLLocationCoordinate2D] = [
        .init(latitude: -12, longitude: -178),
        .init(latitude:  84, longitude: -178),
        .init(latitude:  84, longitude:  -25),
        .init(latitude: -12, longitude:  -25)
    ]

    /// The region that holds every pin, with margin.
    ///
    /// The floor stops a single pin — or several from one car park — zooming to
    /// individual buildings, which looks broken and implies more precision than a
    /// kilometre-accuracy fix actually has.
    static func fit(_ pins: [TrailPin]) -> MKCoordinateRegion {
        let lats = pins.map(\.coordinate.latitude)
        let lons = pins.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: .init(latitude: 39.5, longitude: -98.35),
                                      span: .init(latitudeDelta: 40, longitudeDelta: 50))
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max((maxLat - minLat) * 1.45, 0.2),
                        longitudeDelta: max((maxLon - minLon) * 1.45, 0.2))
        )
    }
}

// MARK: - Marker

/// One marker's worth of plates: a lone card, a fan, or a deck with a count.
///
/// A bundle is a fact about the *zoom*, not about the ground — the same plates are
/// one marker at a continental span and several at street level. `stopKey` on the pin
/// is the thing that describes the ground, and it is what the summary counts.
struct TrailBundle: Identifiable {
    /// The id of the pin that anchored the group. Stable for a given zoom step, and
    /// re-derived when that changes.
    let id: String
    let pins: [TrailPin]
    /// The anchor's own fix, so the marker sits on a real sighting rather than on an
    /// averaged point between them that nothing happened at.
    var coordinate: CLLocationCoordinate2D { pins[0].coordinate }
}

/// The bundle, drawn.
///
/// Deliberately one view for all three shapes rather than one annotation per plate.
/// Laying the cards out as siblings — an `HStack` with negative spacing for the fan,
/// a `VStack` for the column — means the bundle's frame is the union of its cards by
/// construction, which is the thing that makes them tappable. Displacing cards with
/// `.offset` inside a `ZStack` would look identical and hit-test just as badly as the
/// annotation-per-plate version did, because `.offset` never moves layout bounds.
struct TrailBundleView: View {
    let pins: [TrailPin]
    var isExpanded: Bool = false
    var selectedID: UUID?
    /// How wide the camera is. Cards shrink as the view widens, because a
    /// continent's worth of them at full size is a heap and hides the route line.
    var scale: CGFloat = 1
    var onTap: (TrailPin) -> Void = { _ in }

    /// A column is drawn larger than a card ever gets on the map, and at a fixed size
    /// however far out the camera is: expanding is a request to read the thing and
    /// then hit it with a thumb.
    ///
    /// 1.5 rather than something rounder because of what it works out to — a 48pt
    /// card becomes 72 x 43, and with the row gap that clears the 44pt Apple asks a
    /// touch target to be. At 1.35 the rows were 39pt.
    private static let columnScale: CGFloat = 1.5

    /// 0 when the bundle is a fan, 1 when it is a column. Everything about the shape
    /// is a function of this one number, which is what lets it fold.
    private var fold: CGFloat { isExpanded ? 1 : 0 }
    private var cardScale: CGFloat {
        scale + (Self.columnScale - scale) * fold
    }
    private var width: CGFloat { 48 * cardScale }
    private var height: CGFloat { width / Theme.tileAspect }

    /// Above this many plates at one fix, the bundle stops being a shape on the map
    /// and becomes a list.
    ///
    /// A column is a good way to read three or four plates and a bad way to read ten:
    /// six rows already fill most of the map, and a rest stop where fifty went past
    /// has no arrangement that works at all. Past the threshold the marker is a deck
    /// with a count on it, and tapping opens a searchable list of what was seen there.
    ///
    /// Five, down from six, so a fan never holds more than the "three or four" the
    /// paragraph above is actually arguing for — a fan of five was already past the
    /// point where the cards behind read as anything but clutter. Independent of the
    /// grouping radius in `bundles`: that decides *which* pins are one marker, this
    /// decides what a marker of that size is drawn as.
    static let listThreshold = 5

    var body: some View {
        if pins.count >= Self.listThreshold {
            deck
        } else {
            folding
        }
    }

    /// A big stop: three cards squared up in a pile, and the count.
    ///
    /// Not a fan — a fan of ten is the mess this exists to avoid, and there is no
    /// point fanning cards you cannot read. The pile says "several plates, here"; the
    /// list says which.
    private var deck: some View {
        let lean = 3.5 * scale
        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ForEach(Array(pins.suffix(3).enumerated()), id: \.element.id) { i, pin in
                    card(pin)
                        .offset(x: CGFloat(2 - i) * lean, y: CGFloat(2 - i) * -lean)
                }
            }
            // The back cards lean up and right by `.offset`, which does not grow the
            // pile's bounds. Padding puts that room back, so the whole deck — not
            // just the front card — is inside the frame that gets hit-tested.
            .padding(.top, lean * 2)
            .padding(.trailing, lean * 2)
            .overlay(alignment: .topTrailing) { badge }

            Stem()
                .fill(.white)
                .frame(width: 8 * scale, height: 5.5 * scale)
                .offset(y: -0.5)
        }
        // One target for the whole pile. The front card carries its own gesture, but
        // a deck is a single object: tapping the corner of a card behind it, or the
        // count itself, has to open the same list.
        .contentShape(Rectangle())
        .onTapGesture { if let first = pins.first { onTap(first) } }
        .animation(.easeOut(duration: 0.18), value: scale)
    }

    private var badge: some View {
        Text("\(pins.count)")
            .font(Theme.PlateFont.condensed(13 * scale))
            .foregroundStyle(.white)
            .padding(.horizontal, 5 * scale)
            .frame(minWidth: 17 * scale, minHeight: 17 * scale)
            .background(Capsule().fill(Theme.route))
            .overlay(Capsule().strokeBorder(.white, lineWidth: 1.4))
    }

    private var folding: some View {
        // One layout for both shapes, and one animated number between them.
        //
        // This was an `if isExpanded { column } else { fan }`, and that is what made
        // closing so ugly. The two branches are separate view identities to SwiftUI,
        // so it cannot interpolate between them — it removes one and inserts the
        // other, and the container's frame jumps from column-sized to fan-sized in a
        // single step. On the way down that read as a snap to the ground, a bounce
        // back up, and only then the close.
        //
        // A custom `Layout` has none of that. The cards never change identity; the
        // layout places them at the interpolated point between their fan seat and
        // their column row, and `animatableData` means SwiftUI drives that
        // interpolation itself, in both directions, at whatever curve it is given.
        BundleFold(fold: fold, fanScale: scale, count: pins.count) {
            ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                card(pin)
                    // Straightens as it stands up.
                    .rotationEffect(.degrees(angle(index) * (1 - fold)), anchor: .bottom)
            }
            Stem()
                .fill(.white)
                .frame(width: 8 * cardScale, height: 5.5 * cardScale)
        }
        // A bundle reserves the room its column will need, and never changes size.
        //
        // MapKit does not re-apply an annotation's anchor when its content grows: the
        // column came out about 90pt below the fix it belongs to, animated or not,
        // because the annotation was still positioned for the size it had when it was
        // a fan. Holding the frame constant means there is nothing to re-anchor, and
        // it takes the size change out of the fold as well — what animates is where
        // the cards sit inside a box that was always this big.
        //
        // Only bundles. A lone pin never resizes, so giving it a column's worth of
        // reserved height would blanket its neighbours for no reason at all.
        .frame(width: isExpanded ? reserved.width : nil,
               height: isExpanded ? reserved.height : nil,
               alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isExpanded)
        .animation(.easeOut(duration: 0.18), value: scale)
    }

    /// The box an *open* bundle occupies: as tall as its column, as wide as its widest
    /// fan. Computed at the column's own scale so it does not move with the camera.
    ///
    /// Only while open, and that is the important part. Reserving it always was the
    /// obvious way to stop MapKit re-anchoring, and it broke something worse: a
    /// collapsed bundle then carried a 250pt invisible box reaching up the screen,
    /// and MapKit hands a tap to the first annotation whose *frame* contains it. Every
    /// bundle was quietly blanketing whatever sat above it — which is why the deck to
    /// the north of a fan could not be tapped at all.
    private var reserved: CGSize {
        let card = 48 * Self.columnScale
        let cardHeight = card / Theme.tileAspect
        let rows = CGFloat(pins.count)
        let height = rows * cardHeight
            + max(rows - 1, 0) * 4 * Self.columnScale
            + 5.5 * Self.columnScale
        // The fan is drawn at map scale, which never exceeds 1, so measuring it at 1
        // is the widest it can get.
        let step = pins.count > 1 ? min(24, 92 / CGFloat(pins.count - 1)) : 0
        let fanWidth = CGFloat(pins.count - 1) * step + 48
        return CGSize(width: max(card, fanWidth), height: height)
    }

    private func centred(_ index: Int) -> CGFloat {
        CGFloat(index) - CGFloat(pins.count - 1) / 2
    }

    private func angle(_ index: Int) -> Double {
        pins.count > 1 ? Double(centred(index)) * 6 : 0
    }

    /// The pin is the plate.
    ///
    /// The old marker was a coloured capsule with a state code or a count in it,
    /// which is a legend rather than a thing — the map told you a rarity band and
    /// made you remember what the colour meant. A plate needs no legend: it is the
    /// object being collected, in its own colours. Rarity survives as a hairline
    /// along the bottom edge, enough to spot the gold one without the marker becoming
    /// a badge.
    private func card(_ pin: TrailPin) -> some View {
        let style = PlateStyle.style(for: pin.code) ?? .fallback
        let isSelected = selectedID == pin.id

        return ZStack {
            RoundedRectangle(cornerRadius: 4.5 * cardScale, style: .continuous)
                .fill(.white)

            PlateBackground(code: pin.code, style: style)
                .clipShape(RoundedRectangle(cornerRadius: 3 * cardScale, style: .continuous))
                .padding(1.5 * cardScale)

            // No state name at this size — 48pt of card has room for the code and
            // nothing else. The ink still has to come from the artwork, though,
            // or the marker paints navy type onto a plate that turned white.
            PlateLettering(code: pin.code, style: style,
                           codeSize: 17 * cardScale, showsName: false)

            if pin.tier >= .rare {
                VStack {
                    Spacer()
                    Capsule()
                        .fill(pin.tier.color)
                        .frame(height: 2.5 * cardScale)
                        .padding(.horizontal, 4.5 * cardScale)
                        .padding(.bottom, 3 * cardScale)
                }
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 4.5 * cardScale, style: .continuous)
                .strokeBorder(isSelected ? pin.tier.color : .white,
                              lineWidth: isSelected ? 2.2 : 1.4)
        )
        // Light. The old shadow was heavy enough that twenty markers along a route
        // read as a smear of grey before you saw a single plate.
        .shadow(color: Theme.ink.opacity(isSelected ? 0.34 : 0.16),
                radius: isSelected ? 7 : 2.5, y: isSelected ? 3 : 1)
        .scaleEffect(isSelected ? (isExpanded ? 1.08 : 1.3) : 1, anchor: .bottom)
        .animation(.snappy(duration: 0.22), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { onTap(pin) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.plate?.name ?? pin.code)
        .accessibilityValue(pin.spottedAt.formatted(date: .abbreviated, time: .shortened))
        .accessibilityAddTraits(.isButton)
    }

    /// The little pointer under the plate, so the marker aims at the fix rather
    /// than floating over it.
    ///
    /// One notch for the bundle, not one per card. A fan is several plates logged at
    /// a single fix, so several notches would be claiming several fixes; and a notch
    /// per card cannot survive the fold anyway, because the ones that had to vanish
    /// would leave their space behind in the column.
    private struct Stem: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

/// Fan on one side, column on the other, and every position in between.
///
/// A `Layout` rather than offsets or two stacks, for two separate reasons that both
/// bit earlier in this file. Positions a layout assigns are real frames, so the cards
/// stay hit-testable — displacement by `.offset` never moves bounds, and that is what
/// made the expanded cards untappable. And `animatableData` makes the fold a single
/// interpolated number, so SwiftUI drives it continuously both ways rather than
/// swapping one arrangement for another and jumping between their sizes.
///
/// Subviews are the cards in spotting order, then the notch last.
private struct BundleFold: Layout {
    /// 0 = fan, 1 = column.
    var fold: CGFloat
    /// The card scale the map is currently drawing at, which the fan sits at.
    var fanScale: CGFloat
    var count: Int

    var animatableData: CGFloat {
        get { fold }
        set { fold = newValue }
    }

    private var scale: CGFloat { fanScale + (1.5 - fanScale) * fold }
    /// Half a card apart, so each keeps its own code visible, tightening only once
    /// the group would otherwise sprawl across the screen.
    private var spread: CGFloat {
        count > 1 ? min(24, 92 / CGFloat(count - 1)) * scale : 0
    }
    private var gap: CGFloat { 4 * scale }
    private var lift: CGFloat { 4.5 * scale }

    /// Where card `index` sits relative to the notch: sideways, and how far up.
    private func seat(_ index: Int, card: CGSize) -> (x: CGFloat, raise: CGFloat) {
        let centred = CGFloat(index) - CGFloat(count - 1) / 2
        let fanRaise = abs(centred) * lift
        let columnRaise = CGFloat(index) * (card.height + gap)
        return (x: centred * spread * (1 - fold),
                raise: fanRaise + (columnRaise - fanRaise) * fold)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard count > 0, subviews.count > count else { return .zero }
        let card = subviews[0].sizeThatFits(.unspecified)
        let stem = subviews[count].sizeThatFits(.unspecified)

        var half: CGFloat = 0, tallest: CGFloat = 0
        for index in 0..<count {
            let s = seat(index, card: card)
            half = max(half, abs(s.x) + card.width / 2)
            tallest = max(tallest, s.raise + card.height)
        }
        return CGSize(width: half * 2, height: tallest + stem.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard count > 0, subviews.count > count else { return }
        let card = subviews[0].sizeThatFits(.unspecified)
        let stem = subviews[count].sizeThatFits(.unspecified)
        let ground = bounds.maxY - stem.height

        for index in 0..<count {
            let s = seat(index, card: card)
            subviews[index].place(at: CGPoint(x: bounds.midX + s.x, y: ground - s.raise),
                                  anchor: .bottom, proposal: .unspecified)
        }
        subviews[count].place(at: CGPoint(x: bounds.midX, y: bounds.maxY),
                              anchor: .bottom, proposal: .unspecified)
    }
}

// MARK: - Detail

/// What one pin knows about itself: which plate, when, where, who called it.
struct TrailPinDetail: View {
    @Environment(\.dismiss) private var dismiss
    let pin: TrailPin

    var body: some View {
        NavigationStack {
            TrailPinDetailBody(pin: pin)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
    }
}

/// The detail itself, without a sheet around it, so a stop's list can push to it.
struct TrailPinDetailBody: View {
    let pin: TrailPin

    @State private var place: String?

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    rows
                }
                .padding(Theme.screenPadding)
            }
        }
        .navigationTitle(pin.plate?.name ?? pin.code)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: pin.id) { place = await PlaceNames.name(for: pin.coordinate) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let plate = pin.plate {
                PlateTile(plate: plate, isFound: true, rarity: pin.rarity)
                    .frame(width: 116)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(pin.tier.label)
                    .font(Theme.PlateFont.condensed(22))
                    .foregroundStyle(pin.tier.color)

                Text(pin.spottedAt.formatted(.relative(presentation: .named)))
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.inkMuted)

                if let spotter = pin.spotter {
                    HStack(spacing: 5) {
                        SpotterChip(name: spotter, colorIndex: pin.spotterColorIndex ?? 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("clock", "Spotted",
                pin.spottedAt.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
            divider
            row("mappin.and.ellipse", "Where", place ?? coordinateText, isPending: place == nil)
            if let collection = pin.collection {
                divider
                row("road.lanes", "Logged on", collection)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 44)
    }

    private func row(_ symbol: String, _ label: LocalizedStringKey, _ value: String,
                     isPending: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.route)
                .frame(width: 20)
            Text(label)
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.plates(size: 13, weight: .semibold))
                .foregroundStyle(isPending ? Theme.inkMuted : Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    /// Shown while the place name is being looked up, and kept if there is none —
    /// a fix in the middle of Nevada may genuinely have no nearby name.
    private var coordinateText: String {
        String(format: "%.4f, %.4f", pin.coordinate.latitude, pin.coordinate.longitude)
    }
}

/// Coordinates to something a person would say out loud.
///
/// Cached by rounded coordinate for the life of the process. Geocoding is a network
/// round trip and Apple rate-limits it per app, so the same rest stop must not be
/// looked up again every time its plate is tapped. Failure is not an error worth
/// showing: the sheet falls back to the numbers.
@MainActor
enum PlaceNames {
    private static var cache: [String: String] = [:]
    private static let geocoder = CLGeocoder()

    static func name(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.3f_%.3f", coordinate.latitude, coordinate.longitude)
        if let hit = cache[key] { return hit }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }

        // Town and state is what someone would actually say. The street is more
        // precision than a driving fix has, and the country is noise when every
        // plate in the game is from this continent.
        //
        // The state has to be there. Without that test the geocoder's answer for a
        // fix out at sea — a bare region name like "Southwest" — reads as a place
        // you drove through, which is worse than the coordinates it replaced.
        let name: String
        if let state = mark.administrativeArea {
            name = [mark.locality ?? mark.subAdministrativeArea, state]
                .compactMap { $0 }
                .joined(separator: ", ")
        } else if let water = mark.ocean ?? mark.inlandWater {
            name = water
        } else {
            return nil
        }
        cache[key] = name
        return name
    }
}

// MARK: - A whole stop

/// Every plate logged at one fix, as a list you can search.
///
/// The map can draw a handful of plates at a place and stay readable. It cannot draw
/// fifty, and a column of ten is taller than the screen — so past
/// `TrailBundleView.listThreshold` the stop stops being a shape and becomes this.
///
/// Chronological, because that is the thing the map cannot show: at a stop, the order
/// is the only story there is. The search field earns its place at exactly the sizes
/// that sent you here — nobody scrolls fifty rows looking for Rhode Island.
struct TrailStopSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pins: [TrailPin]

    @State private var query = ""
    @State private var place: String?

    private var ordered: [TrailPin] { pins.sorted { $0.spottedAt < $1.spottedAt } }

    private var matches: [TrailPin] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter {
            $0.code.localizedCaseInsensitiveContains(trimmed)
                || ($0.plate?.name ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(matches) { pin in
                        NavigationLink { TrailPinDetailBody(pin: pin) } label: { row(pin) }
                    }
                } header: {
                    Text(query.isEmpty
                         ? span
                         : "\(matches.count) of \(pins.count)")
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(nil)
                }

                if matches.isEmpty {
                    Text("No plate here matches \u{201C}\(query)\u{201D}.")
                        .font(.plates(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .searchable(text: $query, prompt: "Find a plate at this stop")
            .navigationTitle(place ?? "\(pins.count) plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { place = await PlaceNames.name(for: pins[0].coordinate) }
    }

    /// "12 plates · 4:02 to 4:19 PM" — the shape of the stop in one line.
    private var span: String {
        let count = "\(pins.count) plates"
        guard let first = ordered.first, let last = ordered.last else { return count }
        let day = first.spottedAt.formatted(.dateTime.month(.abbreviated).day())
        let from = first.spottedAt.formatted(date: .omitted, time: .shortened)
        let to = last.spottedAt.formatted(date: .omitted, time: .shortened)
        return from == to ? "\(count) \u{00B7} \(day), \(from)"
                          : "\(count) \u{00B7} \(day), \(from)\u{2013}\(to)"
    }

    private func row(_ pin: TrailPin) -> some View {
        HStack(spacing: 12) {
            if let plate = pin.plate {
                PlateTile(plate: plate, isFound: true, rarity: pin.rarity)
                    .frame(width: 58)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pin.plate?.name ?? pin.code)
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                // Time only. Who called it belongs on the plate's own card, not on
                // every row of a list — twelve name tags down one column is a colour
                // chart, and it competes with the plate art for the same glance.
                Text(pin.spottedAt.formatted(date: .omitted, time: .shortened))
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: 6)

            Text(pin.tier.label)
                .font(Theme.PlateFont.condensed(12))
                .foregroundStyle(pin.tier.color)
        }
        .padding(.vertical, 3)
    }
}

/// Who called it.
///
/// This was a coloured dot beside a name, and a 6pt dot is not a design — it reads as
/// a bullet point that happens to be green, and against a row of muted grey text the
/// player palette's greens and oranges look like status lights rather than people.
///
/// A filled capsule with the name inside it does the same job with none of that: the
/// colour is the whole shape rather than a speck, dark ink keeps it legible on every
/// one of the six player colours, and it reads as a tag with somebody's name on it —
/// which is what the player markers are everywhere else in the app.
struct SpotterChip: View {
    let name: String
    let colorIndex: Int
    var size: CGFloat = 12

    var body: some View {
        Text(name)
            .font(.plates(size: size, weight: .bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, size * 0.62)
            .padding(.vertical, size * 0.26)
            .background(Capsule().fill(Theme.playerColor(colorIndex)))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.5))
    }
}
