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
    /// Whether the best find is worth painting. See the note where it is written.
    var bestIsRemarkable: Bool = false

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
    #if DEBUG
    /// Set while a debug harness is running against a throwaway store.
    ///
    /// The sidecar lives at one fixed path in the App Group and takes no store
    /// parameter, so a `write` driven by fixture data overwrites the real home
    /// screen and reloads the widget to show it. `PartyMergeCheck` has always called
    /// `TripClosing`, which rebuilds this — and it now also runs `PartyMerge`, which
    /// does too — so on a real phone the check would replace somebody's widget with
    /// the fixture's trip. `AppDefaults` solved the same problem for preferences by
    /// swapping the store; this file has no equivalent, so the harness suspends it.
    nonisolated(unsafe) static var isSuspended = false
    #endif

    /// A rebuild is wanted, at some point this turn of the run loop.
    ///
    /// `write` is a three-table fetch, a lifetime `PlateBook`, a rarest-find and a
    /// read of the sidecar to compare — cheap enough for a tap and not for a loop.
    /// The paths that arrive from elsewhere are loops: `SharedBookSync.pull` calls
    /// the merge once per CloudKit page and a first sync of a full book is several
    /// pages, and `PartyMerge` runs once per envelope, which in a four-phone car is
    /// once per plate anybody calls plus every relay. Each of those did the whole
    /// rebuild, on the main actor, for a file that only needs its final value.
    ///
    /// Coalesced rather than throttled, so the last state always wins and nothing
    /// has to guess a delay. The trailing edge is what matters here: nobody is
    /// looking at the home screen during a merge.
    @MainActor
    static func setNeedsWrite(from context: ModelContext) {
        #if DEBUG
        // Checked at the ask, not only at the write. A deferred write scheduled
        // during `-partyMergeCheck` would land after the run's `defer` had cleared
        // the flag, and put fixture data on the real home screen — which is the one
        // thing `isSuspended` exists to prevent.
        if isSuspended { return }
        #endif
        pending = context
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor in
            scheduled = false
            guard let context = pending else { return }
            pending = nil
            write(from: context)
        }
    }

    @MainActor private static var scheduled = false
    @MainActor private static var pending: ModelContext?

    @MainActor
    static func write(from context: ModelContext) {
        #if DEBUG
        if isSuspended { return }
        #endif
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        let lifetime = PlateBook(sightings: sightings)

        let target = PlaySelection.current(trips: trips, books: books)
        let current = target?.collection

        // Newest first, so "recently finished" means the drive you just got back
        // from rather than whichever one the store happened to return first.
        let finished = trips.filter { !$0.isActive }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }

        // What the widget will actually be describing, which is not always what is
        // being filled. The headline falls back to the last finished trip and then
        // to the lifetime total, and the album and the rarest find were both being
        // taken from the active collection alone — so on a phone with no open trip
        // and no book, the medium widget drew "LAST TRIP / 24 of 50" beside fifty
        // grey cells, and the caption under the bar rendered nothing at all. Both
        // now follow the same subject the headline does.
        let subject: (any PlateCollection)? = current ?? finished.first
        let seen = subject?.seenCodes ?? Set(sightings.map(\.plateCode))

        // Scored the way the collection itself scores, so a trip's rarest is judged
        // against its own route rather than a national average it never used. The
        // lifetime tier has no route of its own, so it is scored nationally.
        // Through the index, not `collection.rarity(of:)` per code, which filters
        // every sighting the collection has once for each code. This function is
        // called from the party merge, both shared-book merge exits and both play
        // selectors, so on a phone in a party it runs whenever anybody in the car
        // calls a plate.
        let best = subject.map { collection in
            let index = collection.plateIndex()
            return rarestPlate(in: seen) { collection.rarity(of: $0, using: index) }
        } ?? rarestPlate(in: seen) { PlateRarity.rarity($0, on: nil) }

        let snapshot = WidgetData(
            tripName: current?.name,
            tripStates: current?.statesFound ?? 0,
            targetKind: (target?.isBook ?? false) ? "book" : "trip",
            tripLastPlate: current?.allSightings.map(\.spottedAt).max(),
            foundCodes: seen.sorted(),
            bestCode: best?.0,
            // Resolved here, where `RarityTier` is in scope. The widget target
            // cannot import it and was inventing its own `>= 8` cut, which matches
            // no band — epic is 7...8 — so an 8 was painted remarkable on the home
            // screen while the grid called it epic, and mythic came out the same
            // amber as an epic. Everything on this sidecar is a number the app has
            // already worked out; this is one more.
            bestIsRemarkable: (best?.1).map { RarityTier.forRarity($0) >= .epic } ?? false,
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
