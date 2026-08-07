import Foundation
import SwiftData

/// Turning what CloudKit sent into rows in the store.
///
/// `PartyMerge`'s sibling, and deliberately the same shape: fetch before insert on
/// `id`, applying anything twice changes nothing, and nothing here re-enters the
/// path that publishes changes — so a record that arrives cannot bounce straight
/// back out again. Those rules were worth proving once for the party and are worth
/// exactly as much here, where the round trip is slower and a loop would be much
/// harder to notice.
///
/// One thing CloudKit gives us that MultipeerConnectivity did not: **deletions are
/// its own bookkeeping.** A record removed from the zone comes back as a deleted
/// record id, so there is no tombstone sidecar to maintain — the party needs
/// `PartyTombstones` only because a snapshot re-sends everything it knows and has
/// no other way to say "and not this one".
@MainActor
enum SharedBookMerge {

    struct Outcome: Equatable {
        var sightingsAdded = 0
        var sightingsRemoved = 0
        var contributorsAdded = 0
        var bookChanged = false

        var isEmpty: Bool {
            sightingsAdded == 0 && sightingsRemoved == 0
                && contributorsAdded == 0 && !bookChanged
        }
    }

    // MARK: - Applying

    @discardableResult
    static func apply(book fields: SharedBookRecords.BookFields,
                      into context: ModelContext) -> Book {
        let id = fields.id
        if let existing = try? context.fetch(
            FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first {
            // Compared before assigning, so an unchanged record does not dirty the
            // object and send every screen watching it redrawing for nothing.
            if existing.name != fields.name { existing.name = fields.name }
            if existing.startedAt != fields.startedAt { existing.startedAt = fields.startedAt }
            return existing
        }

        let book = Book(name: fields.name)
        book.id = fields.id
        book.startedAt = fields.startedAt
        context.insert(book)
        return book
    }

    @discardableResult
    static func apply(_ sightings: [SharedSighting],
                      removing deleted: [UUID] = [],
                      into context: ModelContext) -> Outcome {
        var outcome = Outcome()
        guard !sightings.isEmpty || !deleted.isEmpty else { return outcome }

        // Removals first. A batch that both adds and deletes the same record is
        // CloudKit telling us the net result is "gone", and doing it in this order
        // means we never insert a row only to delete it a line later.
        if !deleted.isEmpty {
            let doomed = Set(deleted)
            for row in (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
            where doomed.contains(row.id) {
                context.delete(row)
                outcome.sightingsRemoved += 1
            }
        }

        var known = Set(((try? context.fetch(FetchDescriptor<Sighting>())) ?? []).map(\.id))
        var books = [UUID: Book]()
        var players = allPlayers(in: context)

        for event in sightings {
            guard !known.contains(event.id) else { continue }
            guard let book = books[event.bookID]
                    ?? self.book(event.bookID, in: context).map({ books[event.bookID] = $0; return $0 })
            else { continue }

            let sighting = Sighting(plateCode: event.plateCode,
                                    in: book,
                                    player: contributor(event, into: context,
                                                        known: &players, outcome: &outcome),
                                    spottedAt: event.spottedAt)
            sighting.id = event.id
            sighting.rarityWhenSpotted = event.rarityWhenSpotted
            sighting.spottedLat = event.spottedLat
            sighting.spottedLon = event.spottedLon
            context.insert(sighting)

            known.insert(event.id)
            outcome.sightingsAdded += 1
        }

        if !outcome.isEmpty { try? context.save() }
        return outcome
    }

    /// Whoever spotted it, as a local `Player` row.
    ///
    /// A contributor to a shared book is not somebody you have ever sat in a car
    /// with, so there is no roster they arrive on. Their name and colour come
    /// attached to each sighting instead, and the first one creates the row — which
    /// is what makes spotter chips and avatar stacks work on a book filled by
    /// somebody in another state.
    ///
    /// Their name is refreshed from later sightings, so renaming yourself reaches
    /// everyone eventually rather than freezing at whatever you were called the
    /// first time you contributed.
    private static func contributor(_ event: SharedSighting,
                                    into context: ModelContext,
                                    known: inout [UUID: Player],
                                    outcome: inout Outcome) -> Player? {
        guard let id = event.playerID else { return nil }

        if let existing = known[id] {
            if let name = event.playerName, !name.isEmpty, existing.name != name {
                existing.name = name
            }
            if existing.avatar != event.playerAvatar { existing.avatar = event.playerAvatar }
            return existing
        }

        let player = Player(name: event.playerName ?? "Someone",
                            colorIndex: event.playerColorIndex ?? 0)
        player.id = id
        player.avatar = event.playerAvatar
        context.insert(player)
        known[id] = player
        outcome.contributorsAdded += 1
        return player
    }

    // MARK: - Publishing

    /// What this device should push for a book it is sharing: the book, then every
    /// sighting filed under it.
    ///
    /// Returned as models rather than `CKRecord`s so the caller decides the zone —
    /// and so this stays testable without a container.
    static func outgoing(for book: Book) -> (book: Book, sightings: [Sighting]) {
        (book, book.allSightings)
    }

    // MARK: - Lookups

    private static func book(_ id: UUID, in context: ModelContext) -> Book? {
        try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first
    }

    private static func allPlayers(in context: ModelContext) -> [UUID: Player] {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        return Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
