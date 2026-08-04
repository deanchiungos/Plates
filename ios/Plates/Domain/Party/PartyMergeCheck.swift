#if DEBUG
import Foundation
import SwiftData

/// Proof that two devices holding the same sightings compute the same game.
///
/// Run with `-partyMergeCheck`, in the style of `-demoData` and `-noCloud`: it is
/// opt-in, compiled out of Release entirely, and it never touches the real store —
/// both ends are in-memory containers and the tombstones are the memory-only kind.
///
/// This exists because the interesting failure in a party is not a crash. It is two
/// phones quietly disagreeing: the same trip showing Mia's chip here and Theo's
/// there, or totals a point apart, with neither screen looking wrong. That class of
/// bug is invisible unless something compares every derived answer on both sides,
/// which is exactly what this does — and it does it before a single line of
/// networking exists, when the merge is still the only thing that could be at fault.
enum PartyMergeCheck {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-partyMergeCheck")
    }

    private static var failures: [String] = []

    @MainActor
    static func run() {
        failures = []
        print("── party merge check ──")

        do {
            try roundTripPreservesEveryDerivedNumber()
            try applyingTwiceChangesNothing()
            try removalsStickThroughAResnapshot()
            try tiesResolveTheSameWhateverTheOrder()
            try datesSurviveTheWire()
        } catch {
            failures.append("threw: \(error)")
        }

        if failures.isEmpty {
            print("── party merge check: PASS ──")
        } else {
            print("── party merge check: FAIL (\(failures.count)) ──")
            failures.forEach { print("   ✗ \($0)") }
        }
    }

    // MARK: - The cases

    /// The headline: a snapshot rebuilt on a peer must produce an identical game,
    /// not merely the same plates. Counts, per-player scores, standings order, who
    /// is credited, and what each plate was first claimed at.
    @MainActor
    private static func roundTripPreservesEveryDerivedNumber() throws {
        let source = try makeStore()
        let fixture = install(into: source)

        let sent = try wire(snapshotOf: fixture, in: source)
        let peer = try makeStore()
        PartyMerge.apply(sent, into: peer, tombstones: PartyTombstones(url: nil))

        check("round trip", fingerprint(in: source), fingerprint(in: peer))
    }

    /// Every reconnect re-sends everything. If that were not a no-op the grid would
    /// grow a duplicate of every plate each time somebody's phone woke up.
    @MainActor
    private static func applyingTwiceChangesNothing() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let sent = try wire(snapshotOf: fixture, in: source)

        let peer = try makeStore()
        let tombstones = PartyTombstones(url: nil)
        let first = PartyMerge.apply(sent, into: peer, tombstones: tombstones)
        let after = fingerprint(in: peer)

        let second = PartyMerge.apply(sent, into: peer, tombstones: tombstones)
        check("second apply adds nothing", second.sightingsAdded, 0)
        check("second apply adds no players", second.playersAdded, 0)
        check("second apply is idempotent", after, fingerprint(in: peer))
        check("first apply did land", first.sightingsAdded > 0, true)
    }

    /// The case tombstones exist for. A peer un-taps a plate; somebody who never
    /// heard about it reconnects and re-sends a snapshot that still contains it.
    /// Without the withdrawal recorded, the plate comes back.
    @MainActor
    private static func removalsStickThroughAResnapshot() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let sent = try wire(snapshotOf: fixture, in: source)

        let peer = try makeStore()
        let tombstones = PartyTombstones(url: nil)
        PartyMerge.apply(sent, into: peer, tombstones: tombstones)

        // Take back every sighting of one plate, the way `GameScreen.clear` does.
        let doomed = fixture.sightings
            .filter { $0.plateCode == fixture.plateToRemove }
            .map(\.id)
        check("fixture has something to remove", doomed.isEmpty, false)

        let removal = PartyEnvelope(.remove(RemovalEvent(tripID: fixture.tripID,
                                                         sightingIDs: doomed)))
        let outcome = PartyMerge.apply(removal, into: peer, tombstones: tombstones)
        check("removal deleted rows", outcome.sightingsRemoved, doomed.count)
        check("plate is gone", codes(in: peer).contains(fixture.plateToRemove), false)

        // The stale snapshot arrives again, still carrying the withdrawn plate.
        PartyMerge.apply(sent, into: peer, tombstones: tombstones)
        check("plate stays gone after a stale snapshot",
              codes(in: peer).contains(fixture.plateToRemove), false)
    }

    /// The reason `SightingOrder` exists. Two sightings stamped the same instant
    /// must resolve to the same winner on every device, whatever order the rows
    /// happen to arrive in or sit in the relationship array.
    @MainActor
    private static func tiesResolveTheSameWhateverTheOrder() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        guard case .hello(var snapshot) = try snapshotEnvelope(of: fixture, in: source).payload
        else { return check("snapshot payload", false, true) }

        let forwards = try makeStore()
        PartyMerge.apply(PartyEnvelope(.hello(snapshot)),
                         into: forwards, tombstones: PartyTombstones(url: nil))

        snapshot.sightings.reverse()
        snapshot.players.reverse()
        let backwards = try makeStore()
        PartyMerge.apply(PartyEnvelope(.hello(snapshot)),
                         into: backwards, tombstones: PartyTombstones(url: nil))

        check("insert order does not change the game",
              fingerprint(in: forwards), fingerprint(in: backwards))
        check("insert order matches the source",
              fingerprint(in: source), fingerprint(in: backwards))
    }

    /// `spottedAt` is half of `SightingOrder`, so a lossy date strategy would desync
    /// the two devices while looking perfectly reasonable in a debugger.
    @MainActor
    private static func datesSurviveTheWire() throws {
        // A deliberately awkward instant: sub-millisecond, not a round number.
        let awkward = Date(timeIntervalSinceReferenceDate: 774_312_345.678_912_3)
        let event = SightingEvent(id: UUID(), plateCode: "OH", spottedAt: awkward,
                                  tripID: UUID(), playerID: nil,
                                  rarityWhenSpotted: 4, spottedLat: nil, spottedLon: nil)

        let data = try PartyEnvelope(.sighting(event)).encoded()
        guard let decoded = try PartyEnvelope.decoded(from: data),
              case .sighting(let back) = decoded.payload
        else { return check("sighting decodes", false, true) }

        check("date is bit-exact after a round trip",
              back.spottedAt.timeIntervalSinceReferenceDate,
              awkward.timeIntervalSinceReferenceDate)
        check("payload is unchanged", back, event)

        // A newer peer's protocol must be refused, not half-understood.
        let future = try PartyEnvelope(.bye, v: PartyEnvelope.currentVersion + 1).encoded()
        check("a newer version is refused", try PartyEnvelope.decoded(from: future) == nil, true)
    }

    // MARK: - The fixture

    private struct Fixture {
        var tripID: UUID
        var sightings: [SightingEvent]
        var plateToRemove: String
    }

    /// Deliberately nastier than `DemoData`: the point is the awkward cases, not a
    /// pretty screenshot. Same-instant collisions on two different plates, a
    /// sighting nobody owns, a repeat, and plates with and without a coordinate.
    @MainActor
    private static func install(into context: ModelContext) -> Fixture {
        let players = [Player(name: "Dad", colorIndex: 0),
                       Player(name: "Mia", colorIndex: 1),
                       Player(name: "Theo", colorIndex: 2)]
        players.forEach(context.insert)

        let trip = Trip(name: "Party Test", origin: "Newark", destination: "San Diego",
                        scoringMode: .weighted)
        trip.originLat = 40.7357; trip.originLon = -74.1724
        trip.destinationLat = 32.7157; trip.destinationLon = -117.1611
        trip.startedAt = Date(timeIntervalSinceReferenceDate: 774_000_000)
        context.insert(trip)

        // These land at distinct times and cover the ordinary path.
        let ordinary = ["CA", "NV", "UT", "AZ", "CO", "TX", "MT", "ON"]
        for (offset, code) in ordinary.enumerated() {
            let s = Sighting(plateCode: code, trip: trip,
                             player: players[offset % players.count],
                             spottedAt: trip.startedAt.addingTimeInterval(Double(offset) * 600))
            s.rarityWhenSpotted = PlateRarity.rarity(code, on: trip.route)
            if offset.isMultiple(of: 2) {
                s.spottedLat = 39.7392 + Double(offset) * 0.1
                s.spottedLon = -104.9903 - Double(offset) * 0.1
            }
            context.insert(s)
        }

        // Two people call the same plate at the same instant. Nothing but the id
        // separates them, which is the whole point — `spotter` has to pick one and
        // both devices have to pick the *same* one.
        let together = trip.startedAt.addingTimeInterval(9_000)
        for player in [players[1], players[2]] {
            let s = Sighting(plateCode: "WY", trip: trip, player: player, spottedAt: together)
            s.rarityWhenSpotted = PlateRarity.rarity("WY", on: trip.route)
            context.insert(s)
        }

        // The same collision, but on the number that feeds the *score*: two claims
        // at one instant carrying different banked rarities. `claimedRarity` takes
        // the first, so the tie-break decides what the trip is worth.
        for (offset, player) in [players[0], players[1]].enumerated() {
            let s = Sighting(plateCode: "AK", trip: trip, player: player, spottedAt: together)
            s.rarityWhenSpotted = 9 + offset      // 9 on one, 10 on the other
            context.insert(s)
        }

        // Nobody's plate: legal, and the merge has to carry a nil player through.
        let orphan = Sighting(plateCode: "HI", trip: trip, player: nil,
                              spottedAt: trip.startedAt.addingTimeInterval(12_000))
        orphan.rarityWhenSpotted = 8
        context.insert(orphan)

        // A repeat of something already seen, so counts are not all 1.
        let again = Sighting(plateCode: "CA", trip: trip, player: players[2],
                             spottedAt: trip.startedAt.addingTimeInterval(15_000))
        again.rarityWhenSpotted = 2
        context.insert(again)

        try? context.save()

        return Fixture(tripID: trip.id,
                       sightings: trip.allSightings.compactMap(PartyMerge.event(for:)),
                       plateToRemove: "CA")   // has two sightings — both must go
    }

    // MARK: - Comparing two stores

    /// Every derived answer the app would show, as sorted text.
    ///
    /// Text rather than a struct so a failure prints as a readable diff, and *every*
    /// number rather than just the totals: two phones agreeing on "14 plates" while
    /// disagreeing about who spotted three of them is exactly the bug this is for.
    /// Players are named rather than referenced, since the objects differ per store.
    @MainActor
    private static func fingerprint(in context: ModelContext) -> [String] {
        guard let trip = (try? context.fetch(FetchDescriptor<Trip>()))?.first else {
            return ["<no trip>"]
        }
        let players = ((try? context.fetch(FetchDescriptor<Player>())) ?? [])
            .sorted { $0.joinedAt == $1.joinedAt
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.joinedAt < $1.joinedAt }
        let index = trip.plateIndex()

        var lines: [String] = []

        for code in Set(trip.allSightings.map(\.plateCode)).sorted() {
            let spotter = index.spotter(code)?.name ?? "—"
            let claimed = trip.claimedRarity(of: code).map(String.init) ?? "—"
            lines.append("plate \(code) count=\(index.count(code)) "
                         + "spotter=\(spotter) claimed=\(claimed) "
                         + "rarity=\(trip.rarity(of: code))")

            // `PlateIndex` and the accessor are two implementations of "who spotted
            // this", and their doc comments each claim to match the other. Tie-broken
            // separately, so a change to one and not the other would show up here
            // rather than as a chip that disagrees with itself on one screen.
            let viaAccessor = Plate.plate(for: code).flatMap { trip.spotter(of: $0)?.name } ?? "—"
            lines.append("plate \(code) spotterViaAccessor=\(viaAccessor)")
        }

        for player in players {
            lines.append("player \(player.name) colour=\(player.colorIndex) "
                         + "score=\(trip.score(for: player))")
        }

        for (rank, entry) in trip.standings(among: players).enumerated() {
            lines.append("standing \(rank) \(entry.player.name) \(entry.score)")
        }

        lines.append("trip name=\(trip.name) mode=\(trip.scoringModeRaw) "
                     + "trucks=\(trip.includesTrucks) "
                     + "states=\(trip.statesFound) plates=\(trip.platesFound) "
                     + "score=\(trip.score)")
        lines.append("trip route=\(trip.routeLabel ?? "—") "
                     + "origin=\(trip.originLat ?? 0),\(trip.originLon ?? 0)")

        // Coordinates travel too — the Trail is drawn from them.
        for sighting in trip.allSightings.sorted(by: { SightingOrder($0) < SightingOrder($1) }) {
            lines.append("sighting \(sighting.plateCode) at=\(sighting.spottedAt.timeIntervalSinceReferenceDate) "
                         + "by=\(sighting.player?.name ?? "—") "
                         + "banked=\(sighting.rarityWhenSpotted.map(String.init) ?? "—") "
                         + "loc=\(sighting.spottedLat.map { String(format: "%.4f", $0) } ?? "—"),"
                         + "\(sighting.spottedLon.map { String(format: "%.4f", $0) } ?? "—")")
        }

        return lines
    }

    @MainActor
    private static func codes(in context: ModelContext) -> Set<String> {
        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        return Set(sightings.map(\.plateCode))
    }

    // MARK: - Plumbing

    @MainActor
    private static func makeStore() throws -> ModelContext {
        let schema = Schema([Trip.self, Book.self, Player.self, Sighting.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor
    private static func snapshotEnvelope(of fixture: Fixture,
                                         in context: ModelContext) throws -> PartyEnvelope {
        let id = fixture.tripID
        guard let trip = try context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first else {
            throw CheckError.missingTrip
        }
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        return PartyEnvelope(.hello(PartyMerge.snapshot(of: trip,
                                                        players: players,
                                                        hostPlayerID: players.first?.id,
                                                        tombstones: PartyTombstones(url: nil))))
    }

    /// Deliberately goes through `Data` rather than handing the struct over
    /// directly: encoding is where a lossy date strategy or a field nobody added to
    /// `Codable` would be lost, and a check that skipped it would pass anyway.
    @MainActor
    private static func wire(snapshotOf fixture: Fixture,
                             in context: ModelContext) throws -> PartyEnvelope {
        let data = try snapshotEnvelope(of: fixture, in: context).encoded()
        guard let decoded = try PartyEnvelope.decoded(from: data) else {
            throw CheckError.refusedItsOwnEnvelope
        }
        return decoded
    }

    private enum CheckError: Error { case missingTrip, refusedItsOwnEnvelope }

    // MARK: - Assertions

    private static func check<T: Equatable>(_ label: String, _ got: T, _ want: T) {
        guard got != want else { return }
        failures.append("\(label): got \(got), want \(want)")
    }

    private static func check(_ label: String, _ got: [String], _ want: [String]) {
        guard got != want else { return }
        let extra = Set(got).subtracting(want).sorted()
        let missing = Set(want).subtracting(got).sorted()
        failures.append("\(label): \(missing.count) missing, \(extra.count) unexpected")
        missing.prefix(6).forEach { failures.append("      want: \($0)") }
        extra.prefix(6).forEach { failures.append("      got:  \($0)") }
    }
}
#endif
