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

    /// Whatever is being filled — trip *or* book.
    ///
    /// It read `TripSelection` at first, which resolves only trips, so somebody
    /// filling a book saw a widget about a trip they were not playing. The app has
    /// one answer to "what am I collecting into" and it is `PlaySelection`; the
    /// widget has to ask the same question the Game screen does or it is describing a
    /// different app.
    var tripName: String?
    var tripStates: Int
    /// "TRIP" or "BOOK", so the widget can label what it is showing rather than
    /// calling a book a trip.
    var targetKind: String = "trip"
    /// When it last took a plate, for "3 days quiet" without the widget having to
    /// reach into the store to work it out.
    var tripLastPlate: Date?
    /// Every state code on it. The medium widget draws the album from this — the
    /// grid is the app's whole shape, and a widget that only counted was the same
    /// two numbers every other app shows.
    var foundCodes: [String] = []
    /// The rarest thing on it and what that was worth, which is the one number
    /// nobody else's home screen has.
    var bestCode: String?
    var bestRarity: Int = 0

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
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        let lifetime = PlateBook(sightings: sightings)

        let target = PlaySelection.current(trips: trips, books: books)
        let current = target?.collection

        // Scored the way the collection itself scores, so a trip's rarest is judged
        // against its own route rather than a national average it never used.
        let best = current.flatMap { collection in
            rarestPlate(in: collection.seenCodes, scoredBy: collection.rarity(of:))
        }

        // Newest first, so "recently finished" means the drive you just got back
        // from rather than whichever one the store happened to return first.
        let finished = trips.filter { !$0.isActive }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        let snapshot = WidgetData(
            tripName: current?.name,
            tripStates: current?.statesFound ?? 0,
            targetKind: (target?.isBook ?? false) ? "book" : "trip",
            tripLastPlate: current?.allSightings.map(\.spottedAt).max(),
            foundCodes: Array(current?.seenCodes ?? []).sorted(),
            bestCode: best?.0,
            bestRarity: best?.1 ?? 0,
            lastTripName: finished.first?.name,
            lastTripStates: finished.first?.statesFound ?? 0,
            lifetimeStates: lifetime.statesFound,
            lifetimePlates: lifetime.totalFound,
            updatedAt: Date())

        snapshot.save()
    }

    private func save() {
        // Only when something actually changed. A widget reload is not free, and
        // rewriting an identical file on every launch would spend that for nothing.
        if let existing = Self.read(), existing.matches(self) { return }
        Self.file.write(self)
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

    static func read() -> WidgetData? { file.read() }

    /// The same shape as the four sidecars in Application Support, and it earns the
    /// shared reader for a reason of its own: this file is read by the *widget*, in
    /// another process, and a version of the app that changed the shape of it would
    /// otherwise leave the widget silently drawing nothing.
    private static var file: SidecarFile {
        SidecarFile(url: url, holding: "the widget's copy of the game")
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
