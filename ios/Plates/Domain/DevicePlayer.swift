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

    /// Pure. No writes, no inserts — safe to call from a view body, which is where
    /// most callers are.
    static func resolve(from players: [Player]) -> Player? {
        if let stored = UserDefaults.standard.string(forKey: key),
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

    static func adopt(_ player: Player) {
        UserDefaults.standard.set(player.id.uuidString, forKey: key)
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
    /// list, the standings and the spotter chips, with only the colour telling them
    /// apart. Names are the fix, and the party is where they are worth insisting on.
    static let profileSetKey = "devicePlayerNamed"

    static var hasProfile: Bool {
        UserDefaults.standard.bool(forKey: profileSetKey)
    }

    static func markProfileSet() {
        UserDefaults.standard.set(true, forKey: profileSetKey)
    }

    /// Whether this install still carries a roster from before the party existed.
    ///
    /// Used once, to tell those people that the "who spotted it?" prompt has gone
    /// rather than letting them discover it by tapping a plate and watching it land
    /// on the wrong person. Nothing about their data changes — every past
    /// attribution, score and standing is exactly as it was.
    static let migrationNoticeKey = "partyMigrationNoticeShown"

    static func needsMigrationNotice(players: [Player]) -> Bool {
        players.count > 1
            && !UserDefaults.standard.bool(forKey: migrationNoticeKey)
    }

    static func migrationNoticeShown() {
        UserDefaults.standard.set(true, forKey: migrationNoticeKey)
    }
}
