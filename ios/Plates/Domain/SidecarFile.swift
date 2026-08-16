import Foundation

/// A small JSON file living beside the store.
///
/// Five things in this app keep one — the party ledger, its tombstones, the shared
/// book ledger, the route cache and the widget mirror — for the same reason each
/// time: none of it is a `@Model`, because none of it wants a CloudKit record type,
/// and a change token or a "have you seen this tour" flag is meaningless on another
/// device anyway. Each had grown its own copy of the same three lines, and the copies
/// had drifted in the one way that matters.
///
/// **A missing file and an unreadable one are not the same thing.** Every copy wrote
/// `try? Data(contentsOf:)` followed by `try? JSONDecoder().decode(...)` and returned
/// empty on either, which is right for the first launch and wrong for everything
/// else. A tombstone file that fails to decode reads back as "nobody has ever taken a
/// plate back", and the next snapshot from any peer puts every withdrawn plate on
/// every phone in the car — silently, with nothing to look at afterwards. It stays
/// non-throwing, because none of these callers has anything better to do than carry
/// on with what they have; what changes is that the second case says so.
struct SidecarFile {

    let url: URL?
    /// What this holds, for the one line it might print. Not a file name: the reader
    /// of that line is a developer trying to explain a phone's behavior, not find a
    /// path.
    private let contents: String

    init(url: URL?, holding contents: String) {
        self.url = url
        self.contents = contents
    }

    /// In Application Support, which is where everything that is not the user's own
    /// documents belongs and which is excluded from iCloud backup by nobody — these
    /// are all cheap to lose and none of them are worth restoring.
    static func inApplicationSupport(_ name: String, holding contents: String) -> SidecarFile {
        SidecarFile(url: try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent(name),
                    holding: contents)
    }

    /// Nil when there is nothing there yet, which is the ordinary first-launch case
    /// and says nothing. Also nil when the file exists and cannot be read — and that
    /// one is worth a line, because every caller's recovery is to behave as though
    /// the thing never happened.
    func read<Value: Decodable>(_ type: Value.Type = Value.self) -> Value? {
        guard let url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            complain("could not read \(contents): \(error)")
            return nil
        }
    }

    /// Atomic, so a crash mid-write leaves the previous contents rather than half of
    /// the new ones — which for the tombstones is the difference between forgetting
    /// one withdrawal and forgetting all of them.
    func write<Value: Encodable>(_ value: Value) {
        guard let url else { return }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            complain("could not write \(contents): \(error)")
        }
    }

    private func complain(_ message: String) {
        #if DEBUG
        print("[sidecar] \(message)")
        #endif
    }
}
