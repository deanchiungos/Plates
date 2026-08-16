import CoreLocation
import Foundation
import MapKit

/// Driving directions, asked for once.
///
/// Two places want the same road: the trip editor draws a preview of it, and the
/// share poster draws it again. Both were calling `MKDirections` independently, so
/// opening a trip's record and then sharing it fetched Newark-to-San-Diego twice —
/// and that call is nearly all of the three seconds a poster took, because it is a
/// network round trip rather than any work the phone is doing.
///
/// Kept on disk, not just in memory. Sharing is a once-in-a-while act: the cache
/// that matters is the one still warm tomorrow, not the one that lasts until the app
/// is swapped out. It is the same sidecar shape as `PartyLedger` — a small JSON file
/// in Application Support, no `@Model`, no CloudKit record type, nothing synced.
/// Losing it costs one round trip.
///
/// A route is not quite a fact about the world — roads close, and MapKit reroutes —
/// but it is stable enough over the life of a trip, and the alternative is making
/// somebody wait three seconds to send a picture of a drive they already took.
@MainActor
final class RouteCache {

    static let shared = RouteCache(url: RouteCache.defaultURL)

    struct Directions: Codable, Equatable {
        /// Already thinned. A cross-country route arrives as thousands of points and
        /// most of them land on the same pixel at any size this app draws.
        var coordinates: [Point]
        /// "2,748 mi · 38 hr 50 min", for the editor's caption. The poster has no
        /// room for it, but caching per-caller would mean two entries for one road.
        var summary: String
        var storedAt: Date

        struct Point: Codable, Equatable {
            var lat: Double
            var lon: Double
            var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
        }

        var path: [CLLocationCoordinate2D] { coordinates.map(\.coordinate) }
    }

    private let url: URL?
    private var entries: [String: Directions] = [:]
    /// In-flight requests, so two callers asking at the same moment — which is
    /// exactly what a share tapped from an open trip editor looks like — share one
    /// round trip instead of racing.
    private var pending: [String: Task<Directions?, Never>] = [:]

    /// Enough for a year of trips. Past this the oldest goes, because an unbounded
    /// cache of a thing nobody deletes is a slow leak.
    private static let limit = 40

    init(url: URL?) {
        self.url = url
        load()
    }

    // MARK: - Asking

    func directions(from start: CLLocationCoordinate2D,
                    to end: CLLocationCoordinate2D) async -> Directions? {
        let key = Self.key(start, end)
        if let hit = entries[key] { return hit }
        if let running = pending[key] { return await running.value }

        let task = Task<Directions?, Never> { await Self.fetch(from: start, to: end) }
        pending[key] = task
        let found = await task.value
        pending[key] = nil

        if let found {
            entries[key] = found
            prune()
            save()
        }
        return found
    }

    /// The road for these two ends **if it is already known**, without asking for it.
    ///
    /// For `PlateRarity`, which is synchronous, runs inside a `View` body, and is
    /// asked sixty-five times per render. It cannot await a network round trip and it
    /// must not start one: rarity has a correct answer without the road — the straight
    /// segment — and the road only sharpens it.
    ///
    /// So this reports what the disk cache already holds and nothing more. A trip
    /// whose directions have never been fetched scores off the straight line until
    /// something that *can* wait — the editor preview, the share poster — fetches them
    /// and the next render picks them up.
    func knownPath(from start: CLLocationCoordinate2D,
                   to end: CLLocationCoordinate2D) -> [PlateRarity.Waypoint] {
        (entries[Self.key(start, end)]?.coordinates ?? [])
            .map { .init(lat: $0.lat, lon: $0.lon) }
    }

    /// Rounded to about a hundred metres. The endpoints come from a place the user
    /// tapped in a picker, so they are already identical between the two callers —
    /// but a coordinate that arrived by a different route should not miss the cache
    /// over the eighth decimal place.
    private static func key(_ start: CLLocationCoordinate2D,
                            _ end: CLLocationCoordinate2D) -> String {
        func round(_ value: Double) -> String { String(format: "%.3f", value) }
        return "\(round(start.latitude)),\(round(start.longitude))>"
             + "\(round(end.latitude)),\(round(end.longitude))"
    }

    private func prune() {
        guard entries.count > Self.limit else { return }
        let doomed = entries.sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(entries.count - Self.limit)
        for (key, _) in doomed { entries.removeValue(forKey: key) }
    }

    // MARK: - Fetching

    /// Nil is a legitimate answer, not a failure: there is no road from Honolulu to
    /// anywhere, and both callers draw a dashed line when they get one.
    ///
    /// Deliberately not cached. A nil today may be a route tomorrow — the request
    /// can fail for no signal as easily as for no road — and remembering "no" would
    /// turn a dead zone into a permanent one.
    private static func fetch(from start: CLLocationCoordinate2D,
                              to end: CLLocationCoordinate2D) async -> Directions? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }

        let line = route.polyline
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: line.pointCount)
        line.getCoordinates(&coords, range: NSRange(location: 0, length: line.pointCount))

        // Thinned once, here, at the finer of the two callers' needs. The first and
        // last are always kept so the line still meets both pins.
        let maxPoints = 400
        if coords.count > maxPoints {
            // Rounded up, not down. Integer division gave a stride of 1 for anything
            // from 401 to 799 points, so the thinning did nothing at all across that
            // whole band and the cache held up to twice the cap it documents — an
            // array rebuilt on every read of `Trip.route`, which is every render of
            // the grid.
            let step = (coords.count + maxPoints - 1) / maxPoints
            var thinned = stride(from: 0, to: coords.count, by: step).map { coords[$0] }
            // Both halves of the coordinate. Comparing latitude alone kept the last
            // point only when the road happened to end at a different latitude, so a
            // final leg running east or west — the whole width of Texas, say — ended
            // the drawn line wherever the stride stopped, short of the pin, on the
            // poster map and in the rarity model both.
            if let last = coords.last, let end = thinned.last,
               end.latitude != last.latitude || end.longitude != last.longitude {
                thinned.append(last)
            }
            coords = thinned
        }

        return Directions(coordinates: coords.map { .init(lat: $0.latitude, lon: $0.longitude) },
                          summary: summarise(route),
                          storedAt: Date())
    }

    private static func summarise(_ route: MKRoute) -> String {
        let distance = MKDistanceFormatter()
        distance.unitStyle = .abbreviated

        let hours = Int(route.expectedTravelTime) / 3600
        let minutes = (Int(route.expectedTravelTime) % 3600) / 60
        let time = hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
        return "\(distance.string(fromDistance: route.distance)) \u{00B7} \(time)"
    }

    // MARK: - Disk

    private static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Routes.json")
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: Directions].self, from: data)
        else { return }
        entries = stored
    }

    /// Failures are swallowed. The worst case is asking MapKit again.
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
