import Foundation
import SwiftData

/// Closing a trip out, from wherever the decision is made.
///
/// This lived as two private methods on `TripsScreen`, which was fine while the
/// trips list was the only place a trip could end. It is not: a party ending is a
/// drive ending, and the party screen is where somebody is standing when that
/// happens. Two copies of "finish means endedAt *and* archivedAt, and clear the
/// selection if it pointed here" is exactly the kind of pair that drifts.
@MainActor
enum TripClosing {

    /// Finished, which is not the same as put away.
    ///
    /// These used to be one move, on the reasoning that a trip you are done with is a
    /// trip you are done seeing — the switcher had grown taller than the phone and
    /// finishing was what pruned it. That reasoning is now served by `collectable`,
    /// which excludes finished trips from every picker on its own, so the two can be
    /// separate again without the list coming back.
    ///
    /// And they should be. A drive that just ended is the one you most want to look
    /// at: a tester asked for exactly this — finished trips still visible for review,
    /// archived ones out of the summary. Archiving stays a deliberate second step.
    static func finish(_ trip: Trip, in context: ModelContext) {
        trip.endedAt = Date()
        try? context.save()

        // A trip that is no longer the one being played must not still be named as
        // it, or the Game screen opens on something it cannot collect into.
        if UserDefaults.standard.string(forKey: TripSelection.key) == trip.id.uuidString {
            UserDefaults.standard.set("", forKey: TripSelection.key)
        }

        // A finished trip takes no more plates, so a party still pointed at it would
        // be a radio running for a game nobody can play. The goodbye goes out first,
        // which is what stops everyone else hunting for a host that has stopped.
        if PartySession.isPartying(trip) { PartySession.shared?.leave() }

        // A finished trip is not an abandoned one, so its reminder goes.
        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
    }

    /// Throwing away this device's copy of somebody else's trip.
    ///
    /// Only ever offered to a guest who spotted nothing — see `PartyScreen`. The
    /// cascade takes the sightings with it, and those sightings are other people's
    /// finds: that is correct, because they are *this phone's copy* of them. Every
    /// other phone in the party keeps its own, which is the whole shape of the
    /// design and the reason discarding one copy is safe.
    static func discard(_ trip: Trip, in context: ModelContext) {
        let id = trip.id
        if PartySession.isPartying(trip) { PartySession.shared?.leave() }

        context.delete(trip)
        try? context.save()

        // The sidecars are keyed by trip id and would otherwise outlive it — a
        // tombstone set protecting a trip that no longer exists, and a ledger entry
        // claiming a party for one.
        PartyTombstones.shared.forget(trip: id)
        PartyLedger.shared.forget(trip: id)

        if UserDefaults.standard.string(forKey: TripSelection.key) == id.uuidString {
            UserDefaults.standard.set("", forKey: TripSelection.key)
        }

        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
    }

    /// Whether this phone has anything of its own invested in a trip.
    ///
    /// The question behind "can I just throw this copy away?". Judged on the device
    /// player's own sightings, not the trip's — a trip full of other people's plates
    /// that you contributed nothing to is somebody else's drive that you watched.
    static func hasOwnFinds(in trip: Trip, players: [Player]) -> Bool {
        guard let me = DevicePlayer.resolve(from: players) else { return false }
        return trip.allSightings.contains { $0.player?.id == me.id }
    }
}
