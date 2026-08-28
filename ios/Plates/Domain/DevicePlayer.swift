import Foundation
import SwiftData

/// Who this phone is playing as.
///
/// The app used to hold several players on one device and ask, on every tap, which
/// of them had spotted the plate. That made sense when one phone was the whole
/// game. It stops making sense the moment everyone in the car has their own: a
/// party would be asking "who spotted it?" about people each holding the phone that
/// could have answered. So the model is now one device, one identity, and the
/// question disappears — the phone *is* the person.
///
/// Resolution never fails and never guesses twice:
///
/// 1. the player `devicePlayerID` names, if it still exists;
/// 2. otherwise the earliest to join — which on essentially every install is the
///    "Me" that `PlatesStore.seedIfNeeded` created on first launch;
/// 3. and if there are somehow none at all, the caller seeds one.
///
/// Step 2 is deliberately deterministic rather than "pick one and remember it", so
/// this can be called from a view body without writing anything: an install that
/// has never opened Settings resolves to the same player every time, forever,
/// without a stored preference existing at all.
///
/// `UserDefaults` and not `NSUbiquitousKeyValueStore`, deliberately. An iPhone and
/// an iPad on one iCloud account share their `Player` rows through CloudKit, so
/// both will independently resolve to the same "Me" — which is correct, they are
/// the same human. Syncing the key would add nothing and would break the day that
/// stops being true.
enum DevicePlayer {
    static let key = "devicePlayerID"

    /// Where the claim is written. See `AppDefaults` for why this is not
    /// `UserDefaults.standard` directly.
    private static var store: UserDefaults { AppDefaults.store }

    /// Pure. No writes, no inserts — safe to call from a view body, which is where
    /// most callers are.
    static func resolve(from players: [Player]) -> Player? {
        if let stored = store.string(forKey: key),
           let named = players.first(where: { $0.id.uuidString == stored }) {
            return named
        }
        // Ties on `joinedAt` broken by id, for the same reason `SightingOrder` does
        // it: two devices resolving "the earliest" differently would attribute the
        // same taps to different people.
        return players.min {
            ($0.joinedAt, $0.id.uuidString) < ($1.joinedAt, $1.id.uuidString)
        }
    }

    /// For the callers that have a context but no `@Query` — Siri, mainly.
    @MainActor
    static func current(in context: ModelContext) -> Player? {
        resolve(from: (try? context.fetch(FetchDescriptor<Player>())) ?? [])
    }

    /// Who this device says it is, without touching the store.
    ///
    /// For the merges, which need to answer "is this row me?" about an id they were
    /// handed and must not rewrite their own user from somebody else's stale copy.
    /// Nil until a profile is adopted, and a nil here has to be read as "cannot
    /// tell", never as "not me" — comparing an id against nil is always unequal,
    /// which is how the party's ownership guard came to do nothing on fresh installs.
    static var currentID: String? {
        store.string(forKey: key)
    }

    static func adopt(_ player: Player) {
        store.set(player.id.uuidString, forKey: key)
    }

    // MARK: - Having a name

    /// Whether this phone has ever said who it is.
    ///
    /// A flag rather than a check for the seeded name, because "Me" is a legitimate
    /// thing to be called and somebody who deliberately keeps it should not be asked
    /// again every launch. Set when the profile sheet saves, and also at seed time
    /// for any install that already had players — those people have been using the
    /// app for months and do not need to be introduced to themselves.
    ///
    /// This matters most in a party. Every fresh install seeds the same "Me", so
    /// three phones in a car were three players called Me: identical in the member
    /// list, the standings and the spotter chips, with only the color telling them
    /// apart. Names are the fix, and the party is where they are worth insisting on.
    static let profileSetKey = "devicePlayerNamed"

    static var hasProfile: Bool {
        store.bool(forKey: profileSetKey)
    }

    static func markProfileSet() {
        store.set(true, forKey: profileSetKey)
    }

    #if DEBUG
    /// Un-claim this device, leaving every player where they are.
    ///
    /// Behind `-forgetMe`. See the note at the top of `PlatesStore.seedIfNeeded`.
    static func forgetThisDevice() {
        store.removeObject(forKey: key)
        store.removeObject(forKey: profileSetKey)
    }
    #endif
}
