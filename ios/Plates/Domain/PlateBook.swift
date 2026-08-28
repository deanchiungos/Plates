import Foundation

/// A read of the collection: which plates are in it, when they arrived, how often.
///
/// The same type serves one `Book` and the all-time record, because the difference
/// between them is only which sightings you hand it. Nothing is stored — `Sighting`
/// remains the only fact, so a page of the book cannot drift from what happened.
struct PlateBook {

    struct Entry {
        let firstSeen: Date
        let lastSeen: Date
        let count: Int
        /// The trip or book it was first logged against. Nil for an orphan left
        /// behind by a deleted book, which is missing provenance, not a missing find.
        let firstIn: String?
        /// Everyone who claimed it, earliest first, each counted once.
        ///
        /// Carried because `count` alone cannot tell "you saw it four times" from
        /// "four people each saw it once", and a book drew both as ×4 — which is
        /// nonsense to anybody who logged it exactly once and knows it.
        let spotters: [Player]
    }

    private(set) var entries: [String: Entry] = [:]

    init(sightings: [Sighting]) {
        var grouped: [String: [Sighting]] = [:]
        for s in sightings { grouped[s.plateCode, default: []].append(s) }

        for (code, list) in grouped {
            // Through `SightingOrder`, whose tie-break is an id: `sorted(by:)` is not
            // a stable sort, so two claims at the same instant could come out either
            // way on either run. `PlateIndex` orders its claimants the same way, and
            // the two draw the same people on two screens.
            let sorted = list.sorted { SightingOrder($0) < SightingOrder($1) }
            guard let first = sorted.first, let last = sorted.last else { continue }
            // De-duplicated in place rather than through a Set, so the order stays
            // "who got there first" — which is the order the tile draws them in.
            var spotters: [Player] = []
            for player in sorted.compactMap(\.player)
            where !spotters.contains(where: { $0.id == player.id }) {
                spotters.append(player)
            }

            entries[code] = Entry(firstSeen: first.spottedAt,
                                  lastSeen: last.spottedAt,
                                  count: sorted.count,
                                  firstIn: first.containerName,
                                  spotters: spotters)
        }
    }

    // MARK: - Lookups

    func entry(for code: String) -> Entry? { entries[code] }
    func has(_ plate: Plate) -> Bool { entries[plate.code] != nil }

    var foundCodes: Set<String> { Set(entries.keys) }

    func found(in plates: [Plate]) -> Int {
        plates.filter { entries[$0.code] != nil }.count
    }

    var statesFound: Int { found(in: Plate.states) }
    var totalFound: Int { entries.count }

    /// Every sighting ever, repeats included — the "you have logged 412 plates"
    /// number, as distinct from "you have collected 47 of 65".
    var totalSightings: Int { entries.values.reduce(0) { $0 + $1.count } }

    var progress: Double {
        Plate.stateTotal == 0 ? 0 : Double(statesFound) / Double(Plate.stateTotal)
    }

    /// The most recent additions, newest first — what the book shows as "lately".
    func recent(_ limit: Int) -> [(code: String, entry: Entry)] {
        entries.map { (code: $0.key, entry: $0.value) }
            .sorted { $0.entry.firstSeen > $1.entry.firstSeen }
            .prefix(limit)
            .map { $0 }
    }

    var firstEverSighting: Date? { entries.values.map(\.firstSeen).min() }
}

// MARK: - Trip comparison

/// One row of the trip history table.
///
/// Assembled per trip rather than queried per column so the numbers on a row can
/// never come from different points in time.
struct TripSummary: Identifiable {
    let id: UUID
    let name: String
    let route: String?
    let started: Date
    let ended: Date?
    let days: Int
    let statesFound: Int
    let platesFound: Int
    let sightings: Int
    /// The rarest plate found, scored against that trip's own route — a trip's best
    /// find only means anything relative to where that trip went.
    let bestFind: (code: String, rarity: Int)?

    /// `@MainActor` because it reads a SwiftData model, which is main-actor state,
    /// and because the rarity it works out is. It was already only ever built from a
    /// view body; the annotation says so rather than leaving it to be true by luck.
    @MainActor
    init(trip: Trip) {
        let all = trip.allSightings
        let codes = Set(all.map(\.plateCode))

        id = trip.id
        name = trip.name
        route = trip.routeLabel
        started = trip.startedAt
        ended = trip.endedAt
        days = trip.dayNumber
        statesFound = trip.statesFound
        platesFound = codes.count
        sightings = all.count

        // Through the index, like the grid, the poster and the widget. Passed as a
        // function value, `trip.rarity(of:)` also silently dropped its `@MainActor`
        // — which the compiler now warns about and Swift 6 will refuse.
        let index = trip.plateIndex()
        bestFind = rarestPlate(in: codes) { trip.rarity(of: $0, using: index) }
    }
}
