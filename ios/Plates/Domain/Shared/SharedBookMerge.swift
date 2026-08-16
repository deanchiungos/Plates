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
        /// A contributor already on this device was renamed or given an avatar.
        /// Counted apart from `contributorsAdded`, which is inserts only, for the
        /// same reason `PartyMerge` separates the two: an edit is a change worth
        /// saving and the insert count cannot see it.
        var contributorsChanged = false

        var isEmpty: Bool {
            sightingsAdded == 0 && sightingsRemoved == 0
                && contributorsAdded == 0 && !bookChanged && !contributorsChanged
        }
    }

    // MARK: - Applying

    /// Reports what it did through `outcome`, which is the only reason the change
    /// ever reaches the disk.
    ///
    /// `bookChanged` was declared, read by `isEmpty`, and assigned nowhere — a
    /// permanently-true term in the save gate. So a page carrying nothing but a
    /// renamed book applied the rename to the in-memory object, returned an empty
    /// outcome, skipped the save, and then advanced and persisted the change token,
    /// which means the server never sends that record again. The rename was gone for
    /// good and no later pull could recover it.
    @discardableResult
    static func apply(book fields: SharedBookRecords.BookFields,
                      into context: ModelContext,
                      outcome: inout Outcome) -> Book {
        let id = fields.id
        if let existing = try? context.fetch(
            FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first {
            // Compared before assigning, so an unchanged record does not dirty the
            // object and send every screen watching it redrawing for nothing.
            if existing.name != fields.name {
                existing.name = fields.name
                outcome.bookChanged = true
            }
            if existing.startedAt != fields.startedAt {
                existing.startedAt = fields.startedAt
                outcome.bookChanged = true
            }
            return existing
        }

        let book = Book(name: fields.name)
        book.id = fields.id
        book.startedAt = fields.startedAt
        context.insert(book)
        outcome.bookChanged = true
        return book
    }

    /// `carrying` folds in what the book pass already did, because the two run over
    /// one page and share one save. A page can carry a renamed book and no sightings
    /// at all, and that page still has to reach the disk.
    @discardableResult
    static func apply(_ sightings: [SharedSighting],
                      removing deleted: [UUID] = [],
                      into context: ModelContext,
                      carrying carried: Outcome = Outcome()) -> Outcome {
        var outcome = carried
        guard !sightings.isEmpty || !deleted.isEmpty else {
            // Nothing of our own to do, but the book pass may have left an edit
            // sitting in the context — and the caller is about to advance the change
            // token past this page either way.
            if !outcome.isEmpty { try? context.save(); WidgetData.write(from: context) }
            return outcome
        }

        // Removals first. A batch that both adds and deletes the same record is
        // CloudKit telling us the net result is "gone", and doing it in this order
        // means we never insert a row only to delete it a line later.
        if !deleted.isEmpty {
            let doomed = Set(deleted)
            for row in (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
            where doomed.contains(row.id) {
                // The same rule the grid applies locally: a sighting folded in from a
                // trip is the trip's record, on loan to this shelf. A peer taking it
                // off the shared book takes it off the shelf — it does not reach
                // across the wire into a drive they were never on and erase what
                // happened there. Only rows the book itself owns are the book's to
                // delete. See `PlateLogger.withdraw`.
                if row.trip != nil {
                    row.book = nil
                } else {
                    context.delete(row)
                }
                outcome.sightingsRemoved += 1
            }
        }

        var known = Set(((try? context.fetch(FetchDescriptor<Sighting>())) ?? []).map(\.id))
        var books = [UUID: Book]()
        var players = allPlayers(in: context)
        // Resolved once for the whole page. Falls back to the store when no profile
        // has been adopted, for the reason `contributor` gives.
        let mine = DevicePlayer.currentID
            ?? DevicePlayer.resolve(from: Array(players.values))?.id.uuidString

        for event in sightings {
            guard !known.contains(event.id) else { continue }
            guard let book = books[event.bookID]
                    ?? self.book(event.bookID, in: context).map({ books[event.bookID] = $0; return $0 })
            else { continue }

            let sighting = Sighting(plateCode: event.plateCode,
                                    in: book,
                                    player: contributor(event, into: context,
                                                        known: &players, mine: mine,
                                                        outcome: &outcome),
                                    spottedAt: event.spottedAt)
            sighting.id = event.id
            sighting.rarityWhenSpotted = event.rarityWhenSpotted
            sighting.spottedLat = event.spottedLat
            sighting.spottedLon = event.spottedLon
            context.insert(sighting)

            known.insert(event.id)
            outcome.sightingsAdded += 1
        }

        if !outcome.isEmpty {
            try? context.save()
            // As in `PartyMerge`: a plate a friend added to a shared book is a plate
            // this phone now has, and the home screen has to hear about it. Nothing
            // that arrives from another device goes through `PlateLogger`, which is
            // where the widget used to be rebuilt.
            WidgetData.write(from: context)
        }
        return outcome
    }

    /// Whoever spotted it, as a local `Player` row.
    ///
    /// A contributor to a shared book is not somebody you have ever sat in a car
    /// with, so there is no roster they arrive on. Their name and color come
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
                                    mine: String?,
                                    outcome: inout Outcome) -> Player? {
        guard let id = event.playerID else { return nil }

        if let existing = known[id] {
            // Never me. `PartyMerge` has had this guard since a peer's stale roster
            // was found renaming people back, and the same argument holds over a
            // slower wire: a record I pushed carries my name as it was *then*, and
            // this device is the only one that saw me change it. Reachable on a full
            // refetch, and on a second device signed into the same iCloud account,
            // where my own records come back down a zone I own.
            //
            // `mine` is resolved by the caller rather than read raw, because an unset
            // `devicePlayerID` compares unequal to everything and would turn this
            // guard into a no-op on exactly the installs that have not been through
            // the identity prompt yet.
            guard id.uuidString != mine else { return existing }

            if let name = event.playerName, !name.isEmpty, existing.name != name {
                existing.name = name
                outcome.contributorsChanged = true
            }
            // Guarded the same way the name is. Assigning it unconditionally meant a
            // record pushed before somebody picked an emoji — carrying nil — erased
            // the one they have now, and which record lands last within a page is
            // dictionary order, so it was arbitrary rather than newest-wins.
            if let avatar = event.playerAvatar, existing.avatar != avatar {
                existing.avatar = avatar
                outcome.contributorsChanged = true
            }
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
