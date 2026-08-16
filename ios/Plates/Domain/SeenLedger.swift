import Foundation

/// "Has this been shown yet", for one family of one-time things.
///
/// `Coach` and `Tour` are deliberately different features — an aside versus a
/// sequence, and their own files say so at length — but the bookkeeping underneath
/// them was the same object written twice: a key built from a prefix and a raw value,
/// a bool read, a bool written, a loop that marks everything, a loop that clears
/// everything, and a debug flag that forces one case whatever the ledger says. Two
/// copies of a store is two places to remember when the store changes, and the
/// switch to `AppDefaults` found exactly that — one copy was moved and the other was
/// not, which is invisible until a check writes to the real preferences file.
///
/// The differences the two features actually have stay with the features: the launch
/// counter is `Coach`'s alone, `Tour` alone knows that pushed screens do not count
/// toward being finished, and only `Coach` spares the welcome card on a reset. Those
/// are decisions about the feature. This is the filing cabinet they both keep them in.
struct SeenLedger<Item> where Item: RawRepresentable & CaseIterable & Hashable,
                              Item.RawValue == String {

    /// Prefixes every key. These are shipped defaults keys, so it is not renamed
    /// casually — a changed prefix reads as a fresh install to everybody who has
    /// already been shown the thing.
    let prefix: String

    private func key(_ item: Item) -> String { "\(prefix).\(item.rawValue)" }

    func seen(_ item: Item) -> Bool { AppDefaults.store.bool(forKey: key(item)) }

    func markSeen(_ item: Item) { AppDefaults.store.set(true, forKey: key(item)) }

    /// Spend a set of them at once, without showing any.
    func markSeen(_ items: some Sequence<Item>) { items.forEach(markSeen) }

    /// Hand them all back their turn.
    ///
    /// `sparing` is for the one item that should not come back on a general replay —
    /// see `Coach.reset(includingWelcome:)`, which is the only caller that passes it.
    func reset(sparing spared: Set<Item> = []) {
        for item in Item.allCases where !spared.contains(item) {
            AppDefaults.store.removeObject(forKey: key(item))
        }
    }

    #if DEBUG
    /// The item named after `flag`, ledger ignored. `-coach uncheck`, `-tour map`.
    func forced(by flag: String) -> Item? {
        LaunchFlags.value(after: flag).flatMap(Item.init(rawValue:))
    }
    #endif
}
