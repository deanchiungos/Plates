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

        let isFirstFind = !collection.hasSeen(plate)

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
        if let book = sighting.book, SharedBookLedger.shared.isShared(book.id) {
            SharedBookSync.shared.push(sighting, in: book)
        }

        // The trip just took a plate, so whatever reminder was pending for it is
        // now measured from the wrong moment. Rebuilt rather than patched — see
        // `TripReminders`. No-op unless somebody has turned reminders on.
        TripReminders.shared.refresh(in: context)

        return Outcome(isFirstFind: isFirstFind,
                       tier: RarityTier.forRarity(collection.rarity(of: plate.code)),
                       count: collection.sightingCount(for: plate))
    }
}
