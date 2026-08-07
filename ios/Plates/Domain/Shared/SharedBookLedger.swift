import CloudKit
import Foundation
import Observation

/// Which books are shared, and how far we have read each side.
///
/// A sidecar again, for the third time and the same reasons: no `@Model` means no
/// CloudKit record type for our own bookkeeping, and none of this is worth syncing
/// — a change token is meaningless on another device, and "is this book shared" is
/// answered authoritatively by CloudKit anyway. This is a cache so the app can draw
/// the right thing before the network answers.
///
/// `@Observable` because the views that ask "is this book shared?" read it straight
/// out of `shared` rather than holding a copy. Without it nothing tells SwiftUI that
/// stopping a share changed anything, so the button kept saying "Stop sharing" —
/// correctly, from its own point of view — until something unrelated redrew the sheet.
@MainActor
@Observable
final class SharedBookLedger {

    static let shared = SharedBookLedger(url: SharedBookLedger.defaultURL)

    struct Entry: Codable, Equatable {
        var bookID: UUID
        /// True when this device owns the book and shared it out; false when it
        /// arrived from somebody else. The two get different verbs — you *stop
        /// sharing* something of yours and *leave* something of theirs.
        var isOwner: Bool
        /// The zone the records live in. A participant's records are in the
        /// *owner's* zone, reached through the shared database, so the owner name
        /// matters and cannot be assumed to be the current user.
        var zoneName: String
        var zoneOwner: String
    }

    private let url: URL?
    private var entries: [UUID: Entry] = [:]
    /// Server change tokens, per zone, so a pull asks for what is new rather than
    /// everything. Kept separate from `entries` because they are opaque blobs with
    /// a completely different lifetime — a token is invalidated by the server at
    /// will, and the recovery is to drop it and refetch.
    private var tokens: [String: Data] = [:]

    init(url: URL?) {
        self.url = url
        load()
    }

    // MARK: - Books

    func entry(for book: UUID) -> Entry? { entries[book] }
    func isShared(_ book: UUID) -> Bool { entries[book] != nil }
    var allShared: [Entry] { Array(entries.values) }

    func note(_ entry: Entry) {
        entries[entry.bookID] = entry
        save()
    }

    func forget(book: UUID) {
        guard let gone = entries.removeValue(forKey: book) else { return }
        tokens.removeValue(forKey: key(zone: gone.zoneName, owner: gone.zoneOwner))
        save()
    }

    // MARK: - Tokens

    func token(zone: String, owner: String) -> CKServerChangeToken? {
        guard let data = tokens[key(zone: zone, owner: owner)] else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: data)
    }

    func setToken(_ token: CKServerChangeToken?, zone: String, owner: String) {
        let k = key(zone: zone, owner: owner)
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token, requiringSecureCoding: true) else {
            tokens.removeValue(forKey: k)
            save()
            return
        }
        tokens[k] = data
        save()
    }

    private func key(zone: String, owner: String) -> String { "\(owner)/\(zone)" }

    // MARK: - Disk

    private struct Stored: Codable {
        var entries: [Entry]
        var tokens: [String: Data]
    }

    private static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("SharedBooks.json")
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        entries = Dictionary(stored.entries.map { ($0.bookID, $0) }, uniquingKeysWith: { a, _ in a })
        tokens = stored.tokens
    }

    private func save() {
        guard let url,
              let data = try? JSONEncoder().encode(
                Stored(entries: Array(entries.values), tokens: tokens)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
