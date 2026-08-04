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
        if DemoData.isRequested {
            DemoData.install(into: context)
            return
        }
        #endif

        let playerCount = (try? context.fetchCount(FetchDescriptor<Player>())) ?? 0
        if playerCount == 0 {
            context.insert(Player(name: "Me", colorIndex: 0))
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
    }
}
