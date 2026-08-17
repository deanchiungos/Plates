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
    /// Set by `finish`, read by the `doneTrip` coach mark, never persisted.
    ///
    /// In memory on purpose. The tip is a follow-through on something you just did —
    /// "that trip went *there*" — and a flag that survived a relaunch would turn it
    /// into archaeology about a drive from last month, explained to somebody who
    /// opened the Trips tab for an unrelated reason.
    private(set) static var finishedSomethingThisSession = false

    static func finish(_ trip: Trip, in context: ModelContext) {
        trip.endedAt = Date()
        finishedSomethingThisSession = true
        try? context.save()

        // A trip that is no longer the one being played must not still be named as
        // it, or the Game screen opens on something it cannot collect into.
        deselect(trip.id)

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

        // A folded sighting lives in two containers and the cascade only knows about
        // one of them. `Trip.sightings` cascades where `Book.sightings` nullifies, so
        // left alone this would reach through the trip and take plates out of a book
        // somebody deliberately filed them in — and, if that book is shared, leave
        // every other member holding a copy this phone no longer has. Unshelving them
        // from the trip first is the same rule the grid applies when a plate is
        // un-tapped in a book a trip still owns: drop it from this container, leave it
        // in the other. Discarding the drive is not disowning the shelf.
        for sighting in trip.allSightings where sighting.book != nil { sighting.trip = nil }

        context.delete(trip)
        try? context.save()

        // The sidecars are keyed by trip id and would otherwise outlive it — a
        // tombstone set protecting a trip that no longer exists, and a ledger entry
        // claiming a party for one.
        PartyTombstones.shared.forget(trip: id)
        PartyLedger.shared.forget(trip: id)

        deselect(id)

        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
    }

    /// Stop naming this trip as the one being played, if it still is.
    ///
    /// Through `AppDefaults` like every other preference the app owns. Written out
    /// twice against `UserDefaults.standard`, it was the one key `PlaySelection`
    /// writes through the swappable store and this file read through the real one —
    /// so `-partyMergeCheck`, which calls both functions above, reached past the
    /// scratch suite and into the phone's actual selection.
    private static func deselect(_ id: UUID) {
        guard AppDefaults.store.string(forKey: TripSelection.key) == id.uuidString else { return }
        AppDefaults.store.set("", forKey: TripSelection.key)
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
