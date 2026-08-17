#if DEBUG
import CloudKit
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

    /// Every case, each run on its own.
    ///
    /// They used to sit in one `do` block, which made the first `throw` silently the
    /// last thing that happened: a store that failed to open in case three took the
    /// other twenty-two with it and printed a single line about case three. Nothing
    /// said how many had been skipped, so a run that checked a tenth of what it
    /// claims to check looked exactly like a run that checked all of it.
    ///
    /// Named here rather than derived, because a case that is written and never
    /// listed is the other way this goes quiet, and the count below is what makes
    /// that visible.
    @MainActor
    private static var cases: [(String, () throws -> Void)] {
        [("round trip", roundTripPreservesEveryDerivedNumber),
         ("applying twice", applyingTwiceChangesNothing),
         ("removals stick", removalsStickThroughAResnapshot),
         ("ties resolve", tiesResolveTheSameWhateverTheOrder),
         ("dates survive", datesSurviveTheWire),
         ("participants are scoped", participantsAreScopedToTheCollection),
         ("rules decide removal", rulesDecideWhoCanTakeAPlateBack),
         ("rules survive the wire", rulesSurviveTheWire),
         ("shared books round trip", sharedBooksRoundTripThroughCloudKitRecords),
         ("closing a trip", closingATripKeepsWhatItShould),
         ("facts never relock", factsNeverRelock),
         ("reminders", remindersOnlyNudgeLiveTrips),
         ("deep links", deepLinksAreTakenOnce),
         ("only the host rewrites", onlyTheHostCanRewriteTheTrip),
         ("mythic roams", mythicIsAboveTheScaleAndRoams),
         ("my name survives", myOwnNameSurvivesAPeersStaleCopy),
         ("an edit is worth saving", anEditIsAChangeWorthSaving),
         ("a contributor's edit", aContributorsEditIsWorthSavingToo),
         ("a book-only page", aBookOnlyPageStillGetsSaved),
         ("me before I have said who I am", iAmStillMeBeforeIHaveSaidWhoIAm),
         ("a zone's token", aZonesTokenOutlivesOneOfItsBooks),
         ("two screens agree", twoScreensAgreeOnWhoFoundIt),
         ("the best find holds still", theBestFindDoesNotMoveBetweenLaunches),
         ("thinning respects its cap", aThinnedPathRespectsItsCap),
         ("suppressed rows", suppressedRowsAreNotCounts),
         ("a flag's value is its own", aFlagsValueBelongsToThatFlag),
         ("a spared card stays spent", aSparedCardStaysSpent),
         ("clearing a trip is a withdrawal", clearingATripIsARealWithdrawal),
         ("a folded plate is not the trip's to delete", aFoldedPlateSurvivesItsTrip)]
    }

    @MainActor
    static func run() {
        failures = []
        print("── party merge check ──")

        // Nothing this run writes reaches the real preferences.
        //
        // The header above promises this file never touches real state, and it was
        // breaking that promise twice. Four cases have to say who this device is,
        // and writing that to `UserDefaults.standard` meant a run that died in the
        // middle left the phone claiming a player that does not exist. Worse,
        // `factsNeverRelock` calls `FactBook.reset()` — which wipes every fact the
        // person holding the phone has ever unlocked, permanently, with nothing to
        // say it happened.
        //
        // So the whole run is pointed at a scratch suite that is thrown away at the
        // end, and each case sets what it needs on the way in rather than restoring
        // on the way out.
        let suite = "com.eggeppel.plates.mergecheck"
        AppDefaults.store = UserDefaults(suiteName: suite) ?? .standard
        // And the widget's file, which is not a preference and so is not covered by
        // the suite above. See `WidgetData.isSuspended`.
        WidgetData.isSuspended = true
        defer {
            AppDefaults.store.removePersistentDomain(forName: suite)
            AppDefaults.store = .standard
            WidgetData.isSuspended = false
        }

        for (name, body) in cases {
            do { try body() }
            catch { failures.append("\(name) threw: \(error)") }
        }

        if failures.isEmpty {
            print("── party merge check: PASS (\(cases.count) cases) ──")
        } else {
            print("── party merge check: FAIL (\(failures.count) in \(cases.count) cases) ──")
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

    /// The standings strip must show the people on *this* trip, not everyone the
    /// store has ever heard of.
    ///
    /// This is a regression test for a bug that shipped. Partying merges the other
    /// phones' players in and keeps them — correctly, since a finished trip has to
    /// still render its standings years later — so scoring against every `Player`
    /// row meant every new trip opened with a strip of everybody from every past
    /// party, all sitting at zero, on a game they were never part of.
    @MainActor
    private static func participantsAreScopedToTheCollection() throws {
        let store = try makeStore()
        _ = install(into: store)

        // Somebody from a previous party: in the store, on none of its trips.
        let stranger = Player(name: "Nan", colorIndex: 4)
        store.insert(stranger)
        let fresh = Trip(name: "A New Drive")
        store.insert(fresh)
        try? store.save()

        let everyone = (try? store.fetch(FetchDescriptor<Player>())) ?? []
        check("the store really does hold a stranger", everyone.count, 4)

        guard let played = (try? store.fetch(FetchDescriptor<Trip>()))?
            .first(where: { !$0.allSightings.isEmpty }) else {
            return check("fixture trip exists", false, true)
        }

        let onTheTrip = played.participants(from: everyone).map(\.name).sorted()
        check("a played trip lists only its own spotters", onTheTrip, ["Dad", "Mia", "Theo"])

        let onTheNewOne = fresh.participants(from: everyone).map(\.name)
        check("a brand new trip lists nobody", onTheNewOne, [])

        // This phone is always playing whatever it is looking at, even before its
        // first find — otherwise you are missing from your own standings.
        let withMe = fresh.participants(from: everyone, me: stranger).map(\.name)
        check("except this phone", withMe, ["Nan"])

        // And anyone in a live party on it, so joiners appear at zero rather than
        // popping into existence on their first plate.
        let joining = Set([stranger.id])
        let withParty = fresh.participants(from: everyone, alsoPlaying: joining).map(\.name)
        check("and whoever has just joined the party", withParty, ["Nan"])
    }

    /// Protected claims: a tap can only take back what you put there.
    @MainActor
    private static func rulesDecideWhoCanTakeAPlateBack() throws {
        let store = try makeStore()
        _ = install(into: store)
        let everyone = (try? store.fetch(FetchDescriptor<Player>())) ?? []
        guard let trip = (try? store.fetch(FetchDescriptor<Trip>()))?
                .first(where: { !$0.allSightings.isEmpty }),
              let dad = everyone.first(where: { $0.name == "Dad" }),
              let mia = everyone.first(where: { $0.name == "Mia" })
        else { return check("rules fixture", false, true) }

        // "CA" is Dad's in the fixture, twice over.
        check("CA is Dad's", trip.hasClaimed("CA", by: dad), true)
        check("CA is not Mia's", trip.hasClaimed("CA", by: mia), false)

        let miaMay = trip.removableSightings(of: "CA", by: mia, protected: true)
        check("Mia cannot take back Dad's plate", miaMay.count, 0)

        let dadMay = trip.removableSightings(of: "CA", by: dad, protected: true)
        check("Dad can take back his own", dadMay.isEmpty, false)

        let unprotected = trip.removableSightings(of: "CA", by: mia, protected: false)
        check("with the rule off, anyone can", unprotected.isEmpty, false)

        // An unowned sighting is nobody's, so it must stay removable or it would be
        // stuck on the board forever.
        let orphan = trip.removableSightings(of: "HI", by: mia, protected: true)
        check("an unowned plate can still be taken back", orphan.isEmpty, false)

        // Shared claims lean on this: two owners, one distinct code.
        let both = trip.plateIndex().claimants("AK").map(\.name).sorted()
        check("a plate claimed twice lists both", both, ["Dad", "Mia"])
        check("but the trip still counts it once", trip.seenCodes.filter { $0 == "AK" }.count, 1)
    }

    /// What "the party is over" does to this phone's copy.
    ///
    /// The two outcomes are opposites and the choice between them is offered by a
    /// popup nobody can tap from a launch argument, so the logic is checked here
    /// instead: finishing must keep every plate, discarding must take the whole copy
    /// and leave no sidecar behind pointing at a trip that no longer exists.
    @MainActor
    private static func closingATripKeepsWhatItShould() throws {
        let store = try makeStore()
        _ = install(into: store)
        let everyone = (try? store.fetch(FetchDescriptor<Player>())) ?? []
        guard let trip = (try? store.fetch(FetchDescriptor<Trip>()))?
                .first(where: { !$0.allSightings.isEmpty }),
              let dad = everyone.first(where: { $0.name == "Dad" })
        else { return check("closing fixture", false, true) }

        // Whose drive is it? The question the discard offer turns on.
        DevicePlayer.adopt(dad)
        check("a player with finds on the trip has some",
              TripClosing.hasOwnFinds(in: trip, players: everyone), true)

        let stranger = Player(name: "Nobody", colorIndex: 5)
        store.insert(stranger)
        DevicePlayer.adopt(stranger)
        check("somebody who spotted nothing has none",
              TripClosing.hasOwnFinds(in: trip, players: everyone + [stranger]), false)

        // Finishing keeps everything and merely files it.
        let plateCount = trip.allSightings.count
        check("the fixture trip has plates", plateCount > 0, true)
        TripClosing.finish(trip, in: store)
        check("finishing ends the trip", trip.endedAt != nil, true)
        // Deliberately *not* archived. Finishing used to do both, and a tester asked
        // for the split: a drive that just ended is the one most worth looking at,
        // so it stays in the list until it is put away on purpose.
        check("finishing does not archive it", trip.isArchived, false)
        check("finishing keeps every plate", trip.allSightings.count, plateCount)
        // The reason the split is safe: pickers filter on `collectable`, so a
        // finished trip leaves them without needing to be archived.
        check("a finished trip is out of the pickers", [trip].collectable.isEmpty, true)
        check("but still in the list", [trip].playable.isEmpty, false)

        // Discarding takes the copy, the plates on it, and the sidecars keyed to it.
        let id = trip.id
        let tombs = PartyTombstones(url: nil)
        tombs.add(trip.allSightings.map(\.id), to: id)
        let before = (try? store.fetchCount(FetchDescriptor<Sighting>())) ?? 0

        TripClosing.discard(trip, in: store)
        let remainingTrips = ((try? store.fetch(FetchDescriptor<Trip>())) ?? [])
            .filter { $0.id == id }
        check("discarding removes the trip", remainingTrips.isEmpty, true)
        let after = (try? store.fetchCount(FetchDescriptor<Sighting>())) ?? 0
        check("discarding takes its sightings with it", after < before, true)
        check("and forgets the ledger entry", PartyLedger.shared.wasParty(id), false)
    }

    /// A fact you have read stays read.
    ///
    /// The rotation pile empties when a region runs dry, and the detail sheet used to
    /// read that same set to decide what was unlocked — so finishing a state's facts
    /// put every one of them back behind a padlock. Reading past the end is exactly
    /// the case, so the check spots a plate more times than it has facts.
    @MainActor
    private static func factsNeverRelock() throws {
        // A region with several facts, so there is a cycle to run off the end of.
        guard let code = PlateFacts.byCode.first(where: { $0.value.count > 2 })?.key else {
            return check("facts fixture", false, true)
        }
        let total = FactBook.total(for: code)
        FactBook.reset()
        check("nothing is unlocked to begin with", FactBook.seenFacts(for: code).count, 0)

        // Twice round the pile, which is where the reshuffle used to wipe it.
        var high = 0
        for _ in 0..<(total * 2 + 1) {
            _ = FactBook.fact(for: code)
            let now = FactBook.seenFacts(for: code).count
            check("unlocked facts never decrease", now >= high, true)
            high = max(high, now)
        }
        check("every fact ends up unlocked", high, total)
        check("and stays unlocked", FactBook.seenFacts(for: code).count, total)
        FactBook.reset()
    }

    /// Which trips earn a reminder, and when.
    ///
    /// Delivery needs a permission grant no launch argument can arrange, so the part
    /// that is checked is the part that can be wrong: an unstarted trip nagging
    /// somebody, a finished one still pending, or a long-cold trip firing the instant
    /// reminders are switched on.
    @MainActor
    private static func remindersOnlyNudgeLiveTrips() throws {
        let store = try makeStore()
        let now = Date()
        let player = Player(name: "Ada", colorIndex: 0)
        store.insert(player)

        func trip(_ name: String, lastSeen: TimeInterval?) -> Trip {
            let t = Trip(name: name)
            store.insert(t)
            if let lastSeen {
                let s = Sighting(plateCode: "NJ", trip: t, player: player,
                                 spottedAt: now.addingTimeInterval(-lastSeen))
                store.insert(s)
            }
            return t
        }

        let live = trip("Live", lastSeen: 60 * 60)          // an hour ago
        let empty = trip("Never started", lastSeen: nil)
        let cold = trip("Long cold", lastSeen: 8 * 24 * 3600)
        let done = trip("Finished", lastSeen: 60 * 60)
        done.endedAt = now
        let filed = trip("Archived", lastSeen: 60 * 60)
        filed.archivedAt = now
        try? store.save()

        let all = [live, empty, cold, done, filed]
        let planned = TripReminders.plan(for: all, now: now)

        check("only the live trip is nudged", planned.map(\.tripID), [live.id])
        check("an unstarted trip is left alone",
              planned.contains { $0.tripID == empty.id }, false)
        check("a trip that went cold long ago does not fire on sight",
              planned.contains { $0.tripID == cold.id }, false)
        check("a finished trip is not abandoned",
              planned.contains { $0.tripID == done.id }, false)
        check("nor is an archived one",
              planned.contains { $0.tripID == filed.id }, false)

        // Twenty-four hours after the last plate, not after the switch was flipped.
        if let nudge = planned.first {
            let expected = now.addingTimeInterval(TripReminders.quiet - 3600)
            check("it fires a day after the last plate",
                  abs(nudge.fireAt.timeIntervalSince(expected)) < 2, true)
            check("and names the trip", nudge.body.contains("Live"), true)
        }
    }

    /// The widget's way back in.
    ///
    /// Whether the app delegate is handed the URL at all cannot be checked from
    /// here — `simctl openurl` raises an "Open in Plates?" confirmation that a real
    /// widget tap does not, and there is no way to press it without a finger. What
    /// *is* checkable is everything after: that only this app's URLs are claimed, and
    /// that a destination is consumed once rather than re-navigating on every return
    /// from the background.
    @MainActor
    private static func deepLinksAreTakenOnce() throws {
        let link = DeepLink.shared
        _ = link.take()

        check("a foreign scheme is not ours",
              link.receive(URL(string: "https://example.com/collect")!), false)
        check("nor is an unknown host",
              link.receive(URL(string: "plates://somewhere")!), false)
        check("nothing pending after either", link.pending == nil, true)

        check("the widget's URL is claimed",
              link.receive(URL(string: "plates://collect")!), true)
        check("and is pending", link.pending != nil, true)
        check("taking it gives the destination", link.take() != nil, true)
        check("and clears it", link.pending == nil, true)
        check("a second take gives nothing", link.take() == nil, true)
    }

    /// Rules are only rules if they reach the other phones.
    @MainActor
    private static func rulesSurviveTheWire() throws {
        var rules = PartyRules.standard
        check("protection is on by default", rules.protectsClaims, true)
        check("shared claims are off by default", rules.sharedClaims, false)

        rules.sharedClaims = true
        let store = try makeStore()
        let fixture = install(into: store)
        let id = fixture.tripID
        guard let trip = try store.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first else {
            return check("trip", false, true)
        }

        let sent = PartyEnvelope(.tripUpdate(PartyMerge.event(for: trip, rules: rules)))
        let data = try sent.encoded()
        guard let back = try PartyEnvelope.decoded(from: data),
              case .tripUpdate(let event) = back.payload else {
            return check("tripUpdate decodes", false, true)
        }
        check("rules arrive intact", event.rules, rules)
    }

    /// Restarting a party must not let a guest close the trip you just reopened.
    ///
    /// The case that motivated the guard, in order: you finish a party trip, later
    /// reopen it from the Trips tab and host it again. A guest joins whose own copy
    /// is still finished. Their greeting carries a whole snapshot — including
    /// `endedAt` from last week — and the merge used to write it straight onto your
    /// row, so your trip closed underneath a party that had only just started and
    /// stopped accepting plates.
    ///
    /// The second half matters as much as the first: the snapshot has to keep landing.
    /// Refusing a guest's whole greeting would fix the rename and lose every plate
    /// they spotted while they were away.
    @MainActor
    private static func onlyTheHostCanRewriteTheTrip() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let peer = try makeStore()
        let tombstones = PartyTombstones(url: nil)

        PartyMerge.apply(try wire(snapshotOf: fixture, in: source),
                         into: peer, tombstones: tombstones)

        let id = fixture.tripID
        guard let theirs = try source.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first,
              let mine = try peer.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first else {
            return check("both stores hold the trip", false, true)
        }

        // The sender's copy diverges the way a guest's does: finished, under the name
        // it had before the rename, and carrying a plate found while they were away.
        theirs.endedAt = Date(timeIntervalSinceReferenceDate: 780_000_000)
        theirs.name = "Their stale copy"
        theirs.includesTrucks.toggle()
        let alone = Sighting(plateCode: "ME", trip: theirs, player: nil,
                             spottedAt: theirs.startedAt.addingTimeInterval(20_000))
        alone.rarityWhenSpotted = 7
        source.insert(alone)
        try? source.save()

        let stale = try wire(snapshotOf: fixture, in: source)
        let name = mine.name
        let trucks = mine.includesTrucks

        PartyMerge.apply(stale, into: peer, tombstones: tombstones, fromHost: false)
        check("a guest cannot end the trip", mine.endedAt, nil)
        check("a guest cannot rename the trip", mine.name, name)
        check("a guest cannot change the rules", mine.includesTrucks, trucks)
        check("a guest's plates land anyway", codes(in: peer).contains("ME"), true)

        // The other door into the same columns. `broadcastTrip` is host-only, so a
        // guest sending one is a guest that has gone around it.
        let pushed = PartyEnvelope(.tripUpdate(PartyMerge.event(for: theirs, rules: .standard)))
        PartyMerge.apply(pushed, into: peer, tombstones: tombstones, fromHost: false)
        check("a guest cannot push a trip update", mine.endedAt, nil)

        // The host says the same thing and it takes — this is how a guest holding a
        // finished copy gets reopened when the host restarts the party.
        PartyMerge.apply(stale, into: peer, tombstones: tombstones, fromHost: true)
        check("the host can end the trip", mine.endedAt, theirs.endedAt)
        check("the host can rename the trip", mine.name, "Their stale copy")
    }

    /// Mythic is a promotion, not a band, and one of its seven slots moves.
    ///
    /// Three separate things can break here and none of them shows up as a crash: the
    /// six permanent regions could fall back into legendary, the roaming slot could
    /// pick a province or one of the permanent six, and — the quiet one — the
    /// routeless fallback table could top out at 10 and never produce a mythic plate
    /// at all for anybody who has not pinned a destination.
    @MainActor
    private static func mythicIsAboveTheScaleAndRoams() throws {
        let newark = PlateRarity.Route(oLat: 40.7, oLon: -74.2)
        let losAngeles = PlateRarity.Route(oLat: 34.05, oLon: -118.25)

        for route in [newark, losAngeles] {
            for code in PlateRarity.mythicAlways {
                check("\(code) is mythic",
                      RarityTier.forRarity(PlateRarity.rarity(code, on: route)), .mythic)
            }
        }

        // The seventh slot: a state, never one of the permanent six, and it has to
        // actually differ somewhere or it is not roaming at all.
        let east = PlateRarity.roamingMythic(on: newark)
        let west = PlateRarity.roamingMythic(on: losAngeles)
        check("east has a roaming mythic", east != nil, true)
        check("west has a roaming mythic", west != nil, true)
        check("roaming pick is a state",
              Plate.plate(for: east ?? "")?.region, .state)
        check("roaming pick is not already mythic",
              PlateRarity.mythicAlways.contains(east ?? ""), false)
        check("roaming pick actually moves with you", east == west, false)

        // Exactly seven, or the promotion is leaking.
        for (label, route) in [("east", newark), ("west", losAngeles)] {
            let count = Plate.all.filter {
                RarityTier.forRarity(PlateRarity.rarity($0.code, on: route)) == .mythic
            }.count
            check("\(label) has seven mythic plates", count, 7)
        }

        // The fallback, which is the one nobody would notice was missing: a trip with
        // no route set still has to be able to show a mythic plate.
        let routeless = Plate.all.filter {
            RarityTier.forRarity(PlateRarity.rarity($0.code, on: nil)) == .mythic
        }.count
        check("routeless trips still reach mythic", routeless, 7)

        // Legendary must survive losing seven regions to the tier above it.
        let legendary = Plate.all.filter {
            RarityTier.forRarity(PlateRarity.rarity($0.code, on: newark)) == .legendary
        }.count
        check("legendary is not emptied", legendary > 5, true)
    }

    /// A shared book, out to `CKRecord`s and back into somebody else's store.
    ///
    /// Records are built in memory, which is the point: the mapping and the merge
    /// are the half of shared books that can be proven without an iCloud account,
    /// and they are also the half where a mistake is silent. A dropped field or a
    /// non-idempotent apply would show up as plates quietly missing from a friend's
    /// copy, weeks later, with nothing in any log.
    @MainActor
    private static func sharedBooksRoundTripThroughCloudKitRecords() throws {
        let mine = try makeStore()
        let zone = CKRecordZone.ID(zoneName: SharedBookRecords.zoneName,
                                   ownerName: CKCurrentUserDefaultName)

        let deb = Player(name: "Aunt Deb", colorIndex: 3)
        mine.insert(deb)
        let book = Book(name: "Shared Book")
        book.startedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        mine.insert(book)

        let codes = ["NJ", "NY", "PA"]
        for (offset, code) in codes.enumerated() {
            let s = Sighting(plateCode: code, in: book, player: deb,
                             spottedAt: book.startedAt.addingTimeInterval(Double(offset) * 3_600))
            s.rarityWhenSpotted = 4 + offset
            s.spottedLat = 40.7 + Double(offset) / 100
            s.spottedLon = -74.1
            mine.insert(s)
        }
        // One nobody owns, which must survive the trip as unowned rather than being
        // invented an author.
        let orphan = Sighting(plateCode: "DE", in: book, player: nil,
                              spottedAt: book.startedAt.addingTimeInterval(9_999))
        mine.insert(orphan)
        try? mine.save()

        // Out.
        let outgoing = SharedBookMerge.outgoing(for: book)
        let bookRecord = SharedBookRecords.record(for: outgoing.book, in: zone)
        let sightingRecords = outgoing.sightings.map {
            SharedBookRecords.record(for: $0, bookID: book.id, in: zone,
                                     parent: bookRecord.recordID)
        }
        check("every sighting became a record", sightingRecords.count, 4)
        check("sightings hang off the book, so one share covers them",
              sightingRecords.allSatisfy { $0.parent?.recordID == bookRecord.recordID }, true)

        // Back, on somebody else's phone.
        guard let fields = SharedBookRecords.book(from: bookRecord) else {
            return check("book record decodes", false, true)
        }
        let decoded = sightingRecords.compactMap(SharedBookRecords.sighting(from:))
        check("every record decoded", decoded.count, 4)

        let theirs = try makeStore()
        var bookOutcome = SharedBookMerge.Outcome()
        SharedBookMerge.apply(book: fields, into: theirs, outcome: &bookOutcome)
        check("a book arriving is a change worth saving", bookOutcome.bookChanged, true)
        let first = SharedBookMerge.apply(decoded, into: theirs, carrying: bookOutcome)
        check("all four landed", first.sightingsAdded, 4)
        check("the contributor was created once", first.contributorsAdded, 1)

        guard let copy = (try? theirs.fetch(FetchDescriptor<Book>()))?.first else {
            return check("book exists on the other side", false, true)
        }
        check("book name travelled", copy.name, "Shared Book")
        check("plates travelled", copy.seenCodes.sorted(), ["DE", "NJ", "NY", "PA"])
        check("banked rarity travelled", copy.claimedRarity(of: "NY"), 5)
        check("the contributor is named", copy.plateIndex().spotter("NJ")?.name, "Aunt Deb")
        check("an unowned plate stays unowned", copy.plateIndex().spotter("DE")?.name, nil)
        check("coordinates travelled",
              copy.allSightings.filter { $0.spottedLat != nil }.count, 3)

        // The whole batch again — every sync delivers what it already delivered.
        let second = SharedBookMerge.apply(decoded, into: theirs)
        check("re-applying adds nothing", second.sightingsAdded, 0)
        check("and invents no second contributor", second.contributorsAdded, 0)
        check("the book is unchanged", copy.seenCodes.count, 4)

        // A withdrawal, which CloudKit reports as a deleted record id.
        let removed = SharedBookMerge.apply([], removing: [orphan.id], into: theirs)
        check("the deletion applied", removed.sightingsRemoved, 1)
        check("and the plate is gone", copy.seenCodes.sorted(), ["NJ", "NY", "PA"])
    }

    /// A rename must not be undone by somebody else's memory of you.
    ///
    /// Every peer's copy of your name is stale the instant you change it — you are
    /// the only device that saw it happen — so a roster arriving from any of them
    /// used to write the old one straight back. The reported symptom was a rename
    /// that reverted itself whenever a new party started on the same trip, which is
    /// simply the next time a snapshot goes out.
    @MainActor
    private static func myOwnNameSurvivesAPeersStaleCopy() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let peer = try makeStore()
        let tombstones = PartyTombstones(url: nil)

        PartyMerge.apply(try wire(snapshotOf: fixture, in: source),
                         into: peer, tombstones: tombstones)

        let roster = try source.fetch(FetchDescriptor<Player>())
        guard let dad = roster.first(where: { $0.name == "Dad" }),
              let mia = roster.first(where: { $0.name == "Mia" }) else {
            return check("fixture roster", false, true)
        }
        // On this device, "Dad" is me and "Mia" is somebody else in the car.
        let me = dad.id, them = mia.id
        claiming(me.uuidString)

        guard let mine = try peer.fetch(
                FetchDescriptor<Player>(predicate: #Predicate { $0.id == me })).first,
              let other = try peer.fetch(
                FetchDescriptor<Player>(predicate: #Predicate { $0.id == them })).first else {
            return check("both players merged", false, true)
        }

        // I rename myself mid-party. Nobody else has heard yet.
        mine.name = "Ethan"
        try? peer.save()

        // A fresh party on the same trip: the host sends everything it remembers,
        // including its out-of-date copy of me — and its up-to-date copy of Mia,
        // who really did change her name on her own phone.
        mia.name = "Mia B"
        try? source.save()
        PartyMerge.apply(try wire(snapshotOf: fixture, in: source),
                         into: peer, tombstones: tombstones)

        check("my rename survives a peer's stale roster", mine.name, "Ethan")
        check("somebody else's rename still lands", other.name, "Mia B")
    }

    /// The save gate has to be able to see an edit.
    ///
    /// Both merges save once per envelope, at the end, and only if the outcome says
    /// something happened — so an outcome that counts inserts and nothing else cannot
    /// see a rename at all. A roster whose whole effect was somebody's new name left
    /// the context dirty, reported empty, and skipped its save; whether the rename
    /// survived came down to whether autosave happened to fire before the process
    /// died. These stores do not have autosave, which is the point: it is the same
    /// guarantee the merge's own contract claims, so the check can hold it to it.
    ///
    /// `hasChanges` is the assertion that matters. The name landing on the object
    /// proves only that the assignment ran; `hasChanges` being false proves it
    /// reached the disk.
    @MainActor
    private static func anEditIsAChangeWorthSaving() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let peer = try makeStore()
        let tombstones = PartyTombstones(url: nil)

        PartyMerge.apply(try wire(snapshotOf: fixture, in: source),
                         into: peer, tombstones: tombstones)

        guard let mia = try source.fetch(FetchDescriptor<Player>())
            .first(where: { $0.name == "Mia" }) else {
            return check("fixture roster", false, true)
        }
        // Nobody this device could mistake for itself, or the ownership guard would
        // drop the edit and this would pass for the wrong reason.
        claiming(UUID().uuidString)

        // A roster and nothing else: no trip, no sightings, nobody new. And one field
        // at a time, because each is its own branch and each has to open the gate on
        // its own — changing two at once passes whichever of them is still broken.
        mia.name = "Mia B"
        let renamed = PartyMerge.apply(PartyEnvelope(.roster([PartyMerge.event(for: mia)])),
                                       into: peer, tombstones: tombstones)

        check("a rename is not an insert", renamed.playersAdded, 0)
        check("but it is a change", renamed.playersChanged, true)
        check("so the envelope is not empty", renamed.isEmpty, false)
        check("and the merge saved it", peer.hasChanges, false)

        var after = try peer.fetch(FetchDescriptor<Player>())
        check("the new name is on the row", after.first { $0.id == mia.id }?.name, "Mia B")

        mia.avatar = "🦊"
        let face = PartyMerge.apply(PartyEnvelope(.roster([PartyMerge.event(for: mia)])),
                                    into: peer, tombstones: tombstones)
        check("picking a face is a change too", face.playersChanged, true)
        check("which also saved", peer.hasChanges, false)
        after = try peer.fetch(FetchDescriptor<Player>())
        check("and the face is on the row", after.first { $0.id == mia.id }?.avatar, "🦊")

        mia.colorIndex = 4
        let recolored = PartyMerge.apply(PartyEnvelope(.roster([PartyMerge.event(for: mia)])),
                                         into: peer, tombstones: tombstones)
        check("so is a color", recolored.playersChanged, true)
        check("which also saved", peer.hasChanges, false)

        // The same roster again. Nothing left to change, so nothing to save.
        let again = PartyMerge.apply(PartyEnvelope(.roster([PartyMerge.event(for: mia)])),
                                     into: peer, tombstones: tombstones)
        check("re-applying a roster changes nothing", again.isEmpty, true)
    }

    /// The same gate on the slower wire, plus the two things a contributor's name
    /// travels through that a party roster does not.
    ///
    /// A shared book has no roster: a contributor's name and face ride on each
    /// sighting instead. That makes the edit path the only path, and it makes the
    /// order records arrive in — dictionary order within a page, which is to say
    /// arbitrary — something the merge has to survive rather than depend on.
    @MainActor
    private static func aContributorsEditIsWorthSavingToo() throws {
        let theirs = try makeStore()
        let bookID = UUID(), contributor = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 774_000_000)

        claiming(UUID().uuidString)

        func sighting(_ code: String, name: String?, avatar: String?) -> SharedSighting {
            SharedSighting(id: UUID(), bookID: bookID, plateCode: code,
                           spottedAt: start, playerID: contributor,
                           playerName: name, playerColorIndex: 2, playerAvatar: avatar)
        }

        var opening = SharedBookMerge.Outcome()
        SharedBookMerge.apply(book: SharedBookRecords.BookFields(id: bookID,
                                                                name: "Shared Book",
                                                                startedAt: start),
                              into: theirs, outcome: &opening)
        SharedBookMerge.apply([sighting("NJ", name: "Deb", avatar: "🦊")],
                              into: theirs, carrying: opening)

        // She renames herself. The next record she pushes carries the new name and
        // nothing else is new.
        let renamed = SharedBookMerge.apply([sighting("NY", name: "Aunt Deb", avatar: "🦊")],
                                            into: theirs)
        check("a contributor's rename is a change", renamed.contributorsChanged, true)
        check("without being a new contributor", renamed.contributorsAdded, 0)
        check("and the page saved", theirs.hasChanges, false)

        guard let deb = try theirs.fetch(FetchDescriptor<Player>()).first else {
            return check("the contributor exists", false, true)
        }
        check("the name landed", deb.name, "Aunt Deb")

        // A record she pushed *before* picking a face. It is older than the emoji but
        // there is no ordering on a page, so the merge cannot let a nil erase one.
        let stale = SharedBookMerge.apply([sighting("PA", name: "Aunt Deb", avatar: nil)],
                                          into: theirs)
        check("an older record does not erase the face", deb.avatar, "🦊")
        check("and is not counted as an edit", stale.contributorsChanged, false)
    }

    /// A page that carries a renamed book and no sightings still has to reach the
    /// disk, because the caller advances the change token past it either way — and
    /// CloudKit will not send that record again.
    @MainActor
    private static func aBookOnlyPageStillGetsSaved() throws {
        let theirs = try makeStore()
        let bookID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 774_000_000)

        var first = SharedBookMerge.Outcome()
        SharedBookMerge.apply(book: SharedBookRecords.BookFields(id: bookID, name: "Book",
                                                                startedAt: start),
                              into: theirs, outcome: &first)
        SharedBookMerge.apply([], into: theirs, carrying: first)

        var renamed = SharedBookMerge.Outcome()
        SharedBookMerge.apply(book: SharedBookRecords.BookFields(id: bookID, name: "Our Book",
                                                                startedAt: start),
                              into: theirs, outcome: &renamed)
        check("the rename is a change worth saving", renamed.bookChanged, true)
        let carried = SharedBookMerge.apply([], into: theirs, carrying: renamed)
        check("which the empty page carries", carried.isEmpty, false)
        check("and saves", theirs.hasChanges, false)
        check("the name landed",
              try theirs.fetch(FetchDescriptor<Book>()).first?.name, "Our Book")
    }

    /// The ownership guard has to work on an install that has never been through the
    /// identity prompt, which is exactly where it used to do nothing.
    ///
    /// `devicePlayerID` is written when a profile is adopted, so before that it is
    /// unset — and an id compared against nil is always unequal, so "is this row me?"
    /// answered no about everybody. A shared book coming back down a zone this
    /// account owns then renamed the user from their own stale record.
    @MainActor
    private static func iAmStillMeBeforeIHaveSaidWhoIAm() throws {
        let theirs = try makeStore()
        let bookID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 774_000_000)

        // The only player on this install, so `DevicePlayer.resolve` lands on them
        // whatever the key says.
        let me = Player(name: "Ethan", colorIndex: 0)
        theirs.insert(me)
        try? theirs.save()

        claiming(nil)

        var opening = SharedBookMerge.Outcome()
        SharedBookMerge.apply(book: SharedBookRecords.BookFields(id: bookID, name: "Shared Book",
                                                                startedAt: start),
                              into: theirs, outcome: &opening)
        // My own record, pushed back at me under the name I used to have.
        SharedBookMerge.apply([SharedSighting(id: UUID(), bookID: bookID, plateCode: "NJ",
                                              spottedAt: start, playerID: me.id,
                                              playerName: "Me", playerColorIndex: 0,
                                              playerAvatar: nil)],
                              into: theirs, carrying: opening)

        check("my own stale record does not rename me", me.name, "Ethan")
    }

    /// Unsharing one book must not break the next one's sync.
    ///
    /// Ledger entries are per book; change tokens are per zone; and every book this
    /// device shares out lives in the same zone. So forgetting a book used to drop a
    /// token its neighbours were still reading — and a pull with no token is told
    /// what exists, never what was deleted, so those books would never hear about a
    /// withdrawal again and would go on re-uploading rows the far side removed.
    ///
    /// Driven through the ledger's own file rather than its API because a
    /// `CKServerChangeToken` cannot be built outside CloudKit. Nothing here needs it
    /// to be a real one: the question is whether the key survives, and the ledger
    /// treats the value as an opaque blob until something asks it to unarchive one.
    @MainActor
    private static func aZonesTokenOutlivesOneOfItsBooks() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedBooksCheck.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = UUID(), second = UUID()
        let zone = "__defaultOwner__/PlatesShared"
        try JSONSerialization.data(withJSONObject: [
            "entries": [
                ["bookID": first.uuidString, "isOwner": true,
                 "zoneName": "PlatesShared", "zoneOwner": "__defaultOwner__"],
                ["bookID": second.uuidString, "isOwner": true,
                 "zoneName": "PlatesShared", "zoneOwner": "__defaultOwner__"]
            ],
            "tokens": [zone: Data("a token".utf8).base64EncodedString()]
        ]).write(to: url)

        let ledger = SharedBookLedger(url: url)
        check("both books loaded", ledger.allShared.count, 2)

        ledger.forget(book: first)
        check("the zone keeps its token while another book reads it",
              tokenKeys(in: url), [zone])

        ledger.forget(book: second)
        check("and drops it once the last one is gone", tokenKeys(in: url), [])
    }

    private static func tokenKeys(in url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any] else { return [] }
        return tokens.keys.sorted()
    }

    /// Two screens drawing the same plate have to name the same people in the same
    /// order, and the answer has to be the same one next launch.
    ///
    /// `PlateIndex` fed the Game grid and `PlateBook` fed the Book screen, and only
    /// one of them ordered the sightings first — so the same two avatars came out in
    /// opposite orders on one device, and the poster baked whichever it was handed
    /// into an image. Both go through `SightingOrder` now, which also settles the
    /// same-instant case that `sorted(by:)` leaves undefined.
    @MainActor
    private static func twoScreensAgreeOnWhoFoundIt() throws {
        let source = try makeStore()
        let fixture = install(into: source)
        let sightings = try source.fetch(FetchDescriptor<Sighting>())

        let index = PlateIndex(sightings)
        let book = PlateBook(sightings: sightings)

        // "WY" is the fixture's deliberate collision: two people at one instant.
        for code in ["WY", "AK", "CA"] {
            check("\(code): the grid and the book agree on the claimants",
                  index.claimants(code).map(\.name),
                  book.entry(for: code)?.spotters.map(\.name) ?? [])
        }

        // Same rows, opposite order in, same answer out. The store hands a
        // relationship back in whatever order it likes, and that is what this used to
        // be a function of.
        check("and the order they arrive in does not decide it",
              PlateIndex(sightings.reversed()).claimants("WY").map(\.name),
              index.claimants("WY").map(\.name))
        _ = fixture
    }

    /// The best find has to be the same plate twice.
    ///
    /// Candidates come out of a `Set`, whose iteration order is seeded per process,
    /// and six plates sit at mythic by design — so two of the four implementations,
    /// the ones with no tie-break, named a different plate between launches and
    /// disagreed with the widget and the poster, which had one. There is one
    /// implementation now.
    @MainActor
    private static func theBestFindDoesNotMoveBetweenLaunches() throws {
        let tied = ["MT", "AK", "HI", "WY"]
        let flat: (String) -> Int = { _ in 9 }

        check("ties resolve to the same plate whatever the order",
              rarestPlate(in: Set(tied), scoredBy: flat)?.code,
              rarestPlate(in: Set(tied.reversed()), scoredBy: flat)?.code)
        check("and it is the one every implementation would pick",
              rarestPlate(in: Set(tied), scoredBy: flat)?.code, "AK")
        check("a clear winner still wins",
              rarestPlate(in: Set(tied)) { $0 == "MT" ? 10 : 9 }?.code, "MT")
        check("nothing found, nothing named",
              rarestPlate(in: Set<String>(), scoredBy: flat)?.code, nil)
    }

    /// Thinning that does not thin.
    ///
    /// `count / limit` is 1 for everything from one over the limit to one under
    /// twice it, so the whole band came through untouched — and `Route` is the memo
    /// key for the rarity table, hashed on every tile of every render.
    @MainActor
    private static func aThinnedPathRespectsItsCap() throws {
        func path(_ n: Int) -> [PlateRarity.Waypoint] {
            (0..<n).map { .init(lat: 40 + Double($0) / 100, lon: -74 - Double($0) / 100) }
        }
        for n in [47, 48, 49, 60, 95, 96, 400] {
            let kept = PlateRarity.Route.thin(path(n))
            check("\(n) points thin to at most the cap", kept.count <= 49, true)
            check("\(n) points keep the destination", kept.last, path(n).last)
            check("\(n) points keep the start", kept.first, path(n).first)
        }
        check("a path already under the cap is untouched",
              PlateRarity.Route.thin(path(20)).count, 20)
    }

    /// A suppression marker is not a household count.
    ///
    /// The IRS writes -1 where a cell is too small to disclose. Parsed as a number it
    /// subtracts from a tie strength that has no meaning below zero.
    @MainActor
    /// The bug this exists for: `-target past` selected the finished trip by asking
    /// whether the *word* "past" appeared anywhere in the command line. It does not
    /// have to belong to `-target`, or to any flag — `-tab past` did it, and so did a
    /// value meant for something else entirely. Reading the token after the flag is
    /// the whole fix, and this is the case that would have caught it: "past" is in
    /// the arguments both times, and only one of them is `-target`'s.
    private static func aFlagsValueBelongsToThatFlag() throws {
        let mine = ["Plates", "-target", "past", "-tab", "map"]
        check("the value after the flag",
              LaunchFlags.value(after: "-target", in: mine), "past")
        check("and not somebody else's",
              LaunchFlags.value(after: "-tab", in: mine), "map")

        let borrowed = ["Plates", "-tab", "past"]
        check("a bare token belongs to no flag",
              LaunchFlags.value(after: "-target", in: borrowed), nil)

        check("a flag with nothing after it",
              LaunchFlags.value(after: "-target", in: ["Plates", "-target"]), nil)
        check("a flag that is not there",
              LaunchFlags.value(after: "-target", in: ["Plates"]), nil)
        check("a value that looks like a flag is still a value",
              LaunchFlags.value(after: "-rarityDump", in: ["Plates", "-rarityDump", "-33.9,18.4"]),
              "-33.9,18.4")
        check("a flag on its own", LaunchFlags.isSet("-foundAll", in: ["Plates", "-foundAll"]), true)
        check("and one that is not", LaunchFlags.isSet("-foundAll", in: ["Plates"]), false)
    }

    /// `Coach` and `Tour` keep their ledgers in the same drawer now, and the one
    /// behaviour that is not shared is the welcome card: replaying the tips must not
    /// re-run the first-launch card over an app somebody has used for a year, and
    /// "Replay the tour" must. Both directions, because a `sparing:` set that is
    /// ignored and one that is always applied each break exactly one of them.
    private static func aSparedCardStaysSpent() throws {
        Coach.markAllSeen()
        check("every tip is spent", Coach.Tip.allCases.allSatisfy(Coach.seen), true)

        Coach.reset()
        check("the welcome card is not handed back", Coach.seen(.welcome), true)
        check("but the tips are", Coach.seen(.firstTap), false)

        Coach.markAllSeen()
        Coach.reset(includingWelcome: true)
        check("and Replay the tour hands back everything", Coach.seen(.welcome), false)

        // Two ledgers, one drawer: they must not be able to read each other's keys.
        Tour.markAllSeen()
        Coach.reset(includingWelcome: true)
        check("Coach's reset leaves the tours alone", Tour.seen(.game), true)
        Tour.reset()
        check("and the tours can be handed back on their own", Tour.seen(.game), false)
    }

    /// "Clear plates" was the fourth copy of "delete some sightings" and the one
    /// the consolidation missed. Without the tombstones the wipe did not even hold:
    /// the next snapshot from any peer put every plate back, because nothing on this
    /// phone could say they had been taken away on purpose.
    @MainActor
    private static func clearingATripIsARealWithdrawal() throws {
        let store = try makeStore()
        let fixture = install(into: store)
        let trip = try tripOf(store, fixture.tripID)

        check("the fixture has plates to clear", trip.allSightings.count > 0, true)

        PlateLogger.withdraw(trip.allSightings, from: trip, context: store)
        check("and the trip is empty", trip.allSightings.count, 0)
        // The only assertion that separates "the rows were unlinked" from "it
        // reached the disk" — the harness's own contexts do not autosave.
        check("and the emptying was saved", store.hasChanges, false)

        // What this case cannot reach: the party broadcast and the tombstones it
        // writes both go through `PartySession.shared`, which is nil with no party
        // running, so the half of the bug that made a wipe undo itself is verified
        // by reading rather than here. That unreachability is a fair part of why it
        // survived four passes.
    }

    /// A folded plate lives in two containers, and taking it out of one is not
    /// permission to reach into the other. `TripClosing.discard` wrote that rule out
    /// in full; it applied on one side only, so emptying a trip silently shrank
    /// every book its plates had been filed in.
    @MainActor
    private static func aFoldedPlateSurvivesItsTrip() throws {
        let store = try makeStore()
        let fixture = install(into: store)
        let trip = try tripOf(store, fixture.tripID)

        let book = Book(name: "The Shelf")
        store.insert(book)
        let folded = Array(trip.allSightings.prefix(2))
        for sighting in folded { sighting.book = book }
        try? store.save()
        check("two plates are on the shelf", book.allSightings.count, 2)

        PlateLogger.withdraw(trip.allSightings, from: trip, context: store)
        check("the trip gave up everything", trip.allSightings.count, 0)
        check("but the book kept what was filed in it", book.allSightings.count, 2)
        check("and those rows belong to nobody else now",
              book.allSightings.allSatisfy { $0.trip == nil }, true)
    }

    /// `first` where the fetch is by id, so a case reads as one line.
    @MainActor
    private static func tripOf(_ store: ModelContext, _ id: UUID) throws -> Trip {
        let found = (try? store.fetch(FetchDescriptor<Trip>()))?.first { $0.id == id }
        guard let found else { throw CheckTrouble.noTrip }
        return found
    }

    private enum CheckTrouble: Error { case noTrip }

    private static func suppressedRowsAreNotCounts() throws {
        // The three rows that carry it, from the packed table.
        for (from, to) in [("VT", "ND"), ("WY", "DE"), ("WY", "RI")] {
            check("\(from)->\(to) is not a count", PlateMigration.flows[from]?[to], nil)
        }
        check("so no tie strength goes negative",
              PlateMigration.ties(of: "WY", near: "DE") >= 0, true)
        check("and real flows still parsed", PlateMigration.flows["CA"]?["NJ"] != nil, true)
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
            lines.append("player \(player.name) color=\(player.colorIndex) "
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
                                                        rules: .standard,
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

    /// Says who this device is, for the rest of the case.
    ///
    /// Four cases need it and each had its own copy: read the old value, write a new
    /// one, restore it in a `defer`. Not restoring it here at all is the point — the
    /// whole run is pointed at a scratch suite that `run()` throws away, and each
    /// case sets what it needs on the way in. Passing nil is a real state and the one
    /// the ownership guard was silently broken on: a device that has never been
    /// through the identity prompt.
    @MainActor
    private static func claiming(_ id: String?) {
        if let id { AppDefaults.store.set(id, forKey: DevicePlayer.key) }
        else { AppDefaults.store.removeObject(forKey: DevicePlayer.key) }
    }

    // MARK: - Assertions

    private static func check<T: Equatable>(_ label: String, _ got: T, _ want: T) {
        guard got != want else { return }
        failures.append("\(label): got \(got), want \(want)")
    }

    private static func check(_ label: String, _ got: [String], _ want: [String]) {
        guard got != want else { return }
        let extra = Set(got).subtracting(want).sorted()
        let missing = Set(want).subtracting(got).sorted()
        // Said outright, because the set difference cannot say it: two lists holding
        // the same names in different orders reported "0 missing, 0 unexpected",
        // which reads like a passing check that failed anyway. Order is the whole
        // point of some of these.
        guard !missing.isEmpty || !extra.isEmpty else {
            return failures.append(
                "\(label): same entries, different order — got \(got), want \(want)")
        }
        failures.append("\(label): \(missing.count) missing, \(extra.count) unexpected")
        missing.prefix(6).forEach { failures.append("      want: \($0)") }
        extra.prefix(6).forEach { failures.append("      got:  \($0)") }
    }
}
#endif
