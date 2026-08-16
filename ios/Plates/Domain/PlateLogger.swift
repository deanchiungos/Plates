import CoreLocation
import SwiftData

/// Recording a sighting, in one place.
///
/// There are three ways into this — a tap on the grid, Siri, and now voice mode —
/// and until this existed there were three copies of the same six lines. They had
/// already drifted: the grid banked the rarity and stamped the coordinate, Siri did
/// neither, so a plate logged by voice scored the national average and never appeared
/// on the trail. Whichever way a sighting arrives it is the same sighting.
enum PlateLogger {

    struct Outcome {
        /// False when this plate was already on the collection. The difference is the
        /// whole reward, so every caller needs it and none of them should re-derive it
        /// after the insert, when everything is "seen".
        let isFirstFind: Bool
        let tier: RarityTier
        /// How many times this plate has now been seen, including this one.
        let count: Int
    }

    @discardableResult
    @MainActor
    static func record(_ plate: Plate,
                       in collection: any PlateCollection,
                       by player: Player? = nil,
                       at coordinate: CLLocationCoordinate2D? = nil,
                       context: ModelContext) -> Outcome {

        // Whose first find, not the collection's. Under shared claims somebody else
        // getting there first no longer stops you banking it, and asking whether the
        // *collection* had seen it meant every claimant after the first got a repeat
        // buzz and nothing else — no banner, no fact, no confetti — for what the rules
        // had just told them was a genuine claim. The reward is the whole difference
        // this flag carries, so it has to be asked of the person collecting it.
        //
        // Same answer as before wherever a sighting has no player: a solo collection
        // falls back to the collection's own memory.
        let isFirstFind = player.map { !collection.hasClaimed(plate.code, by: $0) }
            ?? !collection.hasSeen(plate)

        let sighting = Sighting(plateCode: plate.code, in: collection, player: player)
        // Banked now, from where the car is now. After this the plate is claimed and
        // stops tracking — see `PlateCollection.rarity(of:)`.
        sighting.rarityWhenSpotted = collection.liveRarity(of: plate.code)
        if let coordinate {
            sighting.spottedLat = coordinate.latitude
            sighting.spottedLon = coordinate.longitude
        }
        context.insert(sighting)
        try? context.save()

        // The one place a sighting is ever created is the one place a party needs to
        // hear about it — which is why this hook is here and not at the three call
        // sites above it. No-op unless a party is running, and it only ever sends
        // what *this* device just authored: nothing received is re-broadcast, so the
        // party cannot echo. See `PartyMerge`.
        PartySession.shared?.broadcast(sighting)

        // The same idea over a slower wire: a plate logged into a shared book has to
        // reach whoever else is filling it. Same rule as the party — only what this
        // device authored goes out, and nothing that arrives is ever re-published,
        // because received sightings come through `SharedBookMerge` and never
        // through here.
        // No `isShared` check here, or at the five other call sites of `push` and
        // `remove`. Every one of them asked the ledger the same question the sync
        // itself asks on the first line of both methods, which put the definition of
        // "this book is shared" in seven places and made six of them able to drift
        // from the one that decides. `SharedBookSync` is a no-op for a book nobody
        // is sharing.
        if let book = sighting.book { SharedBookSync.shared.push(sighting, in: book) }

        // The trip just took a plate, so whatever reminder was pending for it is
        // now measured from the wrong moment. Rebuilt rather than patched — see
        // `TripReminders`. No-op unless somebody has turned reminders on.
        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)

        return Outcome(isFirstFind: isFirstFind,
                       tier: RarityTier.forRarity(collection.rarity(of: plate.code)),
                       count: collection.sightingCount(for: plate))
    }

    /// Taking a sighting back, in one place.
    ///
    /// The mirror of `record`, and it exists for the same reason: there were three
    /// ways to un-log a plate — the grid, voice mode, and emptying a book — and three
    /// copies of the same side effects, which had already drifted three ways. The
    /// grid handed a folded sighting back to its trip where voice mode destroyed it
    /// outright; emptying a book told neither the party nor the shared book that
    /// anything had gone; and none of the three rebuilt the reminder or the widget
    /// mirror, so an un-tapped plate stayed lit on the home screen until the next
    /// time somebody logged something.
    ///
    /// Takes the rows rather than a plate code. "Un-tap this plate" and "delete every
    /// sighting of it" stopped being the same question once claims could be protected
    /// and shared, so who decides which rows go is the caller's business — see
    /// `PlateCollection.removableSightings(of:by:protected:)`. What happens to them
    /// once decided is this function's.
    ///
    /// Haptics stay at the call sites. Undoing a mistap and emptying a whole book are
    /// the same operation on the data and very different news to break to somebody.
    @MainActor
    static func withdraw(_ sightings: [Sighting],
                         from collection: any PlateCollection,
                         context: ModelContext) {
        guard !sightings.isEmpty else { return }

        // Other people's shelves first, while the rows are still here to be asked
        // which book they were on. A sighting can be folded into a book that is not
        // the collection being emptied, and if that book is shared its members need
        // the tombstone — the reference is gone the moment the row is.
        for (_, group) in Dictionary(grouping: sightings.filter { $0.book != nil },
                                     by: { $0.book!.id }) {
            if let book = group.first?.book, book.id != collection.id {
                SharedBookSync.shared.remove(group.map(\.id), in: book)
            }
        }

        // Named individually, and collected before the delete, because afterwards
        // there is nothing left to ask which rows went — and a peer that never heard
        // of a sighting still has to be able to record that it is gone.
        var withdrawn: [UUID] = []
        for sighting in sightings {
            withdrawn.append(sighting.id)
            // A plate folded in from a finished trip is the trip's record, on loan to
            // this book. Taking it off the shelf hands it back; it does not reach into
            // the trip and erase what happened there. Only sightings the book itself
            // logged are the book's to delete.
            if collection is Book, sighting.trip != nil {
                sighting.book = nil
            } else {
                context.delete(sighting)
            }
        }
        try? context.save()

        if let trip = collection as? Trip {
            PartySession.shared?.broadcastRemoval(withdrawn, in: trip.id)
        }
        // The same withdrawal over the slower wire. Deleting the record *is* the
        // tombstone here — CloudKit tells the other side on their next pull — so
        // unlike the party there is nothing extra to remember.
        if let book = collection as? Book {
            SharedBookSync.shared.remove(withdrawn, in: book)
        }

        // The two mirrors that outlive the row. A trip that just gave a plate back is
        // measured from a different moment, and the home screen is still showing the
        // plate — both were rebuilt on the way in and neither was on the way out.
        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
    }
}
