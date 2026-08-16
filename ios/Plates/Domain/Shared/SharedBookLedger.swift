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

    private let file: SidecarFile
    private var entries: [UUID: Entry] = [:]
    /// Server change tokens, per zone, so a pull asks for what is new rather than
    /// everything. Kept separate from `entries` because they are opaque blobs with
    /// a completely different lifetime — a token is invalidated by the server at
    /// will, and the recovery is to drop it and refetch.
    private var tokens: [String: Data] = [:]

    init(url: URL?) {
        file = SidecarFile(url: url, holding: "which books are shared")
        load()
    }

    // MARK: - Books

    func entry(for book: UUID) -> Entry? { entries[book] }
    // An `isShared(_:)` sat here, asking `entry(for:) != nil`. Its six callers each
    // guarded a `SharedBookSync` call that opens by asking the same thing, so all it
    // ever did was let a caller decide for itself what "shared" means. Nothing calls
    // it now. `entry(for:)` returning nil is the one answer.
    var allShared: [Entry] { Array(entries.values) }

    func note(_ entry: Entry) {
        entries[entry.bookID] = entry
        save()
    }

    /// Drops the token only when nothing is left reading that zone.
    ///
    /// Entries are per book and tokens are per zone, and books can share one — every
    /// book this device shares out lives in its own single zone. Dropping the token
    /// whenever any one of them was unshared meant the survivors' next pull started
    /// from nothing, which is not merely slow: a pull with no token is told what
    /// exists, never what was deleted. So the other books in that zone would never
    /// hear about a withdrawal again, and would go on re-uploading rows the far side
    /// had removed.
    func forget(book: UUID) {
        guard let gone = entries.removeValue(forKey: book) else { return }
        let zone = key(zone: gone.zoneName, owner: gone.zoneOwner)
        if !entries.values.contains(where: { key(zone: $0.zoneName, owner: $0.zoneOwner) == zone }) {
            tokens.removeValue(forKey: zone)
        }
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
        SidecarFile.inApplicationSupport("SharedBooks.json",
                                         holding: "which books are shared").url
    }

    private func load() {
        guard let stored: Stored = file.read() else { return }
        entries = Dictionary(stored.entries.map { ($0.bookID, $0) }, uniquingKeysWith: { a, _ in a })
        tokens = stored.tokens
    }

    /// Losing this is worse than it looks: the entries can be rebuilt by asking
    /// CloudKit, but a dropped change token means the next pull is told what exists
    /// and never what was deleted.
    private func save() {
        file.write(Stored(entries: Array(entries.values), tokens: tokens))
    }
}
