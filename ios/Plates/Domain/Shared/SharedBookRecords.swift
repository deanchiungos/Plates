import CloudKit
import Foundation

/// The CloudKit shape of a shared book, and nothing else.
///
/// A book two people fill together cannot use the party's radios: your friend
/// spotting a plate three states away on a Tuesday has no peer to talk to. That
/// needs a persistent remote channel, which means CloudKit sharing — and SwiftData
/// still has no `CKShare` support, so this is raw CloudKit living alongside the
/// SwiftData store rather than a rewrite of it. The private store keeps doing
/// exactly what it does today; a shared book is a second, small system that mirrors
/// into it.
///
/// **These field names are permanent.** A CloudKit production schema is additive
/// and cannot be un-deployed: a record type or field pushed to production is there
/// for the life of the container. Renaming anything here after the first deploy
/// means carrying both names forever. See the warning at the top of `PlatesStore`.
///
/// The mapping is deliberately separate from the syncing. Everything in this file
/// is a pure function between a model object and a `CKRecord`, so it can be tested
/// against records built in memory — no account, no network, no container. Which
/// matters, because the parts that *do* need an account are the parts that cannot
/// be tested anywhere but on a real device with two Apple IDs.
enum SharedBookRecords {

    /// Custom, and it has to be. Records in the default zone cannot be shared at
    /// all — that single CloudKit fact is most of why shared books are a different
    /// mechanism from everything else in the app.
    static let zoneName = "SharedBooks"

    static let bookType = "SBBook"
    static let sightingType = "SBSighting"

    enum Field {
        static let name = "name"
        static let startedAt = "startedAt"

        static let bookID = "bookID"
        static let plateCode = "plateCode"
        static let spottedAt = "spottedAt"
        static let playerID = "playerID"
        static let playerName = "playerName"
        static let playerColor = "playerColor"
        static let playerAvatar = "playerAvatar"
        static let rarity = "rarity"

        // No `lat` / `lon`. Where you were standing when you found a plate is the
        // one thing in a sighting that is about *you* rather than about the plate,
        // and a book shared with five people would have handed all five a map of
        // your week. The Trail still draws every pin — it reads them straight out
        // of the local store, which is where they now stay. See `Sighting`.
    }

    // MARK: - Going out

    static func recordID(for id: UUID, in zone: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone)
    }

    /// The book itself — the root of the shared hierarchy.
    ///
    /// Carries only the columns that are the *book's*. `currentLat` / `currentLon` /
    /// `locatedAt` stay behind for the same reason they do in a party: they are
    /// where this phone is standing, they feed this phone's rarity, and a
    /// contributor two states away has no business overwriting them.
    static func record(for book: Book, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: bookType, recordID: recordID(for: book.id, in: zone))
        record[Field.name] = book.name as CKRecordValue
        record[Field.startedAt] = book.startedAt as CKRecordValue
        return record
    }

    /// One sighting, filed under a book.
    ///
    /// The contributor's name and color ride along rather than being looked up.
    /// There is no roster to look them up *in*: CloudKit participants are Apple
    /// accounts, not rows in your `Player` table, and the whole point of a shared
    /// book is that the other person is somebody you may never sit in a car with.
    /// Three small fields per sighting buys spotter chips and avatar stacks that
    /// work without a second sync channel for people.
    static func record(for sighting: Sighting,
                       bookID: UUID,
                       in zone: CKRecordZone.ID,
                       parent: CKRecord.ID? = nil) -> CKRecord {
        let record = CKRecord(recordType: sightingType,
                              recordID: recordID(for: sighting.id, in: zone))
        record[Field.bookID] = bookID.uuidString as CKRecordValue
        record[Field.plateCode] = sighting.plateCode as CKRecordValue
        record[Field.spottedAt] = sighting.spottedAt as CKRecordValue
        record[Field.playerID] = sighting.player?.id.uuidString as CKRecordValue?
        record[Field.playerName] = sighting.player?.name as CKRecordValue?
        record[Field.playerColor] = sighting.player.map { $0.colorIndex as CKRecordValue }
        record[Field.playerAvatar] = sighting.player?.avatar as CKRecordValue?
        record[Field.rarity] = sighting.rarityWhenSpotted.map { $0 as CKRecordValue }
        // The parent reference is what makes one `CKShare` on the book cover every
        // plate in it. Without it each sighting would be an unshared island and the
        // invitation would hand over an empty book.
        if let parent {
            record.parent = CKRecord.Reference(recordID: parent, action: .none)
        }
        return record
    }

    // MARK: - Coming back

    struct BookFields: Equatable {
        var id: UUID
        var name: String
        var startedAt: Date
    }

    static func book(from record: CKRecord) -> BookFields? {
        guard record.recordType == bookType,
              let id = UUID(uuidString: record.recordID.recordName),
              let name = record[Field.name] as? String,
              let startedAt = record[Field.startedAt] as? Date else { return nil }
        return BookFields(id: id, name: name, startedAt: startedAt)
    }

    static func sighting(from record: CKRecord) -> SharedSighting? {
        guard record.recordType == sightingType,
              let id = UUID(uuidString: record.recordID.recordName),
              let rawBook = record[Field.bookID] as? String,
              let bookID = UUID(uuidString: rawBook),
              let plateCode = record[Field.plateCode] as? String,
              let spottedAt = record[Field.spottedAt] as? Date else { return nil }

        return SharedSighting(
            id: id,
            bookID: bookID,
            plateCode: plateCode,
            spottedAt: spottedAt,
            playerID: (record[Field.playerID] as? String).flatMap(UUID.init(uuidString:)),
            playerName: record[Field.playerName] as? String,
            playerColorIndex: record[Field.playerColor] as? Int,
            playerAvatar: record[Field.playerAvatar] as? String,
            // Deliberately not read, even when present: a book shared from an
            // older build still carries `lat` / `lon`, and honouring them would
            // quietly reintroduce exactly what this stopped sending.
            rarityWhenSpotted: record[Field.rarity] as? Int)
    }
}

/// A sighting as it travels between people who are not in the same car.
///
/// The party's `SightingEvent` is filed under a *trip* and leans on a roster both
/// devices already share. Neither is true here, so this carries its own book id and
/// its own contributor details. Same idea, different journey.
struct SharedSighting: Equatable {
    var id: UUID
    var bookID: UUID
    var plateCode: String
    var spottedAt: Date
    var playerID: UUID?
    var playerName: String?
    var playerColorIndex: Int?
    var playerAvatar: String?
    /// Banked by whoever spotted it, from where *they* were. The same asymmetry
    /// that makes a party honest makes distributed contribution honest: two people
    /// filling one book from different cities each record what the plate was worth
    /// to them, and neither device recomputes the other's.
    var rarityWhenSpotted: Int?
}
