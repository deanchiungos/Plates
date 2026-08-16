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
        /// Everyone who has claimed this plate, in the order they first did.
        /// One name under the old rules; several once a party lets more than one
        /// person bank the same state.
        var claimants: [Player] = []
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
            if let claimant = s.player, !e.claimants.contains(where: { $0.id == claimant.id }) {
                e.claimants.append(claimant)
            }
            built[s.plateCode] = e
        }
        entries = built
    }

    func has(_ code: String) -> Bool { entries[code] != nil }
    func count(_ code: String) -> Int { entries[code]?.count ?? 0 }
    func spotter(_ code: String) -> Player? { entries[code]?.spotter }
    func claimants(_ code: String) -> [Player] { entries[code]?.claimants ?? [] }
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

    /// Most recent spotter of a plate — drives the color bar on a found tile.
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

    /// The numerator of "N / 2" under Bonus plates — D.C. and Puerto Rico, and
    /// nothing else.
    ///
    /// Counted against `Plate.bonusCodes`, the very array the section draws, so the
    /// number and the tiles beneath it cannot disagree. This used to ask
    /// `region.isBonus`, which means `region != .state` and so counted all thirteen
    /// provinces: a full collection reported "15 / 2 found".
    var bonusFound: Int {
        seenCodes.filter(Plate.bonusCodes.contains).count
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
            //
            // Scored from the sightings in hand rather than through `rarity(of:)`,
            // which answers the *collection's* question — what is this plate worth on
            // this trip — and therefore always the first claim's value. That is right
            // for the trip and wrong for a person: under shared claims four people can
            // each bank Montana, and crediting them all with whatever the earliest one
            // happened to be sitting next to takes back the thing shared claims
            // promises. Grouping by code keeps "once per distinct plate" intact.
            //
            // For the whole collection (`player == nil`) `relevant` is every sighting,
            // so the earliest row per code is the first claim and this is exactly what
            // `claimedRarity` returned — same answer, one pass instead of one full
            // scan per code.
            return Dictionary(grouping: relevant, by: \.plateCode)
                .reduce(0) { total, entry in
                    let earliest = entry.value.min { SightingOrder($0) < SightingOrder($1) }
                    return total + (earliest?.rarityWhenSpotted ?? rarity(of: entry.key))
                }

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

    /// The people actually on this collection.
    ///
    /// Not the same thing as "every `Player` in the store", and the difference is a
    /// bug that shipped. The store's players used to *be* the car — a roster you
    /// typed in by hand — so scoring against all of them was right. A party changed
    /// that: joining one merges the other phones' players into your store and keeps
    /// them, permanently and on purpose, because a trip's standings have to still
    /// render years later. Score against the whole table after that and every new
    /// trip opens with a strip of everyone you have ever played with, sitting at
    /// zero, on a game they were never part of.
    ///
    /// Three things make somebody a participant here:
    ///
    /// - they have a sighting filed under this collection — the historical answer,
    ///   which is what keeps finished trips correct;
    /// - they are in a party that is live on this collection right now, so people
    ///   who have joined but not yet called anything appear at zero rather than
    ///   popping into existence on their first find;
    /// - they are this phone, which is always playing whatever it is looking at.
    ///
    /// Returned in the order given, so the caller's sort (join date) survives.
    func participants(from players: [Player],
                      me: Player? = nil,
                      alsoPlaying live: Set<UUID> = []) -> [Player] {
        var wanted = Set(allSightings.compactMap { $0.player?.id }).union(live)
        if let me { wanted.insert(me.id) }
        return players.filter { wanted.contains($0.id) }
    }

    // MARK: - Whose plate is it

    /// Has *this player* banked this plate — strictly, by id.
    ///
    /// Used to decide whether a tap under `sharedClaims` is a fresh claim or a
    /// take-back, so it deliberately does not count unowned sightings: a plate
    /// somebody logged before players existed is not evidence that you claimed it.
    func hasClaimed(_ code: String, by player: Player?) -> Bool {
        guard let player else { return false }
        return allSightings.contains { $0.plateCode == code && $0.player?.id == player.id }
    }

    /// The sightings of this plate that `player` is allowed to take back.
    ///
    /// Unowned ones count as removable, which is the looser half of the rule and is
    /// meant: they predate attribution or belonged to somebody since deleted, so
    /// protecting them would leave plates on the board that nobody alive can undo.
    func removableSightings(of code: String,
                            by player: Player?,
                            protected: Bool) -> [Sighting] {
        allSightings.filter { sighting in
            guard sighting.plateCode == code else { return false }
            guard protected else { return true }
            return sighting.player == nil || sighting.player?.id == player?.id
        }
    }

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
