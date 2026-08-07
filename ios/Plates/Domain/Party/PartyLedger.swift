import Foundation

/// Which trips were parties, and how they were played.
///
/// Two jobs, both of which need to outlive the party itself. The Trips tab marks a
/// party trip differently months later, and the rules have to survive the host's
/// app being closed and reopened mid-drive — a rule that resets to the default
/// every time somebody's phone runs out of battery is not one anybody can rely on.
///
/// **Deliberately not a `@Model`,** for the same reason as `PartyTombstones`:
/// adding one means a new CloudKit record type and the additive-and-permanent
/// production deploy that `PlatesStore` warns about, in exchange for storing a
/// badge. The cost of the sidecar is honest and small — this is per-device, so it
/// is not in the iCloud backup and a reinstall loses the badge on old trips. The
/// plates, the scores and the roster are all real data and are all unaffected.
@MainActor
final class PartyLedger {

    static let shared = PartyLedger(url: PartyLedger.defaultURL)

    struct Record: Codable, Equatable {
        var tripID: UUID
        /// "host" or "guest" — kept as a string so a future third role does not
        /// make old files undecodable.
        var role: String
        var startedAt: Date
        var rules: PartyRules
        /// Whoever was advertising the party we joined, so a guest can be told whose
        /// trip this is by name. Optional because records written before this existed
        /// have no answer — and because a host has nobody to name.
        var hostName: String?
    }

    /// `nil` keeps everything in memory, for the harness.
    private let url: URL?
    private var records: [UUID: Record] = [:]

    init(url: URL?) {
        self.url = url
        load()
    }

    // MARK: - Reading

    func record(for trip: UUID) -> Record? { records[trip] }

    func wasParty(_ trip: UUID) -> Bool { records[trip] != nil }

    /// This device joined this trip rather than starting it.
    ///
    /// Permanent, and meant to be: a guest who could start their own party for
    /// somebody else's trip would be a second host of the same trip id, with its own
    /// idea of the rules — and `setRules` is host-only precisely so two people in one
    /// car cannot disagree about what a tap means. The party ending does not hand the
    /// trip over; it is still Anna's drive, on a copy.
    func joinedAsGuest(_ trip: UUID) -> Bool { records[trip]?.role == "guest" }

    /// Who was hosting when we joined, if we know.
    func hostName(for trip: UUID) -> String? { records[trip]?.hostName }

    /// The rules this trip is played by, or the standard ones if it was never a
    /// party. Callers do not have to know which.
    func rules(for trip: UUID) -> PartyRules {
        records[trip]?.rules ?? .standard
    }

    // MARK: - Writing

    /// Called when a party starts or is joined. Keeps the original `startedAt` if
    /// the trip has been partied before, so re-hosting an old trip does not rewrite
    /// when it first happened.
    func note(trip: UUID, role: String, rules: PartyRules, hostName: String? = nil) {
        let existing = records[trip]
        records[trip] = Record(tripID: trip,
                               role: role,
                               startedAt: existing?.startedAt ?? Date(),
                               rules: rules,
                               // Kept when this call does not carry one, so rejoining
                               // a party does not forget whose trip it is.
                               hostName: hostName ?? existing?.hostName)
        save()
    }

    func setRules(_ rules: PartyRules, for trip: UUID) {
        guard var existing = records[trip] else { return }
        guard existing.rules != rules else { return }
        existing.rules = rules
        records[trip] = existing
        save()
    }

    func forget(trip: UUID) {
        guard records.removeValue(forKey: trip) != nil else { return }
        save()
    }

    // MARK: - Disk

    private static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("PartyLedger.json")
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([Record].self, from: data) else { return }
        records = Dictionary(raw.map { ($0.tripID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Failures are swallowed. The worst case is a badge that does not appear and a
    /// rule that falls back to its default — neither is worth interrupting a drive.
    private func save() {
        guard let url,
              let data = try? JSONEncoder().encode(Array(records.values)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
