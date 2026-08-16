import CloudKit
import Foundation
import SwiftData

/// Pushing a shared book up and pulling other people's contributions down.
///
/// Explicit `CKDatabase` operations rather than `CKSyncEngine`. The engine does
/// more and would be the right answer for a large mutable dataset, but it also owns
/// its own scheduling and serialized state, and this code has to be written before
/// it can ever be run — no simulator has an iCloud account, and sharing needs two
/// Apple IDs on two devices. Given that, the thing worth optimising for is being
/// *readable enough to check by eye*: fetch changes with a token, apply them, save
/// records, handle the handful of errors that actually happen. A book is a few
/// hundred small records, so nothing here needs to be clever.
///
/// **Not verified against a live container.** Every line below compiles and follows
/// the documented shapes, and none of it has round-tripped a real record. Treat the
/// first device run as the real test — see `PlatesStore`'s warning about what
/// CloudKit failures look like when they only appear in TestFlight.
@MainActor
@Observable
final class SharedBookSync {

    static let shared = SharedBookSync()

    private let container = CKContainer(identifier: "iCloud.com.eggeppel.plates")
    private let ledger = SharedBookLedger.shared

    /// Surfaced rather than swallowed: "sharing is not working" with no reason is
    /// unactionable, and CloudKit's failures are mostly things a person can fix
    /// (signed out, no network, storage full).
    private(set) var trouble: String?
    private(set) var isBusy = false

    private var zoneEnsured = false

    // MARK: - The zone

    /// Created once, lazily. Records in the default zone cannot be shared at all,
    /// so everything a shared book touches lives here.
    private func ensureZone() async throws {
        guard !zoneEnsured else { return }
        let zone = CKRecordZone(zoneName: SharedBookRecords.zoneName)
        do {
            _ = try await container.privateCloudDatabase.save(zone)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Already there. Saving an existing zone is not an error worth raising.
        }
        zoneEnsured = true
        log("zone \(SharedBookRecords.zoneName) ready")
    }

    private var ownZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SharedBookRecords.zoneName,
                        ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - Sharing one out

    /// Puts the book and everything in it into the shared zone and returns the
    /// `CKShare` for `UICloudSharingController` to present.
    ///
    /// The share is saved together with the root record in one operation, which is
    /// required: CloudKit will not accept a share whose root does not exist yet, and
    /// doing it in two steps leaves a window where a crash orphans one of them.
    func makeShare(for book: Book) async throws -> (CKShare, CKContainer) {
        isBusy = true
        defer { isBusy = false }
        try await ensureZone()

        let db = container.privateCloudDatabase
        let root = SharedBookRecords.record(for: book, in: ownZoneID)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = book.name as CKRecordValue
        share.publicPermission = .none        // invited people only

        // `.changedKeys` rather than the default. The default refuses to write a
        // record the server already has a different version of, which is exactly the
        // case when somebody shares a book, stops, and shares it again — the root
        // record is still up there from last time and the second attempt would fail
        // with a conflict nobody could act on.
        _ = try await db.modifyRecords(saving: [root, share], deleting: [],
                                       savePolicy: .changedKeys)
        log("shared \(book.name): root + share saved")

        ledger.note(.init(bookID: book.id, isOwner: true,
                          zoneName: ownZoneID.zoneName,
                          zoneOwner: ownZoneID.ownerName))

        // The plates already in the book have to follow it up, or the invitation
        // arrives pointing at an empty shelf.
        try await pushAll(book)
        return (share, container)
    }

    /// Everything currently in the book. Used right after sharing, and as the
    /// repair path if a device thinks it has fallen behind.
    func pushAll(_ book: Book) async throws {
        guard let entry = ledger.entry(for: book.id) else { return }
        let zone = CKRecordZone.ID(zoneName: entry.zoneName, ownerName: entry.zoneOwner)
        let root = SharedBookRecords.recordID(for: book.id, in: zone)
        let records = book.allSightings.map {
            SharedBookRecords.record(for: $0, bookID: book.id, in: zone, parent: root)
        }
        try await save(records, to: database(for: entry))
    }

    // MARK: - Ordinary traffic

    /// One plate, just logged into a shared book. Fire-and-forget: a failure here
    /// is recoverable by the next `pushAll`, and blocking the tap on a network
    /// round trip would make the grid feel broken on a bad connection.
    func push(_ sighting: Sighting, in book: Book) {
        guard let entry = ledger.entry(for: book.id) else { return }
        let zone = CKRecordZone.ID(zoneName: entry.zoneName, ownerName: entry.zoneOwner)
        let record = SharedBookRecords.record(
            for: sighting, bookID: book.id, in: zone,
            parent: SharedBookRecords.recordID(for: book.id, in: zone))

        Task { [weak self] in
            do {
                try await self?.save([record], to: self?.database(for: entry))
                self?.log("pushed \(sighting.plateCode)")
            } catch {
                self?.trouble = Self.explain(error)
                self?.log("push failed for \(sighting.plateCode): \(error)")
            }
        }
    }

    /// A plate taken back. CloudKit's own deletion *is* the tombstone — a peer
    /// learns about it as a deleted record id on its next pull — so there is no
    /// sidecar to maintain here, unlike the party.
    func remove(_ ids: [UUID], in book: Book) {
        guard let entry = ledger.entry(for: book.id) else { return }
        let zone = CKRecordZone.ID(zoneName: entry.zoneName, ownerName: entry.zoneOwner)
        let doomed = ids.map { SharedBookRecords.recordID(for: $0, in: zone) }

        Task { [weak self] in
            guard let db = self?.database(for: entry) else { return }
            do {
                _ = try await db.modifyRecords(saving: [], deleting: doomed)
                self?.log("withdrew \(doomed.count)")
            } catch {
                self?.trouble = Self.explain(error)
                self?.log("withdraw failed: \(error)")
            }
        }
    }

    // MARK: - Pulling

    /// Fetch what has changed in every shared book, and merge it.
    ///
    /// Called on launch and on foreground rather than continuously: a shared book is
    /// filled over weeks, not seconds, and polling would spend battery to shorten a
    /// wait nobody is sitting through.
    func pullAll(into context: ModelContext) async {
        for entry in ledger.allShared {
            await pull(entry, into: context)
        }
    }

    private func pull(_ entry: SharedBookLedger.Entry, into context: ModelContext) async {
        let zone = CKRecordZone.ID(zoneName: entry.zoneName, ownerName: entry.zoneOwner)
        let db = database(for: entry)

        var token = ledger.token(zone: entry.zoneName, owner: entry.zoneOwner)

        do {
            // CloudKit pages. `moreComing` means "ask again with the token I just
            // gave you", and ignoring it truncates the pull *silently* — the first
            // fetch of a well-filled book would bring back a page and stop, leaving
            // a participant with a partial collection and nothing to indicate it.
            var more = true
            while more {
                let page = try await db.recordZoneChanges(inZoneWith: zone, since: token)

                var books: [SharedBookRecords.BookFields] = []
                var sightings: [SharedSighting] = []
                for change in page.modificationResultsByID.values {
                    guard let record = try? change.get().record else { continue }
                    if let fields = SharedBookRecords.book(from: record) { books.append(fields) }
                    else if let s = SharedBookRecords.sighting(from: record) { sightings.append(s) }
                }
                let deleted = page.deletions.map(\.recordID)
                    .compactMap { UUID(uuidString: $0.recordName) }

                var booksOutcome = SharedBookMerge.Outcome()
                for fields in books {
                    SharedBookMerge.apply(book: fields, into: context, outcome: &booksOutcome)
                }
                let outcome = SharedBookMerge.apply(sightings, removing: deleted,
                                                    into: context, carrying: booksOutcome)
                log("pulled \(entry.zoneName): +\(outcome.sightingsAdded) "
                    + "-\(outcome.sightingsRemoved) people:\(outcome.contributorsAdded) "
                    + "more:\(page.moreComing)")

                // Written per page, not once at the end. A pull interrupted halfway
                // through a large book then resumes where it stopped instead of
                // starting over.
                token = page.changeToken
                ledger.setToken(token, zone: entry.zoneName, owner: entry.zoneOwner)
                more = page.moreComing
            }

        } catch let error as CKError where error.code == .changeTokenExpired {
            // The server has forgotten where we were. Drop the token and the next
            // pull starts from the beginning — which is safe precisely because the
            // merge is idempotent.
            ledger.setToken(nil, zone: entry.zoneName, owner: entry.zoneOwner)
        } catch {
            trouble = Self.explain(error)
        }
    }

    // MARK: - Accepting an invitation

    /// Called when somebody opens a share link. The zone arrives on the *shared*
    /// database, owned by whoever sent it, and a first pull brings the contents in.
    func accept(_ metadata: CKShare.Metadata, into context: ModelContext) async {
        do {
            _ = try await container.accept(metadata)
            let zone = metadata.share.recordID.zoneID
            guard let bookID = UUID(uuidString: metadata.hierarchicalRootRecordID?.recordName ?? "")
            else { return trouble = "That invitation did not name a book." }

            log("accepted share for book \(bookID) in \(zone.ownerName)/\(zone.zoneName)")
            ledger.note(.init(bookID: bookID, isOwner: false,
                              zoneName: zone.zoneName, zoneOwner: zone.ownerName))
            await pull(ledger.entry(for: bookID)!, into: context)
        } catch {
            trouble = Self.explain(error)
        }
    }

    // MARK: - Ending it

    /// The owner stops sharing; everybody else keeps nothing. A participant leaving
    /// only detaches themselves.
    ///
    /// Either way the local rows stay put — deleting somebody's plates because a
    /// share ended would be the app throwing away a collection on a technicality.
    /// The book simply becomes an ordinary local one again.
    func stopSharing(_ book: Book) async {
        guard let entry = ledger.entry(for: book.id) else { return }
        let zone = CKRecordZone.ID(zoneName: entry.zoneName, ownerName: entry.zoneOwner)
        let db = database(for: entry)
        do {
            if entry.isOwner {
                // Delete the *share*, not the book record. Deleting the root would
                // take the whole book out of CloudKit — every plate in it — so
                // re-sharing later would have to re-upload from scratch, and any
                // participant mid-sync would see the book vanish rather than simply
                // stop updating. Removing the share revokes access and leaves the
                // data exactly where it is.
                let rootID = SharedBookRecords.recordID(for: book.id, in: zone)
                if let shareID = try await db.record(for: rootID).share?.recordID {
                    _ = try await db.modifyRecords(saving: [], deleting: [shareID])
                }
            } else {
                // Leaving is deleting the whole zone from *your* shared database,
                // which detaches you without touching the owner's copy.
                _ = try await db.modifyRecordZones(saving: [], deleting: [zone])
            }
        } catch {
            trouble = Self.explain(error)
            log("stop sharing failed: \(error)")
        }
        ledger.forget(book: book.id)
    }

    // MARK: - Bits

    private func database(for entry: SharedBookLedger.Entry) -> CKDatabase {
        entry.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func save(_ records: [CKRecord], to db: CKDatabase?) async throws {
        guard let db, !records.isEmpty else { return }
        // Batched, because CloudKit rejects very large single operations and a book
        // topped up after a long trip can carry a few hundred plates at once.
        for chunk in stride(from: 0, to: records.count, by: 200).map({
            Array(records[$0..<min($0 + 200, records.count)])
        }) {
            _ = try await db.modifyRecords(saving: chunk, deleting: [],
                                           savePolicy: .changedKeys)
        }
    }

    /// A running commentary, for the one thing this code has never had: a first run.
    ///
    /// Every interesting failure in CloudKit sharing is quiet — a zone that was
    /// never created, a token that came back empty, a record saved to the wrong
    /// database. None of them crash and most of them look like "nothing happened".
    /// Prefixed so it can be filtered in Console, and compiled out of Release.
    private func log(_ message: String) {
        #if DEBUG
        print("[sharedbook] \(message)")
        #endif
    }

    /// CloudKit's own messages are written for developers. These are the handful a
    /// person can actually do something about.
    private static func explain(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        switch ck.code {
        case .notAuthenticated:   return "Sign in to iCloud to share books."
        case .networkUnavailable,
             .networkFailure:     return "No connection. This will catch up later."
        case .quotaExceeded:      return "Your iCloud storage is full."
        case .zoneNotFound,
             .unknownItem:        return "That shared book is no longer available."
        case .permissionFailure:  return "You do not have permission to change that book."
        default:                  return ck.localizedDescription
        }
    }
}
