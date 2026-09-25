#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData

/// Writes one of everything, so the CloudKit schema can be deployed whole.
///
/// CloudKit creates a field the first time a *non-nil* value for it is exported, and
/// only in the development environment. Production never creates anything on demand.
/// So the development schema is not a picture of the model, it is a picture of
/// whatever the phone that ran last happened to fill in, and deploying it ships a
/// schema with holes exactly where the optional properties are.
///
/// That is not theoretical. The first deploy of `iCloud.com.tagsmedia.tags` carried
/// `CD_Trip` with six fields out of eighteen: a trip that had been started and never
/// finished, never named a destination, never taken a fix and never been archived or
/// pinned. Production would have accepted new trips and rejected the first one
/// somebody ended.
///
/// This fills every optional on every model in one pass, waits for the export to be
/// acknowledged, then deletes what it made. Run it, watch the console, confirm the
/// field lists in CloudKit Console, then deploy.
///
///     xcrun simctl launch --console BOOTED com.tagsmedia.tags -warmSchema
///
/// It has to be a real device signed into iCloud. A simulator has no account, so the
/// export never lands: the run makes its fixtures, waits, reports that nothing
/// reached CloudKit and deletes them again, leaving the schema untouched.
///
/// ## What it touches
///
/// Its fixtures go into the real store, because the mirrored store is the only thing
/// that can talk to CloudKit, and they are therefore briefly visible in the app and
/// on the user's other devices. They live for as long as one export takes and are
/// then deleted. Everything it creates is named `marker` below, nothing else is read
/// or written, and `sweep` clears anything an interrupted earlier run left behind.
/// No existing trip, book, player or sighting is modified or deleted on any path.
@MainActor
enum SchemaWarm {

    /// The name on every object this creates. The sweep is keyed off it, so it has to
    /// be something no player would type, and it has to never change.
    static let marker = "CloudKit Schema Warm"

    static var isRequested: Bool { LaunchFlags.isSet("-warmSchema") }

    // MARK: - The run

    static func run(in context: ModelContext) async {
        log("starting")

        // Named, because there is more than one plausible answer and they are hard to
        // tell apart from outside. Core Data's default directory is the app group
        // container once the app carries an app-groups entitlement, and the plain app
        // container when it does not, so a signed build and an unsigned one keep
        // their plates in different files with the same name. Anyone checking this
        // run against the database wants to be sure which one to open.
        log("store: \(PlatesStore.container.configurations.first?.url.path ?? "unknown")")

        // Before the cloud check, not after it. A run that is interrupted leaves its
        // fixtures behind, and the phone it was interrupted on is exactly the one
        // somebody then runs this on again to tidy up. Gating the sweep on iCloud
        // being up meant the one command that can clear them refused to on a
        // simulator or a signed-out phone, which is where they are likeliest to be
        // sitting.
        sweep(context)

        guard PlatesStore.isCloudBacked else {
            log("the store is not iCloud backed: \(PlatesStore.cloudFailure ?? "no reason reported")")
            log("nothing to warm. Run this on a device signed into iCloud.")
            return
        }

        let fixtures = insert(into: context)
        do {
            try context.save()
        } catch {
            log("FAILED to save the fixtures: \(error)")
            return
        }
        log("inserted 1 trip, 1 book, 1 player and 2 sightings, every optional filled")

        log("waiting up to 3 minutes for the mirrored export")
        var exported = false

        // The export gate is not only about knowing whether the mirrored fields
        // landed. `CKContainer(identifier:)` *traps* when the running build has no
        // entitlement for that container, and a simulator build made without code
        // signing has no entitlements at all, so reaching for the container first
        // takes the app down with SIGTRAP inside CloudKit rather than reporting
        // anything. A completed export is the cheapest proof that the entitlement,
        // the container and the account are all real.
        switch await waitForExport(timeout: 180) {
        case .exported(let when):
            log("export acknowledged at \(when)")
            exported = true
        case .failed(let message):
            log("EXPORT FAILED: \(message)")
            log("skipping SBBook and SBSighting, and removing the fixtures anyway.")
        case .timedOut:
            log("no export event arrived, so nothing here reached iCloud.")
            log("skipping SBBook and SBSighting, and removing the fixtures anyway.")
            log("this is what a simulator does. Run it on a device signed into iCloud.")
        }

        // Built here, used after the fixtures are gone. Turning a model object into
        // a `CKRecord` is a pure function with no network in it, so doing it now
        // costs nothing and means the deletion below does not have to wait on
        // CloudKit. The first device run hung inside the shared-book writes for
        // minutes with the fixtures still sitting in the real store, synced to
        // iCloud, waiting on a call that had no deadline. Cleanup is the one step
        // that must not depend on the network answering.
        let sharedRecords = exported
            ? records(book: fixtures.book, sighting: fixtures.bookSighting)
            : nil

        remove(fixtures, from: context)
        do {
            try context.save()
        } catch {
            log("FAILED to remove the fixtures: \(error)")
            log("they are named \"\(marker)\" and the next -warmSchema run will sweep them.")
            return
        }
        log("fixtures removed")

        var sharedTypesWarmed = false
        if let sharedRecords {
            sharedTypesWarmed = await warmSharedBookTypes(sharedRecords)
        }

        // The launch rebuild in `RootView` runs while the fixtures are alive, so the
        // widget's sidecar can be left counting two plates that no longer exist, and
        // nothing else would rewrite it until the next launch.
        WidgetData.write(from: context)

        report(sharedTypes: sharedTypesWarmed)
    }

    // MARK: - Fixtures

    /// One instance of every model, with no optional left nil.
    ///
    /// Two sightings rather than one because a sighting belongs to a trip *or* a
    /// book, and `CD_book` and `CD_trip` are separate fields. One of each covers both
    /// without giving either sighting a shape the app would never produce.
    private struct Fixtures {
        var player: Player
        var trip: Trip
        var book: Book
        var tripSighting: Sighting
        var bookSighting: Sighting
    }

    private static func insert(into context: ModelContext) -> Fixtures {
        let now = Date()

        let player = Player(name: marker, colorIndex: 0)
        // The two properties added since the first deploy. See the notes on them in
        // `Player`: both are optional with no default, which is the shape CloudKit
        // wants and also the shape that keeps them out of the schema until somebody
        // actually uses them.
        player.avatar = "\u{1F98A}"
        player.blockedAt = now

        // 1970, on everything that is sorted on. The Book screen picks
        // `books.first` when no book has been chosen, sorted by `startedAt` reverse,
        // so a fixture started *now* makes itself the active book on any phone
        // without a stored selection. It reverts when the fixture is deleted, and
        // the right answer is still not to take the screen over for three minutes.
        // The field is written either way, which is all the schema cares about.
        let longAgo = Date(timeIntervalSince1970: 0)

        let trip = Trip(name: marker, origin: "Warm Origin", destination: "Warm Destination")
        trip.startedAt = longAgo
        trip.originLat = 39.9526
        trip.originLon = -75.1652
        trip.destinationLat = 38.9072
        trip.destinationLon = -77.0369
        trip.currentLat = 39.4
        trip.currentLon = -76.6
        trip.locatedAt = now
        trip.endedAt = now
        trip.archivedAt = now
        trip.pinnedAt = now
        // Stored as an Int underneath, and false is not nil, so the field would exist
        // either way. Set true so the value in CloudKit is the non-default one, which
        // is the case worth having proved.
        trip.includesTrucks = true

        let book = Book(name: marker)
        book.startedAt = longAgo
        book.currentLat = 39.4
        book.currentLon = -76.6
        book.locatedAt = now

        let tripSighting = Sighting(plateCode: "DE", trip: trip, player: player)
        tripSighting.rarityWhenSpotted = 4
        tripSighting.spottedLat = 39.4
        tripSighting.spottedLon = -76.6

        let bookSighting = Sighting(plateCode: "AK", trip: nil, player: player)
        bookSighting.book = book
        bookSighting.rarityWhenSpotted = 9
        bookSighting.spottedLat = 39.5
        bookSighting.spottedLon = -76.7

        context.insert(player)
        context.insert(trip)
        context.insert(book)
        context.insert(tripSighting)
        context.insert(bookSighting)

        return Fixtures(player: player, trip: trip, book: book,
                        tripSighting: tripSighting, bookSighting: bookSighting)
    }

    /// Sightings first, by hand.
    ///
    /// `Trip` cascades to its sightings and `Book` and `Player` nullify, so deleting
    /// the containers first would work for the trip's sighting and leave the book's
    /// behind with no book, no player and the marker nowhere on it, which is a
    /// stranded row the sweep could never find again.
    private static func remove(_ fixtures: Fixtures, from context: ModelContext) {
        context.delete(fixtures.tripSighting)
        context.delete(fixtures.bookSighting)
        context.delete(fixtures.trip)
        context.delete(fixtures.book)
        context.delete(fixtures.player)
    }

    /// Anything an earlier run left behind, because it was interrupted or because its
    /// export never came back.
    ///
    /// Matches on the marker name and nothing else, so it can only ever see its own
    /// leavings. A player who names a trip this deserves what happens next.
    private static func sweep(_ context: ModelContext) {
        let name = marker
        var swept = 0

        let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
        for sighting in sightings where sighting.player?.name == name
                                     || sighting.trip?.name == name
                                     || sighting.book?.name == name {
            context.delete(sighting)
            swept += 1
        }

        swept += delete(FetchDescriptor<Trip>(predicate: #Predicate { $0.name == name }), context)
        swept += delete(FetchDescriptor<Book>(predicate: #Predicate { $0.name == name }), context)
        swept += delete(FetchDescriptor<Player>(predicate: #Predicate { $0.name == name }), context)

        guard swept > 0 else { return }
        log("swept \(swept) leftover object(s) from an earlier run")
        try? context.save()
    }

    private static func delete<T: PersistentModel>(_ descriptor: FetchDescriptor<T>,
                                                  _ context: ModelContext) -> Int {
        let found = (try? context.fetch(descriptor)) ?? []
        for object in found { context.delete(object) }
        return found.count
    }

    // MARK: - Waiting for the export

    private enum Outcome {
        case exported(Date)
        case failed(String)
        case timedOut
    }

    /// The only honest signal that CloudKit has taken the data, and the same one
    /// `CloudBackup` reads. An import or a setup event proves the account works,
    /// which is a different claim.
    private static func waitForExport(timeout: TimeInterval) async -> Outcome {
        await withCheckedContinuation { continuation in
            var finished = false
            var observer: NSObjectProtocol?

            func finish(_ outcome: Outcome) {
                guard !finished else { return }
                finished = true
                if let observer { NotificationCenter.default.removeObserver(observer) }
                continuation.resume(returning: outcome)
            }

            observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil, queue: .main
            ) { note in
                guard let event = note.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event,
                      event.type == .export,
                      let ended = event.endDate else { return }

                if let error = event.error {
                    finish(.failed(describe(error)))
                } else {
                    finish(.exported(ended))
                }
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                finish(.timedOut)
            }
        }
    }

    /// Nonisolated because the export observer below is handed its notification on a
    /// plain main-queue closure rather than on the actor, and unwrapping a CKError
    /// touches nothing that needs isolating.
    private nonisolated static func describe(_ error: Error) -> String {
        guard let ck = CloudErrors.meaningful(error) else { return error.localizedDescription }
        return "\(ck.code.rawValue) \(ck.localizedDescription)"
    }

    // MARK: - The hand-rolled types

    private static func records(book: Book,
                                sighting: Sighting) -> (book: CKRecord, sighting: CKRecord) {
        let zoneID = CKRecordZone.ID(zoneName: SharedBookRecords.zoneName,
                                     ownerName: CKCurrentUserDefaultName)
        let bookRecord = SharedBookRecords.record(for: book, in: zoneID)
        let sightingRecord = SharedBookRecords.record(for: sighting, bookID: book.id,
                                                      in: zoneID,
                                                      parent: bookRecord.recordID)
        return (bookRecord, sightingRecord)
    }

    /// Writes the two records, then deletes them, under a deadline.
    ///
    /// Written straight to the private database rather than through
    /// `SharedBookSync`, which would want a real book and a real share. The zone is
    /// left alone afterwards: a real shared book lives in it, and it is not this
    /// code's to remove.
    private static func warmSharedBookTypes(
        _ pair: (book: CKRecord, sighting: CKRecord)) async -> Bool {

        let db = CKContainer(identifier: "iCloud.com.tagsmedia.tags").privateCloudDatabase

        let outcome = await withDeadline(120) {
            do {
                do {
                    _ = try await db.save(CKRecordZone(zoneName: SharedBookRecords.zoneName))
                } catch let error as CKError where error.code == .serverRecordChanged {
                    // Already there, which is the normal case on any phone that has
                    // ever shared a book.
                }

                _ = try await db.modifyRecords(saving: [pair.book, pair.sighting],
                                               deleting: [], savePolicy: .allKeys)
                await log("wrote SBBook and SBSighting")

                _ = try await db.modifyRecords(
                    saving: [], deleting: [pair.sighting.recordID, pair.book.recordID])
                await log("removed the SBBook and SBSighting records")
                return true
            } catch {
                await log("SHARED BOOK TYPES FAILED: \(describe(error))")
                return false
            }
        }

        switch outcome {
        case .some(true):
            return true
        case .some(false):
            log("SBSighting may be missing from the schema. Check it before deploying.")
            return false
        case .none:
            log("GAVE UP on SBBook and SBSighting after 2 minutes with no answer.")
            log("the fixtures are already gone, so nothing is stranded. Run it again.")
            return false
        }
    }

    /// Runs `work`, and stops waiting for it after `seconds`. Nil means the deadline
    /// won.
    ///
    /// Not a promise that the work ends. Cancelling does not reliably unstick a
    /// CloudKit request that has stopped answering, and while the app is suspended
    /// nothing runs at all, timers included. It is a promise that *this* stops
    /// waiting, which is the part the caller depends on.
    private static func withDeadline(_ seconds: TimeInterval,
                                     _ work: @escaping @Sendable () async -> Bool) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Saying what happened

    /// Printed at the end so the console is a checklist rather than a transcript.
    /// Every field named here should now exist in the development schema, and the
    /// point of the run is to compare this list against CloudKit Console before
    /// pressing Deploy.
    private static func report(sharedTypes: Bool) {
        guard sharedTypes else {
            log("done, and nothing reached CloudKit. The schema is unchanged.")
            return
        }
        log("done. Development should now hold:")
        log("  CD_Trip      id name startedAt endedAt scoringModeRaw includesTrucks")
        log("               origin destination originLat originLon destinationLat")
        log("               destinationLon currentLat currentLon locatedAt archivedAt pinnedAt")
        log("  CD_Sighting  id plateCode spottedAt rarityWhenSpotted spottedLat spottedLon")
        log("               trip book player")
        log("  CD_Book      id name startedAt currentLat currentLon locatedAt")
        log("  CD_Player    id name colorIndex joinedAt avatar blockedAt")
        log("  SBBook       name startedAt")
        log("  SBSighting   bookID plateCode spottedAt playerID playerName playerColor")
        log("               playerAvatar rarity")
        log("Check those in CloudKit Console, Development, then Deploy Schema Changes.")
    }

    /// Printed and also appended to `schemawarm.log` beside the store.
    ///
    /// A run takes minutes and ends after the interesting moment has scrolled past,
    /// and on a phone launched from anywhere but Xcode nobody sees `print` at all.
    /// The transcript is the whole output of this tool, so it is worth keeping
    /// somewhere it can be read afterwards.
    private static func log(_ message: String) {
        let line = "[schemawarm] \(message)"
        print(line)

        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask).first else { return }
        let file = directory.appendingPathComponent("schemawarm.log")
        let stamped = "\(Date().formatted(.iso8601)) \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
#endif
