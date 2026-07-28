import Foundation
import SwiftData

enum ScoringMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, weighted, unlimited

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:   return "Classic scoring"
        case .weighted:  return "Weighted scoring"
        case .unlimited: return "Unlimited scoring"
        }
    }

    var blurb: String {
        switch self {
        case .classic:   return "One point per state, however many times you see it."
        case .weighted:  return "Rarer plates are worth more."
        case .unlimited: return "Every sighting scores, so keep counting."
        }
    }
}

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    /// Index into `Theme.playerColors` — storing the index rather than a hex string
    /// keeps players correct if the palette is ever retuned.
    var colorIndex: Int = 0
    var joinedAt: Date = Date()

    /// Nullify, not cascade. Removing someone from the car must not un-collect
    /// the plates they spotted — the sighting happened. Their sightings survive
    /// with no owner, so the trip's count is unchanged and only the per-player
    /// standings lose those points.
    @Relationship(deleteRule: .nullify, inverse: \Sighting.player)
    var sightings: [Sighting]? = []

    init(name: String, colorIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorIndex = colorIndex
        self.joinedAt = Date()
    }

    var initial: String { String(name.prefix(1)).uppercased() }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var scoringModeRaw: String = ScoringMode.classic.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Sighting.trip)
    var sightings: [Sighting]? = []

    init(name: String, scoringMode: ScoringMode = .classic) {
        self.id = UUID()
        self.name = name
        self.startedAt = Date()
        self.scoringModeRaw = scoringMode.rawValue
    }

    var scoringMode: ScoringMode {
        get { ScoringMode(rawValue: scoringModeRaw) ?? .classic }
        set { scoringModeRaw = newValue.rawValue }
    }

    var isActive: Bool { endedAt == nil }

    /// 1-based, so the first day of a trip reads "day 1".
    var dayNumber: Int {
        let days = Calendar.current.dateComponents([.day], from: startedAt, to: Date()).day ?? 0
        return max(1, days + 1)
    }
}

/// One plate, seen once, by one player. This is the single source of truth —
/// every count, score and badge in the app is derived from these and nothing else.
@Model
final class Sighting {
    var id: UUID = UUID()
    var plateCode: String = ""
    var spottedAt: Date = Date()

    var trip: Trip?
    var player: Player?

    init(plateCode: String, trip: Trip?, player: Player?, spottedAt: Date = Date()) {
        self.id = UUID()
        self.plateCode = plateCode
        self.trip = trip
        self.player = player
        self.spottedAt = spottedAt
    }

    var plate: Plate? { Plate.plate(for: plateCode) }
}
