import Foundation

// Everything below is DERIVED from `Trip.sightings`.
//
// The web version stored a parallel `log` array, capped it at 30 entries, and then
// counted unique states from that log — so the headline "N/50" silently stopped
// rising at 30 and decayed as older sightings fell off the end. Nothing here caches
// or truncates: the only way to change a count is to add or remove a Sighting.

extension Trip {

    var allSightings: [Sighting] { sightings ?? [] }

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
            .max { $0.spottedAt < $1.spottedAt }?
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
            return codes.reduce(0) { $0 + (Plate.plate(for: $1)?.points ?? 0) }

        case .unlimited:
            // Every sighting scores its rarity, so repeats keep paying.
            return relevant.reduce(0) { $0 + ($1.plate?.points ?? 0) }
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
