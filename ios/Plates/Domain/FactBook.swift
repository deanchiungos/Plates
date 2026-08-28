import Foundation

/// Picks which fact to show, and remembers which ones you have already seen.
///
/// Each region carries several facts, and the same one twice in a row is the fastest
/// way to make a reward feel like a canned response. So this deals from an unseen
/// pile per region: every fact gets shown once before any repeats, and when a region
/// runs dry the pile is reshuffled — never re-dealing the one just seen, so a reshuffle
/// cannot hand you the same fact twice in a row across the seam.
///
/// Facts are recorded by content hash rather than by position, so `PlateFacts` can be
/// edited freely — added to, deleted from, reordered — without scrambling what a
/// player has already read. See `PlateFacts.id(of:)`.
///
/// Seen state lives in `UserDefaults` rather than SwiftData. It is a record of what
/// this person has read, not a fact about the trip: it should survive wiping a trip's
/// plates, should not be duplicated per trip, and losing it costs nothing worse than
/// an early repeat.
@MainActor
enum FactBook {

    /// The rotation pile: which facts this cycle has already dealt. Emptied when a
    /// region runs dry, because that is what "reshuffle" means.
    private static let seenKey = "seenFactIDs"
    private static let lastKey = "lastFactID"

    /// Everything this player has ever read, which only ever grows.
    ///
    /// Split out from `seenKey`, which was doing both jobs and could not do both:
    /// the pile has to empty on a reshuffle, and the detail sheet reads the same set
    /// to decide which facts are unlocked. So reading the last fact for a state
    /// reset the pile and every fact for it went back to showing "Locked" — the
    /// collection visibly un-collecting itself. A tester reported it as not being
    /// able to tell how facts are unlocked, which is exactly how that would look.
    private static let unlockedKey = "unlockedFactIDs"

    /// A fact for this plate, preferring one that has not been shown before.
    /// Nil only if the region has no facts at all.
    static func fact(for code: String) -> String? {
        let facts = PlateFacts.facts(for: code)
        guard !facts.isEmpty else { return nil }
        guard facts.count > 1 else {
            record(PlateFacts.id(of: facts[0]), for: code)
            return facts[0]
        }

        let last = lastID(for: code)
        // Intersected with what exists now, so ids left behind by deleted or
        // reworded facts cannot keep a region looking permanently exhausted.
        let live = Set(facts.map(PlateFacts.id(of:)))
        var seen = seenIDs(for: code).intersection(live)

        var pool = facts.filter { !seen.contains(PlateFacts.id(of: $0)) }
        if pool.isEmpty {
            // Every fact for this region has been read. Start the cycle over, minus
            // whichever one was showing most recently.
            seen = []
            pool = facts.filter { PlateFacts.id(of: $0) != last }
        }

        guard let pick = pool.randomElement() else { return facts[0] }

        seen.insert(PlateFacts.id(of: pick))
        setSeen(seen, for: code)
        unlock(PlateFacts.id(of: pick), for: code)
        setLast(PlateFacts.id(of: pick), for: code)
        return pick
    }

    /// How many distinct facts have been read, across every region — the number
    /// behind a future "41 of 390 facts" line. Counts only facts that still exist,
    /// so deleting one does not leave the total stranded above the maximum.
    static var seenCount: Int {
        let store = unlockedStore
        return PlateFacts.byCode.reduce(0) { running, entry in
            let live = Set(entry.value.map(PlateFacts.id(of:)))
            return running + Set(store[entry.key] ?? []).intersection(live).count
        }
    }

    static var totalCount: Int {
        PlateFacts.byCode.values.reduce(0) { $0 + $1.count }
    }

    /// The lines this player has actually read for a region, in catalogue order.
    /// The map's detail sheet shows these and leaves the rest locked, so the facts
    /// are themselves something to collect.
    static func seenFacts(for code: String) -> [String] {
        let facts = PlateFacts.byCode[code] ?? []
        let unlocked = unlockedIDs(for: code)
        return facts.filter { unlocked.contains(PlateFacts.id(of: $0)) }
    }

    static func total(for code: String) -> Int {
        PlateFacts.byCode[code]?.count ?? 0
    }

    static func reset() {
        AppDefaults.store.removeObject(forKey: seenKey)
        AppDefaults.store.removeObject(forKey: lastKey)
        AppDefaults.store.removeObject(forKey: unlockedKey)
    }

    // MARK: - Storage

    private static var seenStore: [String: [Int]] {
        AppDefaults.store.dictionary(forKey: seenKey) as? [String: [Int]] ?? [:]
    }

    private static func seenIDs(for code: String) -> Set<Int> {
        Set((seenStore[code] ?? []).map(PlateFacts.canonical))
    }

    private static func setSeen(_ ids: Set<Int>, for code: String) {
        var store = seenStore
        store[code] = Array(ids)
        AppDefaults.store.set(store, forKey: seenKey)
    }

    private static func lastID(for code: String) -> Int? {
        (AppDefaults.store.dictionary(forKey: lastKey) as? [String: Int])?[code]
            .map(PlateFacts.canonical)
    }

    private static func setLast(_ id: Int, for code: String) {
        var store = (AppDefaults.store.dictionary(forKey: lastKey) as? [String: Int]) ?? [:]
        store[code] = id
        AppDefaults.store.set(store, forKey: lastKey)
    }

    private static func record(_ id: Int, for code: String) {
        setSeen(seenIDs(for: code).union([id]), for: code)
        unlock(id, for: code)
        setLast(id, for: code)
    }

    // MARK: - What has ever been read

    /// Seeded from the rotation pile the first time it is asked for, so anybody
    /// upgrading keeps whatever their pile happened to be holding. Some of it was
    /// already lost to a reshuffle before this existed and cannot be recovered —
    /// the facts are still there to be read again, they just show as locked once.
    private static var unlockedStore: [String: [Int]] {
        if let stored = AppDefaults.store.dictionary(forKey: unlockedKey) as? [String: [Int]] {
            return stored
        }
        let carried = seenStore
        AppDefaults.store.set(carried, forKey: unlockedKey)
        return carried
    }

    private static func unlockedIDs(for code: String) -> Set<Int> {
        Set((unlockedStore[code] ?? []).map(PlateFacts.canonical))
    }

    private static func unlock(_ id: Int, for code: String) {
        var store = unlockedStore
        store[code] = Array(Set(store[code] ?? []).union([id]))
        AppDefaults.store.set(store, forKey: unlockedKey)
    }
}
