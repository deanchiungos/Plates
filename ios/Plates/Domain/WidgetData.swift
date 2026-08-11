import Foundation
import SwiftData

/// What the home screen is allowed to know.
///
/// A widget runs in its own process and can only read what the app has deliberately
/// put somewhere shared. The obvious way to do that is to move the SwiftData store
/// into an App Group so both sides open the same file — and that is the wrong trade
/// here. It would mean migrating every existing install's `default.store`, with
/// CloudKit mirroring attached to it, to get a number onto a home screen. A failed
/// migration costs somebody their plates; a failed sidecar costs a stale widget.
///
/// So the app writes this instead: a few dozen bytes of already-computed answers,
/// the same shape as `PartyLedger` and `PartyTombstones`. The store never moves.
///
/// **Falls back to the app's own container when the App Group is unavailable.** The
/// entitlement needs the capability enabled on the developer account, and a build
/// signed without it should degrade to a widget that shows nothing rather than an
/// app that cannot save.
struct WidgetData: Codable, Equatable {

    static let group = "group.com.eggeppel.plates"
    private static let filename = "Widget.json"

    /// The trip being filled, if one is. Nil is a normal state — plenty of people
    /// only ever keep a book — and the widget shows lifetime totals instead.
    var tripName: String?
    var tripStates: Int
    /// When that trip last took a plate, for "3 days ago" without the widget having
    /// to reach into the store to work it out.
    var tripLastPlate: Date?

    /// The most recently finished trip, for the gap between drives.
    var lastTripName: String?
    var lastTripStates: Int

    /// The evergreen fallback: everything ever spotted on this phone.
    var lifetimeStates: Int
    var lifetimePlates: Int

    var updatedAt: Date

    static let stateTotal = 50

    // MARK: - Writing

    /// Rebuilt from the store rather than accumulated, for the same reason every
    /// other derived number in this app is: `Sighting` is the only stored fact, and
    /// a counter kept alongside it is a second source of truth waiting to disagree.
    @MainActor
    static func write(from context: ModelContext) {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        let lifetime = PlateBook(sightings: sightings)

        let current = TripSelection.current(
            from: trips,
            id: UserDefaults.standard.string(forKey: TripSelection.key) ?? "")

        // Newest first, so "recently finished" means the drive you just got back
        // from rather than whichever one the store happened to return first.
        let finished = trips.filter { !$0.isActive }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        let snapshot = WidgetData(
            tripName: current?.name,
            tripStates: current?.statesFound ?? 0,
            tripLastPlate: current?.allSightings.map(\.spottedAt).max(),
            lastTripName: finished.first?.name,
            lastTripStates: finished.first?.statesFound ?? 0,
            lifetimeStates: lifetime.statesFound,
            lifetimePlates: lifetime.totalFound,
            updatedAt: Date())

        snapshot.save()
    }

    private func save() {
        guard let url = Self.url,
              let data = try? JSONEncoder().encode(self) else { return }
        // Only when something actually changed. A widget reload is not free, and
        // rewriting an identical file on every launch would spend that for nothing.
        if let existing = Self.read(), existing.matches(self) { return }
        try? data.write(to: url, options: .atomic)
        WidgetRefresh.request()
    }

    /// Everything except the timestamp. Two snapshots taken a minute apart with the
    /// same plates on them are the same news.
    private func matches(_ other: WidgetData) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    // MARK: - Reading

    static func read() -> WidgetData? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    /// The shared container if the entitlement is in place, the app's own if not.
    /// A widget reading the second one finds nothing, which is the right failure:
    /// blank rather than wrong.
    static var url: URL? {
        let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)
        let base = shared ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
        return base?.appendingPathComponent(filename)
    }
}
