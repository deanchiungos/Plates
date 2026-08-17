import SwiftUI
import MapKit

/// A place picked on the map, or typed freehand.
///
/// The coordinate is optional on purpose: someone typing "Grandma's" should still
/// get a trip named for it. They just do not get geographic rarity until they pin
/// a real place, and the model falls back to national defaults.
struct Place: Equatable {
    var name: String = ""
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isPinned: Bool { coordinate != nil }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Wraps `MKLocalSearchCompleter`, which is delegate-based and pre-dates Swift
/// concurrency, in something a SwiftUI view can observe.
///
/// Note this needs no location permission — completions are unbiased by the user's
/// position, which is right here anyway: you are usually planning a trip to
/// somewhere you are not.
@MainActor
final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Addresses would drown the list in house numbers. A road trip runs between
        // towns and landmarks, so that is all we ask for.
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() { suggestions = [] }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(5))
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.suggestions = [] }
    }

    /// A completion is only a piece of text — resolving it to a coordinate is a
    /// second network round trip.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Place {
        var place = Place(name: completion.title)
        let response = try? await MKLocalSearch(request: .init(completion: completion)).start()
        if let item = response?.mapItems.first {
            let c = item.placemark.coordinate
            place.latitude = c.latitude
            place.longitude = c.longitude
        }
        return place
    }
}

/// A text field that drops a list of map suggestions beneath itself.
struct PlaceField: View {
    let placeholder: String
    let symbol: String
    @Binding var place: Place
    /// Read-only: still says where the trip went, but nothing about it can be
    /// changed. Greyed rather than hidden, because the route is part of the record
    /// and an archived trip is a thing you look at.
    var isLocked = false

    @StateObject private var completer = PlaceCompleter()
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var suppressLookup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isLocked ? Theme.inkMuted.opacity(0.55)
                                              : Theme.route.opacity(0.7))
                    .frame(width: 17)

                TextField(placeholder, text: $text)
                    .font(.plates(size: 17))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(isLocked)
                    .foregroundStyle(isLocked ? Theme.inkMuted : Theme.ink)

                if place.isPinned {
                    // Confirms the difference that matters: a pinned place drives
                    // rarity and the map, typed text does not.
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 15))
                        // Muted rather than removed on a locked field. At full
                        // strength it was the brightest thing on a grey form and read
                        // as the one control still live.
                        .foregroundStyle(Theme.route.opacity(isLocked ? 0.4 : 1))
                        .transition(.scale.combined(with: .opacity))
                } else if !text.isEmpty, !isLocked {
                    // Clearing is an edit, so a locked field does not offer it. The
                    // pin marker above stays: it says the rarity was scored against a
                    // real place rather than typed text, which is part of the record.
                    Button {
                        text = ""
                        place = Place()
                        completer.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkMuted.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // Filled with the paper rather than the card white. A white box
                    // on cream reads as somewhere to type; the same box in the
                    // background color reads as a label, which is what it now is.
                    .fill(isLocked ? Theme.unfound.opacity(0.55) : Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(focused ? Theme.route.opacity(0.5) : Theme.line,
                                      lineWidth: focused ? 1.5 : 1))
            )

            if focused, !completer.suggestions.isEmpty {
                suggestionList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: completer.suggestions.count)
        .animation(.snappy(duration: 0.2), value: place.isPinned)
        .onAppear { text = place.name }
        .onChange(of: text) { _, new in
            // Selecting a suggestion writes the title back into the field, which
            // would otherwise immediately re-open the dropdown underneath it.
            if suppressLookup {
                suppressLookup = false
                return
            }
            // Editing after pinning invalidates the pin — the coordinate belongs to
            // the old text, and silently keeping it would put the map somewhere the
            // field no longer says.
            if place.isPinned, new != place.name { place = Place(name: new) }
            else { place.name = new }
            completer.update(query: new)
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(completer.suggestions, id: \.self) { suggestion in
                Button {
                    select(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.plates(size: 14.5, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.plates(size: 11.5))
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if suggestion != completer.suggestions.last {
                    Divider().padding(.leading, 13)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.12), radius: 10, y: 4)
        )
        .padding(.top, 5)
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        suppressLookup = true
        text = suggestion.title
        completer.clear()
        focused = false
        Haptics.selection()

        Task {
            let resolved = await completer.resolve(suggestion)
            // Guard against a slow lookup landing after the user has moved on and
            // typed something else.
            if text == suggestion.title { place = resolved }
        }
    }
}

/// The two pins, once both ends are set. Read-only: it is a confirmation that the
/// app understood where you meant, not a map you are meant to navigate with.
///
/// Rendered with `MKMapSnapshotter` rather than a live `Map`. A `Map` is a
/// GPU-backed `CAMetalLayer`, and putting one inside a scrolling form that fades it
/// in made the layer get measured at zero size mid-transition — which produced
/// `setDrawableSize width=0 height=0`, then a Metal validation assertion when the
/// drawable was destroyed while the command buffer still held it, and a visible
/// stall on the Trips tab. A snapshot is a plain image: no Metal layer, no GPU cost
/// while scrolling, nothing to tear down. Since the map was never interactive, this
/// gives up nothing.
struct RouteMap: View {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D

    private static let height: CGFloat = 170

    @State private var snapshot: MKMapSnapshotter.Snapshot?
    @State private var failed = false

    /// The driving route, as coordinates. Empty when MapKit could not find one —
    /// which is the normal answer for Honolulu to anywhere, not an error.
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeSummary: String?
    /// Which pair of endpoints `routeCoords` was fetched for, so a width change
    /// re-snapshots without asking MapKit for directions again.
    @State private var routedEndpoints: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot.image)
                        .resizable()
                        .scaledToFill()

                    routeLine(on: snapshot)

                    pin(systemImage: "flag.fill", tint: Theme.route,
                        at: snapshot.point(for: start))
                    pin(systemImage: "flag.checkered", tint: Theme.paint,
                        at: snapshot.point(for: end))

                    if let routeSummary {
                        // Bottom right: the Apple Maps mark is burned into the
                        // bottom left of the snapshot and must not be covered.
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text(routeSummary)
                                    .font(.plates(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.92)))
                                    .shadow(color: Theme.ink.opacity(0.18), radius: 3, y: 1)
                            }
                        }
                        .padding(7)
                    }

                    // No attribution overlay here: the snapshot image already has
                    // the Apple Maps mark burned into it, and adding one drew it
                    // twice.
                } else {
                    Theme.ground
                    if failed {
                        Label("Map unavailable", systemImage: "map")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkMuted)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(width: geo.size.width, height: Self.height)
            .task(id: TaskKey(width: geo.size.width, start: start, end: end)) {
                await load(width: geo.size.width)
            }
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    /// Re-snapshots when the width or either endpoint changes, and not otherwise —
    /// a snapshot is a network round trip, so it must not fire on every re-render.
    private struct TaskKey: Equatable {
        let width: CGFloat
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D

        static func == (a: TaskKey, b: TaskKey) -> Bool {
            a.width == b.width
                && a.start.latitude == b.start.latitude
                && a.start.longitude == b.start.longitude
                && a.end.latitude == b.end.latitude
                && a.end.longitude == b.end.longitude
        }
    }

    /// The road the trip actually follows, drawn over the snapshot.
    ///
    /// A white casing under the blue keeps it readable where it crosses motorways
    /// and coastline, which is the same trick every map app uses.
    ///
    /// When MapKit could not route between the two points — an island, or two
    /// places with no road between them — it falls back to a dashed straight line.
    /// Dashed rather than solid on purpose: a solid line would assert a road that
    /// does not exist.
    @ViewBuilder
    private func routeLine(on snapshot: MKMapSnapshotter.Snapshot) -> some View {
        if routeCoords.count > 1 {
            let path = Path { p in
                let points = routeCoords.map { snapshot.point(for: $0) }
                p.move(to: points[0])
                for point in points.dropFirst() { p.addLine(to: point) }
            }
            path.stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            path.stroke(Theme.route,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
        } else {
            Path { p in
                p.move(to: snapshot.point(for: start))
                p.addLine(to: snapshot.point(for: end))
            }
            .stroke(Theme.route.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [5, 5]))
        }
    }

    private func pin(systemImage: String, tint: Color, at point: CGPoint) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: Theme.ink.opacity(0.35), radius: 3, y: 1)
            .position(point)
    }

    private func load(width: CGFloat) async {
        guard width > 1 else { return }

        // Directions first: the snapshot has to be framed around the road, not the
        // two endpoints. A route that detours north around a mountain range would
        // otherwise run off the top of a map framed on its ends.
        let key = endpointKey
        if routedEndpoints != key {
            let found = await fetchRoute()
            guard !Task.isCancelled else { return }
            routeCoords = found?.coords ?? []
            routeSummary = found?.summary
            routedEndpoints = key
        }

        let result = await MapSnapshot.take(
            of: routeCoords.count > 1 ? region(fitting: routeCoords) : region,
            size: CGSize(width: width, height: Self.height))

        guard !Task.isCancelled else { return }
        if let result { snapshot = result } else { failed = true }
    }

    /// Framed to hold both pins with a margin, and floored so two places in the
    /// same town do not zoom to street level.
    ///
    /// The margin is thin (1.15) because MapKit already grows whichever span is
    /// needed to match the view's aspect ratio — a wide strip like this one. At 1.6
    /// a Newark-to-San-Diego route came out showing Canada to Colombia.
    private var region: MKCoordinateRegion {
        let midLat = (start.latitude + end.latitude) / 2
        let midLon = (start.longitude + end.longitude) / 2
        // Longitude gets the wider margin: in a strip this shape MapKit grows the
        // latitude span to match the aspect ratio, so vertical padding comes free
        // while horizontal is exactly what is asked for — and at 1.15 the endpoint
        // pins were half off the left and right edges.
        let spanLat = max(abs(start.latitude - end.latitude) * 1.15, 0.6)
        let spanLon = max(abs(start.longitude - end.longitude) * 1.4, 0.6)
        return MKCoordinateRegion(
            center: .init(latitude: midLat, longitude: midLon),
            span: .init(latitudeDelta: min(spanLat, 120), longitudeDelta: min(spanLon, 160))
        )
    }

    /// Framed around the whole road, with the same asymmetric margin as the
    /// endpoint framing so the pins do not sit on the edges.
    private func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return region }

        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: min(max((maxLat - minLat) * 1.2, 0.6), 120),
                        longitudeDelta: min(max((maxLon - minLon) * 1.35, 0.6), 160))
        )
    }

    private var endpointKey: String {
        "\(start.latitude),\(start.longitude)>\(end.latitude),\(end.longitude)"
    }

    /// Through `RouteCache`, which the share poster also uses — the two were each
    /// asking MapKit for the same road, so opening a trip's record and then sharing
    /// it fetched the whole route twice.
    private func fetchRoute() async -> (coords: [CLLocationCoordinate2D], summary: String)? {
        guard let found = await RouteCache.shared.directions(from: start, to: end) else {
            return nil
        }
        return (found.path, found.summary)
    }
}
