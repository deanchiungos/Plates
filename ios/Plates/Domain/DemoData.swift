#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixture, used for screenshots and previews.
///
/// Opt-in: it only runs when the app is launched with `-demoData`. It is compiled
/// out of Release entirely, so there is no path by which a real player sees it.
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    /// Mirrors the design mockup: a westward trip, three people in the car, and an
    /// uneven split so the leader treatment on the player strip is actually visible.
    /// Includes all eight styled prototype states (AK CO NM CA TX NY HI MT)
    /// alongside unstyled ones, so a screenshot shows styled plates, blue
    /// fallbacks and unfound paper tiles side by side for comparison.
    private static let script: [(code: String, player: Int)] = [
        ("CA", 0), ("NV", 1), ("UT", 2), ("AZ", 0), ("CO", 1), ("NM", 0),
        ("KS", 2), ("MO", 1), ("IL", 0), ("TX", 0), ("OK", 1), ("AR", 2),
        ("NE", 0), ("WY", 1), ("ID", 0), ("OR", 2), ("WA", 1), ("MT", 0),
        ("AK", 1), ("HI", 2), ("NY", 0)
    ]

    @MainActor
    static func install(into context: ModelContext) {
        // start from a clean slate so repeated launches are deterministic
        try? context.delete(model: Sighting.self)
        try? context.delete(model: Trip.self)
        try? context.delete(model: Player.self)

        let players = [
            Player(name: "Dad",  colorIndex: 0),
            Player(name: "Mia",  colorIndex: 1),
            Player(name: "Theo", colorIndex: 2)
        ]
        players.forEach(context.insert)

        let trip = Trip(name: "Summer Roadtrip")
        trip.startedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        context.insert(trip)

        // spread the timestamps so "most recent spotter" is well defined
        for (offset, entry) in script.enumerated() {
            let when = trip.startedAt.addingTimeInterval(Double(offset) * 600)
            context.insert(
                Sighting(plateCode: entry.code,
                         trip: trip,
                         player: players[entry.player],
                         spottedAt: when)
            )
        }

        try? context.save()
    }
}
#endif
