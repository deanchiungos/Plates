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
        /// A player already on this device was edited — renamed, recolored, or given
        /// an avatar. Separate from `playersAdded`, which counts inserts only.
        ///
        /// Without this the save gate below could not see an edit at all: an envelope
        /// whose whole effect was somebody's rename left the context dirty and
        /// returned an empty outcome, so `apply` skipped its one save and the change
        /// survived only if SwiftData's autosave happened to fire before the process
        /// died — which the "one save per envelope, at the end" contract explicitly
        /// does not rely on, and which the merge harness's own store disables.
        var playersChanged = false

        var isEmpty: Bool {
            sightingsAdded == 0 && sightingsRemoved == 0
                && playersAdded == 0 && !tripChanged && !playersChanged
        }
    }

    // MARK: - Building what we send

    static func snapshot(of trip: Trip,
                         players: [Player],
                         hostPlayerID: UUID?,
                         rules: PartyRules,
                         tombstones: PartyTombstones) -> PartySnapshot {
        PartySnapshot(
            trip: event(for: trip, rules: rules),
            players: players.map(event(for:)),
            sightings: trip.allSightings.compactMap(event(for:)),
            tombstones: Array(tombstones.ids(for: trip.id)),
            hostPlayerID: hostPlayerID
        )
    }

    static func event(for trip: Trip, rules: PartyRules? = nil) -> TripEvent {
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
                  includesTrucks: trip.includesTrucks,
                  rules: rules)
    }

    static func event(for player: Player) -> PlayerEvent {
        PlayerEvent(id: player.id,
                    name: player.name,
                    colorIndex: player.colorIndex,
                    avatar: player.avatar,
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
    /// `fromHost` says whether the peer that sent this is the one whose word counts
    /// for the trip's own settings — its name, its scoring, and whether it has
    /// finished. Everything else in an envelope is accepted from anybody: a plate is
    /// a plate whoever spotted it.
    ///
    /// Defaults to `true` so a caller reasoning about a host's snapshot — which is
    /// every caller in the harness — does not have to say so. `PartySession` passes
    /// the real answer.
    @discardableResult
    static func apply(_ envelope: PartyEnvelope,
                      into context: ModelContext,
                      tombstones: PartyTombstones,
                      fromHost: Bool = true) -> Outcome {
        var outcome = Outcome()

        switch envelope.payload {
        case .hello(let snapshot):
            apply(snapshot, into: context, tombstones: tombstones,
                  fromHost: fromHost, outcome: &outcome)

        case .sighting(let event):
            apply([event], into: context, tombstones: tombstones, outcome: &outcome)

        case .remove(let event):
            apply(event, into: context, tombstones: tombstones, outcome: &outcome)

        case .roster(let events):
            apply(events, into: context, outcome: &outcome)

        case .tripUpdate(let event):
            // Nothing in a trip update is anything but the host's to say, so one from
            // a guest is dropped whole rather than filtered. `broadcastTrip` already
            // refuses to *send* one; this is the receiving half of the same rule.
            if fromHost { _ = apply(event, into: context, outcome: &outcome) }

        case .bye:
            break
        }

        if !outcome.isEmpty {
            try? context.save()
            // A passenger's find is a find. Nothing that arrives from another device
            // goes through `PlateLogger`, which is where the widget was rebuilt — so
            // the grid climbed while the home screen sat at the count it had when
            // the drive started.
            //
            // Asked for rather than done: this runs once per envelope, and a car
            // full of phones calling plates is a steady stream of them.
            WidgetData.setNeedsWrite(from: context)
        }
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
                              fromHost: Bool,
                              outcome: inout Outcome) {
        guard let trip = apply(snapshot.trip, into: context,
                               canRewrite: fromHost, outcome: &outcome) else { return }

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
    ///
    /// `canRewrite` is false for a snapshot from a guest, and it has to be. A snapshot
    /// carries the sender's whole idea of the trip, including how finished it was the
    /// last time they looked — so re-hosting a trip you reopened means the first guest
    /// to join, still holding their finished copy, hands you `endedAt` back and your
    /// own trip quietly closes underneath the party. Same shape for a rename they
    /// missed. A guest's snapshot may still *create* the trip: refusing outright would
    /// take every sighting in it down as well, which is a worse trade than a stale name.
    @discardableResult
    private static func apply(_ event: TripEvent,
                              into context: ModelContext,
                              canRewrite: Bool = true,
                              outcome: inout Outcome) -> Trip? {
        let id = event.id
        let existing = try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id }))

        if let trip = existing?.first {
            guard canRewrite else { return trip }
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

        // This device is the last word on who *it* is.
        //
        // Without this, applying a roster was last-writer-wins on a field only one
        // device can be right about. Rename yourself mid-drive and every other phone
        // still holds your old name; the next snapshot any of them sends — a fresh
        // party on the same trip is the reliable way to trigger one — writes it back
        // over you, and the rename you just made undoes itself. It reads as the app
        // refusing to let you be called what you asked to be called, and doing it
        // again every time somebody starts a party.
        //
        // Ownership rather than a timestamp because `Player` is a `@Model`: a
        // `renamedAt` field would mean a new CloudKit attribute and the
        // additive-and-permanent production deploy `PlatesStore` warns about, to
        // arbitrate a conflict that has an obvious owner.
        //
        // Falls back to resolving when the key is unset, which is not a rare state:
        // `pinDevicePlayer` writes it only once a profile exists, so a fresh install
        // or a restore whose sync has not landed reaches a party with nothing there.
        // Comparing against nil is always unequal, so the guard below silently did
        // nothing on exactly the installs it most needed to protect — a peer's stale
        // roster would rewrite the user's own name, color and avatar. Resolving costs
        // nothing here because `known` is the fetch it would otherwise have to make.
        let mine = DevicePlayer.currentID
            ?? DevicePlayer.resolve(from: Array(known.values))?.id.uuidString

        for event in events {
            if let player = known[event.id] {
                // Their copy of me is stale by construction — I am the only device
                // that saw me change it. See `PartySession.announceMe` for how the
                // rename gets *out*.
                guard player.id.uuidString != mine else { continue }
                if player.name != event.name {
                    player.name = event.name
                    outcome.playersChanged = true
                }
                if player.colorIndex != event.colorIndex {
                    player.colorIndex = event.colorIndex
                    outcome.playersChanged = true
                }
                if player.avatar != event.avatar {
                    player.avatar = event.avatar
                    outcome.playersChanged = true
                }
                continue
            }
            let player = Player(name: event.name, colorIndex: event.colorIndex)
            player.id = event.id
            player.avatar = event.avatar
            player.joinedAt = event.joinedAt
            context.insert(player)
            known[event.id] = player
            outcome.playersAdded += 1
        }

        // The party, not the address book. `known` is every `Player` this install has
        // ever created, so de-colliding across it made the answer a function of each
        // device's private history: a phone holding five players from past drives
        // consumed the palette on people who are not in the car, and the person
        // sitting next to you came out a different color on your phone than on
        // theirs. It also rewrote those historical players — persisted, and
        // retroactively repainting last summer's standings — and could move this
        // device's own player, three lines after the guard that exists to stop
        // exactly that.
        //
        // The events are the roster, and every device receives the same ones, so
        // scoping to them is what makes this the pure function it is documented to
        // be. A lone `.roster` naming one person settles nothing, which is correct;
        // the full roster arrives with every `.hello`, which is when collisions are
        // worth resolving.
        settleColors(events.compactMap { known[$0.id] }, outcome: &outcome)
    }

    /// Two people who both picked green have to stop being both green, and every
    /// phone has to agree on which of them moved.
    ///
    /// Nobody negotiates. Order everyone by when they joined, walk the list, and give
    /// anyone whose color an earlier player already holds the lowest free one. That
    /// is a pure function of data every device has, so all of them land on the same
    /// answer without a message being sent — and the person who was there first keeps
    /// the color they have been playing as.
    ///
    /// Ties on `joinedAt` break on id, for the same reason `SightingOrder` does it:
    /// otherwise two devices could disagree about who counts as earlier and hand the
    /// same two people opposite colors.
    private static func settleColors(_ players: [Player], outcome: inout Outcome) {
        var taken = Set<Int>()
        let ordered = players.sorted {
            ($0.joinedAt, $0.id.uuidString) < ($1.joinedAt, $1.id.uuidString)
        }
        for player in ordered {
            if taken.insert(player.colorIndex).inserted { continue }
            guard let free = (0..<Theme.playerColors.count).first(where: { !taken.contains($0) })
            else {
                // More people than colors. Everybody past the sixth keeps whatever
                // they arrived with and colors start repeating, which is the known
                // cost of not capping how many can play. `continue`, not `break`:
                // the palette is full for everyone remaining, so there is nothing
                // left to settle, but stopping the loop here used to read as a
                // decision rather than as running out.
                continue
            }
            player.colorIndex = free
            taken.insert(free)
            outcome.playersChanged = true
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
            // The same rule every other removal path applies, and the one path that
            // never had it. A peer un-tapping a plate is a statement about the trip;
            // it is not permission to reach into a book on this phone. A row folded
            // into a book hands itself back to the book instead of being deleted —
            // and this matters more here than anywhere, because a reconnect replays
            // the whole accumulated tombstone set, so one un-tap last Tuesday could
            // empty a shelf today. See `PlateLogger.withdraw` and the mirror in
            // `SharedBookMerge.apply`.
            if sighting.book != nil {
                sighting.trip = nil
            } else {
                context.delete(sighting)
            }
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
