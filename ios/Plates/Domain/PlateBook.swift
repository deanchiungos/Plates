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
    }

    private(set) var entries: [String: Entry] = [:]

    init(sightings: [Sighting]) {
        var grouped: [String: [Sighting]] = [:]
        for s in sightings { grouped[s.plateCode, default: []].append(s) }

        for (code, list) in grouped {
            let sorted = list.sorted { $0.spottedAt < $1.spottedAt }
            guard let first = sorted.first, let last = sorted.last else { continue }
            entries[code] = Entry(firstSeen: first.spottedAt,
                                  lastSeen: last.spottedAt,
                                  count: sorted.count,
                                  firstIn: first.containerName)
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

        bestFind = codes
            .map { (code: $0, rarity: trip.rarity(of: $0)) }
            .max { $0.rarity < $1.rarity }
    }
}
