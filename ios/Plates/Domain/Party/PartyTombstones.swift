import Foundation

/// The sightings a party has taken back.
///
/// A deletion is not a fact you can send once and forget, because the party keeps
/// re-sending everything it knows (see `PartySnapshot`). Without a record of what
/// was withdrawn, every reconnect would hand the un-tapped plate straight back:
/// peer A removes Ohio, peer B has not heard yet, B reconnects and its snapshot
/// re-adds Ohio on A. The plate would flicker back into the grid minutes after
/// somebody deliberately took it off, and no amount of care in the merge would fix
/// it — the merge cannot tell "new to me" from "gone on purpose" without this.
///
/// **Deliberately not a `@Model`.** Adding one would mean a new CloudKit record
/// type and the production schema deploy that `PlatesStore` warns about at length,
/// and would sync a bookkeeping detail to every device the user owns forever. This
/// is small, local, and disposable: a file in Application Support, keyed by trip.
///
/// Unbounded, and safely so. Entries only ever arrive from somebody physically
/// tapping a found plate to un-collect it, which is rare and capped in practice by
/// how many plates a trip has in the first place.
@MainActor
final class PartyTombstones {

    static let shared = PartyTombstones(url: PartyTombstones.defaultURL)

    /// `nil` keeps everything in memory and never touches disk — the harness runs
    /// against one of these so a verification pass cannot leave residue in the real
    /// file, or read somebody's actual party out of it.
    private let url: URL?
    private var byTrip: [UUID: Set<UUID>] = [:]

    init(url: URL?) {
        self.url = url
        load()
    }

    // MARK: - Reading

    func ids(for trip: UUID) -> Set<UUID> { byTrip[trip] ?? [] }

    func contains(_ sighting: UUID, in trip: UUID) -> Bool {
        byTrip[trip]?.contains(sighting) ?? false
    }

    // MARK: - Writing

    func add(_ sightings: [UUID], to trip: UUID) {
        guard !sightings.isEmpty else { return }
        byTrip[trip, default: []].formUnion(sightings)
        save()
    }

    /// Called when a trip is deleted outright: there is nothing left to protect
    /// from resurrection, and keeping the ids would leak a little more every time
    /// somebody clears out an old drive.
    func forget(trip: UUID) {
        guard byTrip.removeValue(forKey: trip) != nil else { return }
        save()
    }

    // MARK: - Disk

    private static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("PartyTombstones.json")
    }

    /// Stored as strings rather than `UUID`s because the top level is a dictionary
    /// key, and JSON keys are strings whatever Swift would prefer.
    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        for (trip, ids) in raw {
            guard let tripID = UUID(uuidString: trip) else { continue }
            byTrip[tripID] = Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }

    /// Failures are swallowed on purpose. The worst case is a plate somebody
    /// un-tapped coming back on a later reconnect — annoying, one tap to fix, and
    /// not worth interrupting a car full of people to report.
    private func save() {
        guard let url else { return }
        let raw = byTrip.reduce(into: [String: [String]]()) { out, entry in
            out[entry.key.uuidString] = entry.value.map(\.uuidString).sorted()
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
