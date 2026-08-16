import Foundation
import SwiftData

enum ScoringMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, weighted, unlimited

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:   return String(localized: "Classic scoring")
        case .weighted:  return String(localized: "Weighted scoring")
        case .unlimited: return String(localized: "Unlimited scoring")
        }
    }

    var blurb: String {
        switch self {
        case .classic:   return String(localized: "One point per state, however many times you see it.")
        case .weighted:  return String(localized: "Rarer plates are worth more, judged against your route.")
        case .unlimited: return String(localized: "Every sighting scores, so keep counting.")
        }
    }
}

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    /// Index into `Theme.playerColors` — storing the index rather than a hex string
    /// keeps players correct if the palette is ever retuned.
    var colorIndex: Int = 0
    var joinedAt: Date = Date()

    /// An emoji to be, instead of initials.
    ///
    /// Optional, and stays optional: initials are a perfectly good answer and the
    /// grown-up in the car will often want them. But this is a game played mostly by
    /// children, where "I'm the fox" is a more useful handle than "AD" — and in a
    /// party, where four circles sit side by side, a picture is legible at sizes two
    /// letters are not.
    ///
    /// NOTE: this is the first added property since the CloudKit schema was
    /// deployed. Optional with no default, which is the shape CloudKit requires, but
    /// it still needs a production deploy before any build that carries it reaches
    /// TestFlight. See the warning at the top of `PlatesStore`.
    var avatar: String?

    /// Nullify, not cascade. Removing someone from the car must not un-collect
    /// the plates they spotted — the sighting happened. Their sightings survive
    /// with no owner, so the trip's count is unchanged and only the per-player
    /// standings lose those points.
    @Relationship(deleteRule: .nullify, inverse: \Sighting.player)
    var sightings: [Sighting]? = []

    init(name: String, colorIndex: Int) {
        self.id = UUID()
        self.name = name
        self.colorIndex = colorIndex
        self.joinedAt = Date()
    }

    /// How many people can be in the car: as many as you like.
    ///
    /// There was briefly a cap of six, on the reasoning that six is how many
    /// identity colors there are and the standings strip ran out of width past
    /// that. The width was the real problem and a cap was the wrong fix for it —
    /// the strip scrolls now, so each person keeps a readable card however many
    /// there are. Colors do start repeating after the sixth, which is a genuine
    /// cost and a much smaller one than turning somebody away from the game.

    var initial: String { String(name.prefix(1)).uppercased() }

    /// What goes in the circle: their emoji if they picked one, else initials.
    ///
    /// Two accessors rather than one because the sizes are genuinely different. A
    /// 24pt avatar can hold two letters; the 12pt chip in a plate's corner cannot,
    /// and has always shown one. An emoji is a single glyph either way, so it simply
    /// wins in both.
    /// Falls back to initials when the chosen emoji cannot be drawn here — see
    /// `Glyphs`. A box is worse than a letter.
    var face: String { usesEmoji ? (avatar ?? initials2) : initials2 }
    var smallFace: String { usesEmoji ? (avatar ?? initial) : initial }

    /// Two letters, for the overlapping avatar circles.
    ///
    /// Initials where there are two words to take them from — "Aunt Deb" is AD —
    /// and the first two letters otherwise, so "Mia" is MI rather than a lonely M
    /// in a circle sized for a pair. A single letter reads as a mistake next to
    /// four two-letter neighbours.
    var initials2: String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            return (words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?

    /// What a new trip is scored by, in one place.
    ///
    /// Weighted rather than Classic. Classic held the default because it is the
    /// version of the game everyone already knows from the back seat — one point a
    /// state, nothing to explain. But the app's own answer to "what is this plate
    /// worth" is the route-aware rarity model, and under Classic that entire machine
    /// is decoration: the tiers still flash, the map still colors, and none of it
    /// reaches the score. A default that ignores the best thing the app does is the
    /// wrong default.
    ///
    /// Only new trips are affected. The mode is stored per trip, so every existing
    /// one keeps what it was created with and no score anywhere moves. It is also
    /// still the first thing in the trip editor, for anyone who wants the plain game.
    ///
    /// Referenced by the editor's picker as well, so the mode a new trip is saved
    /// with and the mode the picker opens on cannot drift apart.
    static let defaultScoringMode: ScoringMode = .weighted

    var scoringModeRaw: String = Trip.defaultScoringMode.rawValue

    /// Where the trip runs from and to. Both optional — plenty of trips are just
    /// "the drive to Grandma's" and forcing two destinations before you can start
    /// spotting would be a tax on the common case.
    var origin: String?
    var destination: String?

    /// Coordinates from the map picker. Stored as loose Doubles rather than a
    /// CLLocationCoordinate2D so the model stays free of CoreLocation — and so a
    /// place typed without picking a suggestion still saves its name.
    var originLat: Double?
    var originLon: Double?
    var destinationLat: Double?
    var destinationLon: Double?

    /// The most recent position seen while this trip was being played, and when.
    ///
    /// One point, overwritten — not a track. The app has no use for where you have
    /// been, only for where you are, so storing a history would be collecting
    /// something it would then have to justify keeping.
    var currentLat: Double?
    var currentLon: Double?
    var locatedAt: Date?

    /// Count pickups, SUVs and vans in the rarity model as well as cars.
    ///
    /// Per-trip rather than global, and still stored per trip, because it changes
    /// what the scores on *this* trip mean — two trips scored differently must not be
    /// silently rewritten by a switch flipped later.
    ///
    /// No longer *asked*, though. It was a checkbox in the trip editor, and a tester
    /// put it well: nobody knows what it is for. "Should pickups count as cars" is a
    /// modelling parameter, not a game setting, and the honest answer is yes — a
    /// pickup is a vehicle on the road with a plate on it, and excluding them
    /// undercounted every state where they dominate the fleet.
    ///
    /// Defaults to true for trips created from here on. Existing trips keep the value
    /// already stored against them, so no score anywhere moves — the same promise
    /// `defaultScoringMode` makes, for the same reason.
    var includesTrucks: Bool = true

    /// Put away, but not deleted.
    ///
    /// An archived trip stops being offered anywhere you choose what to play — the
    /// switcher, the trips list, the trail's filter. Nothing about the data changes:
    /// its sightings still exist, still belong to it, and still count toward the
    /// all-time history, which is the difference between archiving and deleting.
    ///
    /// The alternative was to lean on `endedAt`, and it is not the same thing.
    /// Finishing a trip is a fact about the drive — it is over — and a finished trip
    /// is still worth switching back to. Archiving is a statement about the list:
    /// stop showing me this.
    var archivedAt: Date?

    /// Kept at the top of every list, regardless of date.
    ///
    /// The lists sort newest-first, which is right almost always and wrong in the
    /// one case that matters most: a trip you are actually in the middle of, that
    /// you started before the three you made last week. Pinning is the manual
    /// override for "this is the one I care about", and it is the cheapest answer to
    /// a long list — it does not shorten it, it just puts the answer first.
    ///
    /// A date rather than a flag, so several pinned trips have an order of their own
    /// (most recently pinned first) instead of falling back on the date they started.
    var pinnedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Sighting.trip)
    var sightings: [Sighting]? = []

    init(name: String,
         origin: String? = nil,
         destination: String? = nil,
         scoringMode: ScoringMode = Trip.defaultScoringMode) {
        self.id = UUID()
        self.name = name
        self.origin = origin?.nilIfBlank
        self.destination = destination?.nilIfBlank
        self.startedAt = Date()
        self.scoringModeRaw = scoringMode.rawValue
    }

    /// The fallback matches the stored default, so an unreadable raw value lands on
    /// the same mode a fresh trip would rather than on a second, invisible default.
    var scoringMode: ScoringMode {
        get { ScoringMode(rawValue: scoringModeRaw) ?? Trip.defaultScoringMode }
        set { scoringModeRaw = newValue.rawValue }
    }

    var isActive: Bool { endedAt == nil }

    var isArchived: Bool { archivedAt != nil }

    /// 1-based, so the first day of a trip reads "day 1". A finished trip stops
    /// counting at the day it ended rather than ticking on forever.
    var dayNumber: Int {
        let end = endedAt ?? Date()
        let days = Calendar.current.dateComponents([.day], from: startedAt, to: end).day ?? 0
        return max(1, days + 1)
    }

    /// What the rarity model needs from this trip, or nil if no start has been
    /// pinned yet — in which case rarity falls back to the national defaults.
    @MainActor
    var route: PlateRarity.Route? {
        guard let oLat = originLat, let oLon = originLon else { return nil }
        // The road between the pins, when it has already been fetched for something
        // else — the editor's preview or the share poster. Never fetched from here:
        // this is read during a render, and rarity has a correct answer without it.
        var path: [PlateRarity.Waypoint] = []
        if let dLat = destinationLat, let dLon = destinationLon {
            path = RouteCache.shared.knownPath(from: .init(latitude: oLat, longitude: oLon),
                                               to: .init(latitude: dLat, longitude: dLon))
        }
        return .init(oLat: oLat, oLon: oLon,
                     dLat: destinationLat, dLon: destinationLon,
                     currentLat: currentLat, currentLon: currentLon,
                     includeTrucks: includesTrucks,
                     isWinter: PlateRarity.Route.snowbirdSeason,
                     path: path)
    }

    /// "Newark → Orlando", or whichever half was filled in. Nil when neither was.
    var routeLabel: String? {
        switch (origin?.nilIfBlank, destination?.nilIfBlank) {
        case let (from?, to?):  return "\(from) \u{2192} \(to)"
        case let (from?, nil):  return "From \(from)"
        case let (nil, to?):    return "To \(to)"
        default:                return nil
        }
    }
}

/// An ongoing collection — the coin book.
///
/// A `Trip` is an event: it starts, it ends, and the plates found on it belong to
/// it. A `Book` is the other kind of container entirely. It has no route, no
/// destination and no end; you keep filling it across as many drives as it takes,
/// and you can open it in a car park with nothing running.
///
/// Starting a second book does not close the first, and nothing you do to a book
/// can touch the all-time record — that is the union of every sighting ever, which
/// is why "start a new book" is safe to offer.
@Model
final class Book {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()

    /// The most recent position seen while this book was open, and when.
    ///
    /// The same one-point-overwritten shape as `Trip`, and for the same reason: a
    /// book has no use for where you have been, only for where you are.
    ///
    /// A book needs this more than a trip does, not less. A trip has an origin and a
    /// destination to score against even before the first fix arrives; a book has
    /// nothing at all, so without a stored point it falls back to the national table
    /// every time it is reopened, and the national table is a ranking of fleet size —
    /// which is to say, it is not about where you are standing.
    var currentLat: Double?
    var currentLon: Double?
    var locatedAt: Date?

    /// Nullify, not cascade — deliberately the opposite of `Trip`. Deleting a book
    /// means "I am done with this shelf", not "I never saw those plates": the
    /// sightings survive with no book and stay in the all-time count. Emptying a
    /// book is a separate, explicit action.
    @Relationship(deleteRule: .nullify, inverse: \Sighting.book)
    var sightings: [Sighting]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.startedAt = Date()
    }

    /// "Since Mar 4" — a book has a start and no end, so that is the whole of its
    /// date line.
    var sinceLabel: String {
        "Since \(startedAt.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}

// MARK: - What plates get collected into

/// A trip, or a book.
///
/// Every derived number in the app — counts, standings, rarity, score — comes from
/// `sightings` and nothing else. Hoisting that one requirement into a protocol is
/// what lets a book reuse the whole of `Scoring.swift` rather than reimplementing
/// it, and guarantees the two containers can never drift apart in how they count.
protocol PlateCollection: AnyObject, Identifiable where ID == UUID {
    var id: UUID { get }
    var name: String { get }
    var sightings: [Sighting]? { get }

    /// The route rarity is judged against, or nil to fall back to the national
    /// table. Always nil for a book, which is not a journey.
    ///
    /// Main-actor because `Trip.route` reads `RouteCache.shared`, which is. The
    /// requirement said nothing about isolation while the conformance claimed it,
    /// which Swift 5 accepts silently and Swift 6 does not — and in the meantime the
    /// rule was kept by nothing but every caller happening to be on the main actor.
    @MainActor var route: PlateRarity.Route? { get }
    var scoringMode: ScoringMode { get }

    /// Files a fresh sighting under this collection.
    func adopt(_ sighting: Sighting)
}

extension Trip: PlateCollection {
    func adopt(_ sighting: Sighting) { sighting.trip = self }
}

extension Book: PlateCollection {
    /// A book has no journey, but it always has a *here* — and here is what rarity
    /// is actually about.
    ///
    /// This used to return nil, which sent every book to the national table. That
    /// table is a ranking of registrations with no distance term in it at all, so a
    /// book scored California 1 and Montana 10 whether you were filling it in
    /// Sacramento or Missoula. Sacramento is where a California plate is *least*
    /// worth having, and the book was the one place in the app that could not tell.
    ///
    /// A single point is a legitimate route: `PlateRarity` measures from the current
    /// fix when it has one and ignores the endpoints entirely, so a book is just the
    /// degenerate case where the origin and the current position are the same place.
    /// Trucks stay out of it — that switch is a per-trip decision about what a
    /// particular drive's scores mean, and a book spans too many drives to answer it
    /// once.
    @MainActor
    var route: PlateRarity.Route? {
        guard let lat = currentLat, let lon = currentLon else { return nil }
        return .init(oLat: lat, oLon: lon, currentLat: lat, currentLon: lon,
                     isWinter: PlateRarity.Route.snowbirdSeason)
    }

    /// One point per state, permanently. Weighting a lifetime collection against a
    /// route it never had would be inventing a number.
    var scoringMode: ScoringMode { .classic }

    func adopt(_ sighting: Sighting) { sighting.book = self }
}

extension String {
    /// Whitespace-only input is the same as no input — otherwise a stray space
    /// becomes a destination and the route label renders an arrow to nowhere.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Which trip the Game screen is currently showing.
///
/// This is a preference, not a fact about the world, so it lives in
/// `UserDefaults` rather than on the model. Storing it as a flag on `Trip` would
/// mean maintaining an "exactly one is current" invariant across every insert and
/// delete, and any bug there silently shows the wrong trip's plates.
enum TripSelection {
    static let key = "currentTripID"

    /// Falls back to the newest trip, so a deleted or missing selection can never
    /// leave the Game screen empty while trips still exist.
    ///
    /// Archived trips are invisible here, which is what makes archiving stick: every
    /// surface that offers a trip resolves through this, so none of them has to
    /// remember to filter. Archiving the trip you were playing therefore moves you
    /// to the next one rather than stranding you on something you just put away.
    static func current(from trips: [Trip], id: String) -> Trip? {
        // Finished trips are invisible here for the same reason archived ones are:
        // this resolves what you are *collecting into*, and a trip you have marked
        // done is not accepting plates. Falls back to the newest one that is.
        let open = trips.collectable
        return open.first { $0.id.uuidString == id } ?? open.first
    }
}

/// What the Drive screen is filling in right now.
enum PlayTarget: Identifiable {
    case trip(Trip)
    case book(Book)

    var id: UUID { collection.id }

    var collection: any PlateCollection {
        switch self {
        case .trip(let t): return t
        case .book(let b): return b
        }
    }

    var name: String { collection.name }

    var isBook: Bool {
        if case .book = self { return true }
        return false
    }
}

/// Which container the Drive screen is pointed at, held as three separate
/// preferences rather than one.
///
/// `kind` says trip-or-book; the two ids remember your place in *each* so switching
/// to a book and back does not lose which trip you were on. Splitting them this way
/// also means the Book tab can change which book is yours without yanking the Drive
/// screen off a trip that is still running.
enum PlaySelection {
    static let kindKey = "currentTargetKind"
    static let bookKey = "currentBookID"
    // The trip half keeps `TripSelection.key`, so existing installs carry over.

    static func current(kind: String, tripID: String, bookID: String,
                        trips: [Trip], books: [Book]) -> PlayTarget? {
        let book = books.first { $0.id.uuidString == bookID } ?? books.first

        if kind == "book", let book { return .book(book) }
        if let trip = TripSelection.current(from: trips, id: tripID) { return .trip(trip) }
        // The saved kind said trip but there are none left. Falling through to a
        // book beats showing an empty screen while there is something to fill.
        if let book { return .book(book) }
        return nil
    }

    /// Written straight to `UserDefaults` rather than through the `@AppStorage`
    /// properties — `@AppStorage` observes the store, so every screen still updates,
    /// and one call site can set the pair atomically instead of each screen
    /// remembering to set both.
    static func select(_ target: PlayTarget) {
        let defaults = UserDefaults.standard
        switch target {
        case .trip(let trip):
            defaults.set("trip", forKey: kindKey)
            defaults.set(trip.id.uuidString, forKey: TripSelection.key)
        case .book(let book):
            defaults.set("book", forKey: kindKey)
            defaults.set(book.id.uuidString, forKey: bookKey)
        }
    }

    /// Marks a book as "your book" without changing what the Drive screen is
    /// filling. Browsing the Book tab should not interrupt a trip in progress.
    static func selectBookOnly(_ book: Book) {
        UserDefaults.standard.set(book.id.uuidString, forKey: bookKey)
    }
}

/// One plate, seen once, by one player. This is the single source of truth —
/// every count, score and badge in the app is derived from these and nothing else.
@Model
final class Sighting {
    var id: UUID = UUID()
    var plateCode: String = ""
    var spottedAt: Date = Date()

    /// A sighting belongs to the trip it was logged on, and may *additionally* be
    /// shelved in one book.
    ///
    /// Logged fresh, exactly one of these is set — the container being played.
    /// Both set means the sighting came from a trip that was folded into a book
    /// afterwards: one record, two containers, so the book can show a trip's
    /// plates without the all-time count seeing them twice. Both nil is legal too
    /// — an orphan from a deleted book still happened, and still counts all-time.
    var trip: Trip?
    var book: Book?
    var player: Player?

    /// What this plate was worth at the moment it was claimed.
    ///
    /// Frozen on purpose. Rarity moves as you drive — a Kentucky plate that was a
    /// find in Nevada is wallpaper by the time you reach Louisville — so a plate
    /// scored live would quietly lose value after you had already earned it. What
    /// you claimed it for is what it stays worth. Only *unclaimed* plates track the
    /// car.
    ///
    /// Optional because sightings recorded before this existed have no answer, and
    /// inventing one retroactively would be worse than falling back to the live
    /// number for them.
    var rarityWhenSpotted: Int?

    /// Where you were standing when you logged it, if location was on at the time.
    ///
    /// Optional and always will be: location is opt-in, most sightings before it was
    /// added have none, and a plate logged in a tunnel has none either. Every reader
    /// has to cope with nil rather than treat it as an error.
    var spottedLat: Double?
    var spottedLon: Double?

    init(plateCode: String, trip: Trip?, player: Player?, spottedAt: Date = Date()) {
        self.id = UUID()
        self.plateCode = plateCode
        self.trip = trip
        self.player = player
        self.spottedAt = spottedAt
    }

    /// The general form: file this under whichever container is being played.
    convenience init(plateCode: String,
                    in collection: (any PlateCollection)?,
                    player: Player?,
                    spottedAt: Date = Date()) {
        self.init(plateCode: plateCode, trip: nil, player: player, spottedAt: spottedAt)
        collection?.adopt(self)
    }

    var plate: Plate? { Plate.plate(for: plateCode) }

    /// Where it was logged, for the book's "first found on" line.
    var containerName: String? { trip?.name ?? book?.name }
}


extension Array where Element == Trip {
    /// The trips worth offering: everything not archived.
    ///
    /// A named property rather than a bare `filter` at each call site, so "did this
    /// list remember about archiving" is answerable by reading it.
    var playable: [Trip] { filter { !$0.isArchived } }

    /// The trips that will actually take a plate right now: not archived, and not
    /// marked done.
    ///
    /// The distinction from `playable` is the difference between browsing and
    /// collecting. The Trips list and the Trail's scope menu want `playable` — a
    /// finished trip is still a thing you look at, and its pins are still on the
    /// map. Every switcher that answers "what am I filling?" wants this one,
    /// because offering a closed trip there is offering a dead end.
    var collectable: [Trip] { filter { !$0.isArchived && $0.isActive } }

    var archived: [Trip] { filter(\.isArchived) }

    /// Done, but not put away — the drive that just ended, which is the one most
    /// worth looking at. Finishing no longer archives, so these sit in their own
    /// section rather than vanishing into the archive the moment they end.
    var finished: [Trip] { filter { !$0.isArchived && !$0.isActive } }

    /// Still taking plates. What the main list is actually about.
    var running: [Trip] { filter { !$0.isArchived && $0.isActive } }

    /// Pinned trips first, most recently pinned leading; everything else keeps the
    /// newest-first order the queries already come in.
    ///
    /// Applied at the display layer rather than in the `@Query` sort, because
    /// SwiftData cannot express "nulls last" on an optional date without turning the
    /// descriptor into something harder to read than this line.
    var pinnedFirst: [Trip] {
        enumerated().sorted { a, b in
            switch (a.element.pinnedAt, b.element.pinnedAt) {
            case let (x?, y?): return x > y
            case (_?, nil):    return true
            case (nil, _?):    return false
            // Stable: fall back to the order the query gave us.
            case (nil, nil):   return a.offset < b.offset
            }
        }.map(\.element)
    }
}
