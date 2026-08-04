import Foundation

// Everything below is DERIVED from `sightings`.
//
// The web version stored a parallel `log` array, capped it at 30 entries, and then
// counted unique states from that log — so the headline "N/50" silently stopped
// rising at 30 and decayed as older sightings fell off the end. Nothing here caches
// or truncates: the only way to change a count is to add or remove a Sighting.
//
// Written against `PlateCollection` rather than `Trip`, so a book counts by exactly
// the same rules a trip does. There is no second implementation to keep in sync.

/// A total order over sightings: when it happened, then which one it was.
///
/// `spottedAt` alone is not a total order, and the difference matters as soon as
/// there is more than one device. Two phones in the same car can stamp the same
/// instant — the same *plate*, even, when two people call it together — and every
/// derivation that picks a single winner from a group ("who spotted this",  "what
/// was it first claimed at") would otherwise be resolving the tie by the order the
/// rows happen to sit in a relationship array. That order is an implementation
/// detail of the local store: it is not guaranteed to match between two devices
/// holding exactly the same sightings, so the same trip could show Mia's chip on
/// one phone and Theo's on the other, with neither of them wrong.
///
/// Breaking the tie on `id` fixes that for free. Ids are UUIDs minted where the
/// sighting was created, so they are unique, they travel with the record, and
/// every device computes the same winner from the same set without having to
/// agree on anything first.
///
/// On a single device this changes nothing anyone can observe: it only decides
/// cases that were previously undefined.
struct SightingOrder: Comparable {
    let at: Date
    let id: UUID

    init(_ sighting: Sighting) {
        at = sighting.spottedAt
        id = sighting.id
    }

    static func < (a: SightingOrder, b: SightingOrder) -> Bool {
        a.at == b.at ? a.id.uuidString < b.id.uuidString : a.at < b.at
    }
}

/// Every per-plate answer the grid needs, from one pass over `sightings`.
///
/// The accessors below — `hasSeen`, `sightingCount`, `spotter` — are each a full
/// scan, and two of them allocate an array on the way. That is fine for one
/// plate and quadratic for a grid: 65 tiles times three scans times every
/// sighting, rebuilt on every tap, every search keystroke, and every time a row
/// scrolls into view. It also degrades as the game goes on, because `n` is the
/// number of sightings. Build this once and every tile is a dictionary hit.
struct PlateIndex {
    struct Entry {
        var count = 0
        var latest: SightingOrder?
        var spotter: Player?
    }

    private let entries: [String: Entry]

    init(_ sightings: [Sighting]) {
        var built: [String: Entry] = [:]
        built.reserveCapacity(sightings.count)
        for s in sightings {
            var e = built[s.plateCode] ?? Entry()
            e.count += 1
            // Most recent spotter wins, matching `spotter(of:)` — and ties are
            // broken the same way there, so the chip on the tile and the answer
            // from the accessor cannot disagree. See `SightingOrder`.
            let order = SightingOrder(s)
            if e.latest.map({ order > $0 }) ?? true {
                e.latest = order
                e.spotter = s.player
            }
            built[s.plateCode] = e
        }
        entries = built
    }

    func has(_ code: String) -> Bool { entries[code] != nil }
    func count(_ code: String) -> Int { entries[code]?.count ?? 0 }
    func spotter(_ code: String) -> Player? { entries[code]?.spotter }
}

extension PlateCollection {

    var allSightings: [Sighting] { sightings ?? [] }

    /// See `PlateIndex`. Build once per grid, not once per tile.
    func plateIndex() -> PlateIndex { PlateIndex(allSightings) }

    /// Distinct plate codes seen on this trip, whatever the region.
    var seenCodes: Set<String> {
        Set(allSightings.map(\.plateCode))
    }

    func hasSeen(_ plate: Plate) -> Bool {
        allSightings.contains { $0.plateCode == plate.code }
    }

    func sightingCount(for plate: Plate) -> Int {
        allSightings.filter { $0.plateCode == plate.code }.count
    }

    /// Most recent spotter of a plate — drives the colour bar on a found tile.
    func spotter(of plate: Plate) -> Player? {
        allSightings
            .filter { $0.plateCode == plate.code }
            .max { SightingOrder($0) < SightingOrder($1) }?
            .player
    }

    // MARK: - Headline counts

    /// The numerator of "N/50". Bonus plates are deliberately excluded.
    var statesFound: Int {
        seenCodes.filter { Plate.plate(for: $0)?.region == .state }.count
    }

    var bonusFound: Int {
        seenCodes.filter { Plate.plate(for: $0)?.region.isBonus == true }.count
    }

    var provincesFound: Int {
        seenCodes.filter { Plate.plate(for: $0)?.region == .province }.count
    }

    /// Every distinct plate on the trip, states and bonus and provinces together —
    /// the honest "how much did we collect" number for the trips list, where the
    /// states-only headline would undersell a trip spent hunting provinces.
    var platesFound: Int { seenCodes.count }

    var progress: Double {
        Plate.stateTotal == 0 ? 0 : Double(statesFound) / Double(Plate.stateTotal)
    }

    // MARK: - Score

    var score: Int { score(for: nil) }

    /// Score for one player, or for everyone when `player` is nil.
    func score(for player: Player?) -> Int {
        let relevant = player == nil
            ? allSightings
            : allSightings.filter { $0.player?.id == player?.id }

        switch scoringMode {
        case .classic:
            // One point per distinct state. Bonus plates score nothing.
            let codes = Set(relevant.map(\.plateCode))
            return codes.filter { Plate.plate(for: $0)?.region == .state }.count

        case .weighted:
            // Rarity points, once per distinct plate. Bonus plates count here.
            let codes = Set(relevant.map(\.plateCode))
            return codes.reduce(0) { $0 + rarity(of: $1) }

        case .unlimited:
            // Every sighting scores what it was worth when it was logged, so two
            // sightings of the same plate a thousand miles apart can score
            // differently — which is right, they were different finds.
            return relevant.reduce(0) {
                $0 + ($1.rarityWhenSpotted ?? PlateRarity.rarity($1.plateCode, on: route))
            }
        }
    }

    /// What a plate is worth *on this trip*.
    ///
    /// Claimed plates keep the value they were claimed at; unclaimed ones track the
    /// car. That asymmetry is the whole design: rarity has to move as you drive or
    /// it is not describing the road out of the window, but a plate whose value
    /// silently dropped after you had already earned it would feel like being robbed.
    ///
    /// Falls back to the live model for sightings logged before rarity was recorded,
    /// and for every plate on a book, which has no route.
    func rarity(of code: String) -> Int {
        claimedRarity(of: code) ?? PlateRarity.rarity(code, on: route)
    }

    /// The rarity banked at the *first* claim of this plate. Later sightings do not
    /// revalue it — you cannot re-earn something you already have.
    ///
    /// Ties broken by `SightingOrder`, because this one feeds the *score*: two
    /// people calling the same plate at the same instant must not leave the two
    /// phones adding up different totals for the same trip.
    func claimedRarity(of code: String) -> Int? {
        allSightings
            .filter { $0.plateCode == code }
            .min { SightingOrder($0) < SightingOrder($1) }?
            .rarityWhenSpotted
    }

    /// What a plate is worth if you claim it *right now*. Used at the moment of the
    /// tap, to decide the celebration and to bank onto the sighting.
    func liveRarity(of code: String) -> Int {
        PlateRarity.rarity(code, on: route)
    }

    func rarity(of plate: Plate) -> Int { rarity(of: plate.code) }

    /// Per-player scores, highest first. Ties keep a stable order by join date.
    func standings(among players: [Player]) -> [(player: Player, score: Int)] {
        players
            .map { (player: $0, score: score(for: $0)) }
            .sorted {
                $0.score == $1.score
                    ? $0.player.joinedAt < $1.player.joinedAt
                    : $0.score > $1.score
            }
    }
}
