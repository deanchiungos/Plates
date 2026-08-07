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

    /// First launch gets one player, one trip and one book, so neither the Drive
    /// screen nor the Book tab opens on an empty state.
    static func seedIfNeeded() {
        #if DEBUG
        // Only take the fixture path if the fixture actually ran. It refuses against
        // an iCloud-backed store, and falling through to ordinary seeding then is the
        // difference between "no demo data" and "no players at all".
        if DemoData.isRequested, DemoData.install(into: context) {
            // The fixture's players are named, so it is not a fresh install as far as
            // the profile prompt is concerned — otherwise every screenshot run opens
            // on a "who's playing?" sheet.
            DevicePlayer.markProfileSet()
            // Falls through to the device-player pin below rather than returning.
            // The fixture is a stand-in for a real install and has to be pinned the
            // same way, or a demo host resolves its identity by fallback and every
            // two-device test is exercising a path no shipping install takes.
            pinDevicePlayer()
            return
        }
        #endif

        let playerCount = (try? context.fetchCount(FetchDescriptor<Player>())) ?? 0
        if playerCount == 0 {
            context.insert(Player(name: "Me", colorIndex: 0))
        } else {
            // Players already here means this install has been played. Whoever it is
            // has a name they chose, or chose to keep, and asking "who's playing?" on
            // an update would be the app forgetting somebody it has known for months.
            DevicePlayer.markProfileSet()
        }

        let tripCount = (try? context.fetchCount(FetchDescriptor<Trip>())) ?? 0
        if tripCount == 0 {
            context.insert(Trip(name: "Summer Roadtrip"))
        }

        // Also runs for installs that predate books, which is the point — everyone
        // gets a shelf to collect onto without having to create one first.
        let bookCount = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        if bookCount == 0 {
            context.insert(Book(name: "My Plate Book"))
        }

        try? context.save()
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
    private static func pinDevicePlayer() {
        if UserDefaults.standard.string(forKey: DevicePlayer.key) == nil,
           let me = DevicePlayer.current(in: context) {
            DevicePlayer.adopt(me)
        }

        #if DEBUG
        // `-asPlayer Mia` names this phone without typing. Two simulators both seed
        // a player called "Me", so without it a two-device party is two identical
        // players and the one thing the test is checking cannot be seen.
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-asPlayer"), at + 1 < args.count,
           let me = DevicePlayer.current(in: context) {
            me.name = args[at + 1]
            try? context.save()
            DevicePlayer.markProfileSet()
        }
        #endif
    }
}
