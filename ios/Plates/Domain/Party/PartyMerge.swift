import Foundation
import SwiftData

/// Turning what a peer said into rows in the store, and back again.
///
/// The one rule this file exists to keep: **applying anything twice must change
/// nothing.** Every connection re-sends a full snapshot, phones drop in and out of
/// a party all drive, and the same sighting will arrive several times over a long
/// trip. Idempotence is what makes all of that boring instead of a source of
/// duplicate plates. It is enforced by fetching before inserting, on `id` — not by
/// `@Attribute(.unique)`, which SwiftData forbids on a CloudKit-backed store.
///
/// The second rule, which is easier to break by accident: **received data never
/// re-enters the broadcast path.** Nothing here calls `PlateLogger`, and nothing
/// that calls `PlateLogger` calls anything here. That separation is the entire
/// reason sightings do not need an author tag to avoid echoing around the party
/// forever — the loop is broken structurally rather than by a flag.
@MainActor
enum PartyMerge {

    /// What an envelope did, for the caller that wants to say so out loud.
    struct Outcome: Equatable {
        var sightingsAdded = 0
        var sightingsRemoved = 0
        var playersAdded = 0
        var tripChanged = false

        var isEmpty: Bool {
            sightingsAdded == 0 && sightingsRemoved == 0
                && playersAdded == 0 && !tripChanged
        }
    }

    // MARK: - Building what we send

    static func snapshot(of trip: Trip,
                         players: [Player],
                         hostPlayerID: UUID?,
                         tombstones: PartyTombstones) -> PartySnapshot {
        PartySnapshot(
            trip: event(for: trip),
            players: players.map(event(for:)),
            sightings: trip.allSightings.compactMap(event(for:)),
            tombstones: Array(tombstones.ids(for: trip.id)),
            hostPlayerID: hostPlayerID
        )
    }

    static func event(for trip: Trip) -> TripEvent {
        TripEvent(id: trip.id,
                  name: trip.name,
                  startedAt: trip.startedAt,
                  endedAt: trip.endedAt,
                  origin: trip.origin,
                  destination: trip.destination,
                  originLat: trip.originLat,
                  originLon: trip.originLon,
                  destinationLat: trip.destinationLat,
                  destinationLon: trip.destinationLon,
                  scoringModeRaw: trip.scoringModeRaw,
                  includesTrucks: trip.includesTrucks)
    }

    static func event(for player: Player) -> PlayerEvent {
        PlayerEvent(id: player.id,
                    name: player.name,
                    colorIndex: player.colorIndex,
                    joinedAt: player.joinedAt)
    }

    /// Nil for anything not filed under a trip. Books are single-player by design
    /// and orphaned sightings have no party to belong to.
    static func event(for sighting: Sighting) -> SightingEvent? {
        guard let tripID = sighting.trip?.id else { return nil }
        return SightingEvent(id: sighting.id,
                             plateCode: sighting.plateCode,
                             spottedAt: sighting.spottedAt,
                             tripID: tripID,
                             playerID: sighting.player?.id,
                             rarityWhenSpotted: sighting.rarityWhenSpotted,
                             spottedLat: sighting.spottedLat,
                             spottedLon: sighting.spottedLon)
    }

    // MARK: - Applying what we hear

    /// One save per envelope, at the end, rather than one per row: a snapshot is
    /// dozens of inserts and saving between each would be dozens of writes to the
    /// store — and, on a CloudKit-backed container, dozens of separate pushes.
    @discardableResult
    static func apply(_ envelope: PartyEnvelope,
                      into context: ModelContext,
                      tombstones: PartyTombstones) -> Outcome {
        var outcome = Outcome()

        switch envelope.payload {
        case .hello(let snapshot):
            apply(snapshot, into: context, tombstones: tombstones, outcome: &outcome)

        case .sighting(let event):
            apply([event], into: context, tombstones: tombstones, outcome: &outcome)

        case .remove(let event):
            apply(event, into: context, tombstones: tombstones, outcome: &outcome)

        case .roster(let events):
            apply(events, into: context, outcome: &outcome)

        case .tripUpdate(let event):
            _ = apply(event, into: context, outcome: &outcome)

        case .bye:
            break
        }

        if !outcome.isEmpty { try? context.save() }
        return outcome
    }

    // MARK: - Snapshot

    /// Order matters here.
    ///
    /// The trip lands first because sightings need something to attach to, and the
    /// players before the sightings for the same reason. Tombstones go in *before*
    /// the sightings rather than after: the sender's snapshot contains everything
    /// it knows, including plates that were later taken back, so applying the
    /// withdrawals first means those are never inserted at all instead of being
    /// inserted and then deleted a line later.
    private static func apply(_ snapshot: PartySnapshot,
                              into context: ModelContext,
                              tombstones: PartyTombstones,
                              outcome: inout Outcome) {
        guard let trip = apply(snapshot.trip, into: context, outcome: &outcome) else { return }

        apply(snapshot.players, into: context, outcome: &outcome)

        apply(RemovalEvent(tripID: trip.id, sightingIDs: snapshot.tombstones),
              into: context, tombstones: tombstones, outcome: &outcome)

        apply(snapshot.sightings, into: context, tombstones: tombstones, outcome: &outcome)
    }

    // MARK: - Trip

    /// Writes the shared columns and *only* the shared columns.
    ///
    /// `currentLat` / `currentLon` / `locatedAt` are this phone's own position and
    /// feed its live rarity; `pinnedAt` and `archivedAt` are preferences about your
    /// own lists. A peer must not touch any of them. See `TripEvent`.
    @discardableResult
    private static func apply(_ event: TripEvent,
                              into context: ModelContext,
                              outcome: inout Outcome) -> Trip? {
        let id = event.id
        let existing = try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id }))

        if let trip = existing?.first {
            // Compared before assigning so an unchanged snapshot — the common case,
            // since one arrives on every reconnect — does not dirty the object and
            // send SwiftUI redrawing the whole grid for nothing.
            if trip.name != event.name { trip.name = event.name; outcome.tripChanged = true }
            if trip.startedAt != event.startedAt { trip.startedAt = event.startedAt; outcome.tripChanged = true }
            if trip.endedAt != event.endedAt { trip.endedAt = event.endedAt; outcome.tripChanged = true }
            if trip.origin != event.origin { trip.origin = event.origin; outcome.tripChanged = true }
            if trip.destination != event.destination { trip.destination = event.destination; outcome.tripChanged = true }
            if trip.originLat != event.originLat { trip.originLat = event.originLat; outcome.tripChanged = true }
            if trip.originLon != event.originLon { trip.originLon = event.originLon; outcome.tripChanged = true }
            if trip.destinationLat != event.destinationLat { trip.destinationLat = event.destinationLat; outcome.tripChanged = true }
            if trip.destinationLon != event.destinationLon { trip.destinationLon = event.destinationLon; outcome.tripChanged = true }
            if trip.scoringModeRaw != event.scoringModeRaw { trip.scoringModeRaw = event.scoringModeRaw; outcome.tripChanged = true }
            if trip.includesTrucks != event.includesTrucks { trip.includesTrucks = event.includesTrucks; outcome.tripChanged = true }
            return trip
        }

        let trip = Trip(name: event.name)
        trip.id = event.id
        trip.startedAt = event.startedAt
        trip.endedAt = event.endedAt
        trip.origin = event.origin
        trip.destination = event.destination
        trip.originLat = event.originLat
        trip.originLon = event.originLon
        trip.destinationLat = event.destinationLat
        trip.destinationLon = event.destinationLon
        trip.scoringModeRaw = event.scoringModeRaw
        trip.includesTrucks = event.includesTrucks
        context.insert(trip)
        outcome.tripChanged = true
        return trip
    }

    // MARK: - Players

    private static func apply(_ events: [PlayerEvent],
                              into context: ModelContext,
                              outcome: inout Outcome) {
        guard !events.isEmpty else { return }
        var known = allPlayers(in: context)

        for event in events {
            if let player = known[event.id] {
                if player.name != event.name { player.name = event.name }
                if player.colorIndex != event.colorIndex { player.colorIndex = event.colorIndex }
                continue
            }
            let player = Player(name: event.name, colorIndex: event.colorIndex)
            player.id = event.id
            player.joinedAt = event.joinedAt
            context.insert(player)
            known[event.id] = player
            outcome.playersAdded += 1
        }
    }

    // MARK: - Sightings

    private static func apply(_ events: [SightingEvent],
                              into context: ModelContext,
                              tombstones: PartyTombstones,
                              outcome: inout Outcome) {
        guard !events.isEmpty else { return }

        // Fetched whole rather than per-id, because the alternative is one query per
        // sighting on every reconnect. The set is every sighting the install has
        // ever recorded, which is a few hundred rows for somebody who has played a
        // lot — one cheap query on a rare event, against N queries on a common one.
        var seen = allSightingIDs(in: context)
        var trips = [UUID: Trip]()
        var players: [UUID: Player]?

        for event in events {
            guard !seen.contains(event.id) else { continue }
            guard !tombstones.contains(event.id, in: event.tripID) else { continue }

            // No trip means nothing to file it under. Defensive rather than expected:
            // a snapshot always carries its trip first, and a live sighting only
            // arrives from a party we are already in.
            guard let trip = trips[event.tripID]
                    ?? trip(event.tripID, in: context).map({ trips[event.tripID] = $0; return $0 })
            else { continue }

            var player: Player?
            if let playerID = event.playerID {
                // Loaded once, and only if some sighting actually names a player.
                let table = players ?? allPlayers(in: context)
                players = table
                player = table[playerID]
            }

            let sighting = Sighting(plateCode: event.plateCode,
                                    trip: trip,
                                    player: player,
                                    spottedAt: event.spottedAt)
            sighting.id = event.id
            sighting.rarityWhenSpotted = event.rarityWhenSpotted
            sighting.spottedLat = event.spottedLat
            sighting.spottedLon = event.spottedLon
            context.insert(sighting)

            seen.insert(event.id)
            outcome.sightingsAdded += 1
        }
    }

    /// Records the withdrawal first, then deletes.
    ///
    /// The tombstone is written even when there is no local row to delete, which is
    /// the case that matters: a peer that never heard about the plate in the first
    /// place still has to remember it was taken back, or its next snapshot puts it
    /// back on everybody else's phone.
    private static func apply(_ event: RemovalEvent,
                              into context: ModelContext,
                              tombstones: PartyTombstones,
                              outcome: inout Outcome) {
        guard !event.sightingIDs.isEmpty else { return }
        tombstones.add(event.sightingIDs, to: event.tripID)

        let doomed = Set(event.sightingIDs)
        let existing = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        for sighting in existing where doomed.contains(sighting.id) {
            context.delete(sighting)
            outcome.sightingsRemoved += 1
        }
    }

    // MARK: - Lookups

    private static func trip(_ id: UUID, in context: ModelContext) -> Trip? {
        try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first
    }

    private static func allPlayers(in context: ModelContext) -> [UUID: Player] {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        return Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private static func allSightingIDs(in context: ModelContext) -> Set<UUID> {
        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        return Set(sightings.map(\.id))
    }
}
