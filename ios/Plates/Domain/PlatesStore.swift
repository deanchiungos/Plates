import Foundation
import SwiftData

/// The one SwiftData container, shared by the app and by the Siri intents.
///
/// App Intents run in the app's process but not inside its view hierarchy, so they
/// cannot reach `@Environment(\.modelContext)`. Both sides go through here instead.
/// Two containers opened separately on the same file would each hold their own
/// in-memory state and quietly disagree about what has been logged.
@MainActor
enum PlatesStore {

    /// Whether the store that actually opened is backed by iCloud.
    ///
    /// Read by the backup row on the Book screen. It is set as a side effect of
    /// opening `container`, which is safe only because nothing can observe it before
    /// the container exists — every reader goes through the container first.
    private(set) static var isCloudBacked = false

    /// Why iCloud was not used, when it was not. Surfaced verbatim rather than
    /// swallowed: "backup is off" with no reason is unactionable.
    private(set) static var cloudFailure: String?

    static let container: ModelContainer = {
        // CHANGING THIS SCHEMA IS A TWO-PART JOB.
        //
        // Adding a model here, or a property to one of these models, also requires
        // deploying the CloudKit schema to Production — CloudKit Console, container
        // iCloud.com.eggeppel.plates, Development, "Deploy Schema Changes".
        //
        // Nothing here will tell you that you forgot. Xcode builds run against the
        // *development* CloudKit environment, which creates record types on demand,
        // so sync keeps working perfectly at your desk. TestFlight and App Store
        // builds run against *production*, which never does, and every export fails
        // with CKError 2 (partialFailure). The bug therefore only ever appears in
        // front of testers. It cost an afternoon once already.
        //
        // Deployment is additive and permanent: record types and fields can never be
        // removed from production, so read the diff before confirming it.
        let schema = Schema([Trip.self, Book.self, Player.self, Sighting.self])

        // iCloud first. Both configurations point at the same default store file, so
        // this is genuinely a fallback and not a second database: a install that opens
        // local-only today keeps every plate it has, and adopts iCloud the moment the
        // entitlement and the account are both in place.
        if !isCloudDisabled {
            do {
                let store = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema,
                                                       cloudKitDatabase: .automatic))
                isCloudBacked = true
                return store
            } catch {
                // Reached when the entitlement is missing, the container does not
                // exist, or the device has no iCloud at all. None of those are worth
                // losing the app over — the local store is the source of truth and
                // sync is an addition to it.
                cloudFailure = error.localizedDescription
            }
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            // Nothing left to fall back to: the on-disk store itself is unreadable.
            fatalError("Could not open the plates store: \(error)")
        }
    }()

    /// `-noCloud` forces the local path, so the fallback is exercisable and the
    /// screenshot fixtures do not fight a real iCloud account.
    private static var isCloudDisabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-noCloud")
        #else
        return false
        #endif
    }

    static var context: ModelContext { container.mainContext }

    /// What Siri should log against — the same trip or book the Drive screen is on.
    ///
    /// Creates a trip if the store is somehow empty, because "I saw a Wyoming plate"
    /// failing on a technicality is a worse answer than starting one.
    static func currentTarget() -> (any PlateCollection)? {
        let trips = (try? context.fetch(FetchDescriptor<Trip>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        let books = (try? context.fetch(FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []

        let defaults = UserDefaults.standard
        if let target = PlaySelection.current(
            kind: defaults.string(forKey: PlaySelection.kindKey) ?? "trip",
            tripID: defaults.string(forKey: TripSelection.key) ?? "",
            bookID: defaults.string(forKey: PlaySelection.bookKey) ?? "",
            trips: trips, books: books) {
            return target.collection
        }

        let fresh = Trip(name: "Roadtrip")
        context.insert(fresh)
        PlaySelection.select(.trip(fresh))
        try? context.save()
        return fresh
    }

    /// Deliberately seeds nothing.
    ///
    /// This used to hand every first launch a player called "Me", a trip called
    /// "Summer Roadtrip" and a book called "My Plate Book", on the reasoning that an
    /// empty screen is a bad welcome. All three were wrong, for different reasons.
    ///
    /// The trip and the book were wrong because they were *somebody else's*. The Game
    /// tab has a considered empty state — "Nothing to fill yet", and a choice between
    /// a trip and a book with one line on the difference — and the seed meant nobody
    /// ever saw it. A new player landed on a grid belonging to a drive they had not
    /// taken, named after a season it might not be, and the first thing the app asked
    /// them to understand was why it had already decided for them. An empty state that
    /// asks a question beats a full one that answers the wrong one.
    ///
    /// The player was wrong because of the clock. This runs synchronously in
    /// `PlatesApp.init`, and CloudKit syncs asynchronously some seconds or minutes
    /// later — so on a reinstall or a new phone the player count here is zero even
    /// though the account has a perfectly good player, and seeding inserted a second
    /// one and pinned the device to it. The real person then arrived from iCloud with
    /// every plate they had ever logged and landed in Settings under "Other people",
    /// as a stranger. Nothing on this device can tell the difference between "new" and
    /// "not synced yet", so it no longer guesses: `DevicePlayer` tolerates having
    /// nobody, and the identity prompt creates or adopts one once there is enough on
    /// screen to be sure. See `IdentityPrompt`.
    ///
    /// What is left is the one thing that is safe to decide alone: an install that
    /// already has players has been played, so it is not asked who it is.
    static func seedIfNeeded() {
        #if DEBUG
        // `-forgetMe` throws away this device's claim on a player without touching the
        // store. It is the only way to reach the identity prompt twice: the flags are
        // one-shot by nature, and reinstalling to clear the keys also clears the very
        // people the prompt is supposed to offer. With `-demoData` it stands in for a
        // restored install exactly — a full account, and a phone that has never said
        // which of these it is.
        if ProcessInfo.processInfo.arguments.contains("-forgetMe") {
            DevicePlayer.forgetThisDevice()
        }

        // `-emptyTrip` is the state a first launch reaches one tap after the fork:
        // something to fill, and nothing in it. Nothing seeds that any more, and it
        // is the only state several onboarding marks fire against — reaching it
        // otherwise means typing a trip name into the simulator by hand.
        if ProcessInfo.processInfo.arguments.contains("-emptyTrip"),
           (try? context.fetchCount(FetchDescriptor<Trip>())) == 0 {
            let fresh = Trip(name: "Roadtrip")
            context.insert(fresh)
            try? context.save()
            PlaySelection.select(.trip(fresh))
        }

        // Only take the fixture path if the fixture actually ran. It refuses against
        // an iCloud-backed store, and falling through to ordinary seeding then is the
        // difference between "no demo data" and "no players at all".
        if DemoData.isRequested, DemoData.install(into: context) {
            // The fixture's players are named, so it is not a fresh install as far as
            // the profile prompt is concerned — otherwise every screenshot run opens
            // on a "who's playing?" sheet. Unless that is exactly what is being
            // tested, which is what `-forgetMe` alongside it means.
            if !ProcessInfo.processInfo.arguments.contains("-forgetMe") {
                DevicePlayer.markProfileSet()
            }
            // Falls through to the device-player pin below rather than returning.
            // The fixture is a stand-in for a real install and has to be pinned the
            // same way, or a demo host resolves its identity by fallback and every
            // two-device test is exercising a path no shipping install takes.
            pinDevicePlayer()
            return
        }
        #endif

        // Players already here means this install has been played. Whoever it is has a
        // name they chose, or chose to keep, and asking "who's playing?" on an update
        // would be the app forgetting somebody it has known for months.
        //
        // Note this is only ever *true* for an install that has genuinely run before —
        // a restore reaches here with a count of zero, having synced nothing yet, and
        // is left unmarked so the identity prompt can settle it properly.
        let playerCount = (try? context.fetchCount(FetchDescriptor<Player>())) ?? 0
        if playerCount > 0 { DevicePlayer.markProfileSet() }

        pinDevicePlayer()
    }

    /// Pin who this phone is, once, before anything can shuffle the roster.
    ///
    /// `DevicePlayer.resolve` falls back to the earliest-joined player when no id is
    /// stored, which is right on a fresh install and quietly wrong the moment a party
    /// merges somebody else's people in: a host who started playing last year has an
    /// earlier `joinedAt` than your own "Me", so the fallback would hand your identity
    /// to them and you would start logging plates as the host, on your own phone.
    /// Writing the id at launch means the fallback only ever runs while this device is
    /// still the only one in the store.
    ///
    /// Only for installs that have already said who they are. A device that has not
    /// been introduced yet must not pin anybody, because on a restore the roster it
    /// would be choosing from is whatever iCloud happens to have delivered so far —
    /// and "earliest to join" among *that* is as likely to be a party host from last
    /// summer as it is to be you. Left unpinned, `IdentityPrompt` asks.
    private static func pinDevicePlayer() {
        if DevicePlayer.hasProfile,
           UserDefaults.standard.string(forKey: DevicePlayer.key) == nil,
           let me = DevicePlayer.current(in: context) {
            DevicePlayer.adopt(me)
        }

        #if DEBUG
        // `-asPlayer Mia` names this phone without typing. Two simulators otherwise
        // reach a party as two players called the same thing — or, now that nothing is
        // seeded, as two players called nothing at all — and the one thing a two-device
        // test is checking cannot be seen. Inserts rather than renames, because on a
        // fresh simulator there is no longer anybody here to rename.
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-asPlayer"), at + 1 < args.count {
            let me = DevicePlayer.current(in: context) ?? {
                let fresh = Player(name: args[at + 1], colorIndex: 0)
                context.insert(fresh)
                return fresh
            }()
            me.name = args[at + 1]
            try? context.save()
            DevicePlayer.adopt(me)
            DevicePlayer.markProfileSet()
        }
        #endif
    }
}
