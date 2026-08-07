#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixture, used for screenshots and previews.
///
/// Opt-in: it only runs when the app is launched with `-demoData`. It is compiled
/// out of Release entirely, so there is no path by which a real player sees it.
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    /// Mirrors the design mockup: a westward trip, three people in the car, and an
    /// uneven split so the leader treatment on the player strip is actually visible.
    /// Every jurisdiction in PlateStyle.catalog is styled now, so this mix exists to
    /// show found-vs-unfound tiles side by side rather than styled-vs-fallback.
    private static let script: [(code: String, player: Int)] = [
        ("CA", 0), ("NV", 1), ("UT", 2), ("AZ", 0), ("CO", 1), ("NM", 0),
        ("KS", 2), ("MO", 1), ("IL", 0), ("TX", 0), ("OK", 1), ("AR", 2),
        ("NE", 0), ("WY", 1), ("ID", 0), ("OR", 2), ("WA", 1), ("MT", 0),
        ("AK", 1), ("HI", 2), ("NY", 0),
        // Two provinces, so the Canada map has found regions to draw and not only
        // rarity bands. A Newark start makes both entirely plausible sightings.
        ("ON", 1), ("QC", 2)
    ]

    /// Refuses to run against a store that syncs. This is the important one.
    ///
    /// The fixture opens by deleting every sighting, trip, book and player, and then
    /// inserts its own. Against the local store that is exactly what a fixture
    /// should do. Against an **iCloud-backed** store it is a disaster in two
    /// directions: it wipes a real collection, and the replacement — Dad, Mia, Theo,
    /// "Summer Roadtrip" — is written into the user's private CloudKit database,
    /// syncs to every device they own, and stays there. Removing the launch argument
    /// afterwards fixes nothing, because the records are already in iCloud and sync
    /// back. There is no undo.
    ///
    /// So: `-demoData` requires `-noCloud`. Screenshot runs already pass both; a
    /// device run that forgets gets a loud refusal and its real data untouched.
    /// Returns whether it actually installed. A refusal has to be distinguishable
    /// from a success, or the caller takes the fixture path — and its early return —
    /// against a store the fixture never touched, leaving the app with no seeded
    /// player at all.
    @discardableResult
    @MainActor
    static func install(into context: ModelContext) -> Bool {
        guard !PlatesStore.isCloudBacked else {
            print("""

            ⚠️  -demoData REFUSED: this store is backed by iCloud.

                The fixture deletes everything and inserts its own players and trips.
                On a synced store that would wipe your real collection and push
                "Dad / Mia / Theo" into your iCloud account permanently.

                Run with -noCloud as well if you want the fixture.

            """)
            return false
        }

        // start from a clean slate so repeated launches are deterministic
        try? context.delete(model: Sighting.self)
        try? context.delete(model: Trip.self)
        try? context.delete(model: Book.self)
        try? context.delete(model: Player.self)

        let players = [
            Player(name: "Dad",  colorIndex: 0),
            Player(name: "Mia",  colorIndex: 1),
            Player(name: "Theo", colorIndex: 2)
        ]
        // Two of the three pick a face and one keeps initials, so every screen that
        // draws a player has both cases in it rather than only the pretty one.
        players[1].avatar = "🦊"
        players[2].avatar = "🚀"
        players.forEach(context.insert)

        // `-fullCar` tops the car up to the six-player cap. Three people read fine
        // in the standings strip and six is where it has to hold up, so the fixture
        // needs both. Named after the last three colours in the palette, since the
        // cap exists because the palette runs out.
        if ProcessInfo.processInfo.arguments.contains("-fullCar") {
            for (offset, name) in ["Nan", "Sam", "Jo"].enumerated() {
                context.insert(Player(name: name, colorIndex: 3 + offset))
            }
        }

        let trip = Trip(name: "Summer Roadtrip",
                        origin: "Newark",
                        destination: "San Diego")
        trip.startedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        // Pinned, so the geographic rarity model is exercised rather than silently
        // falling back to the national defaults.
        trip.originLat = 40.7357;  trip.originLon = -74.1724
        trip.destinationLat = 32.7157; trip.destinationLon = -117.1611
        // `-trucks` flips the fleet the rarity model counts, so the two tables can
        // be screenshotted side by side without tapping through the editor.
        trip.includesTrucks = ProcessInfo.processInfo.arguments.contains("-trucks")
        context.insert(trip)

        // A second, finished trip so the Trips screen has both states to show and
        // switching between trips is exercisable.
        let past = Trip(name: "Thanksgiving Drive",
                        origin: "Boston",
                        destination: "Pittsburgh",
                        scoringMode: .weighted)
        past.originLat = 42.3601; past.originLon = -71.0589
        past.destinationLat = 40.4406; past.destinationLon = -79.9959
        past.startedAt = Calendar.current.date(byAdding: .day, value: -240, to: Date()) ?? Date()
        past.endedAt = Calendar.current.date(byAdding: .day, value: -237, to: Date())
        // `-archived` pre-archives it, so the archived section and its absence
        // from every picker can be screenshotted without tapping through.
        if ProcessInfo.processInfo.arguments.contains("-archived") {
            past.archivedAt = Date()
        }
        context.insert(past)

        // `-bareDone` adds a second finished trip with no route and only a few
        // plates. That is the record sheet's smallest honest shape — short enough
        // that the plate log *and* the buttons under it fit one screenshot, which
        // the Thanksgiving fixture's map pushes off the bottom.
        var bareDone: Trip?
        if ProcessInfo.processInfo.arguments.contains("-bareDone") {
            let errand = Trip(name: "Airport Runs", scoringMode: .classic)
            bareDone = errand
            errand.startedAt = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let over = errand.startedAt.addingTimeInterval(86_400)
            errand.endedAt = over
            errand.archivedAt = Date()  // newest archive date, so `.archived.first` finds it
            context.insert(errand)
            for (offset, code) in ["NJ", "DE", "QC"].enumerated() {
                let s = Sighting(plateCode: code, trip: errand,
                                 player: players[offset % players.count],
                                 spottedAt: errand.startedAt.addingTimeInterval(Double(offset) * 3_000))
                s.rarityWhenSpotted = [1, 4, 8][offset]
                context.insert(s)
            }
        }
        for (offset, code) in ["MA", "CT", "NY", "PA", "NJ", "OH", "VT"].enumerated() {
            let old = Sighting(plateCode: code,
                               trip: past,
                               player: players[offset % players.count],
                               spottedAt: past.startedAt.addingTimeInterval(Double(offset) * 900))
            let t = Double(offset) / 6.0
            old.spottedLat = 42.3601 + (40.4406 - 42.3601) * t + sin(Double(offset)) * 0.25
            old.spottedLon = -71.0589 + (-79.9959 + 71.0589) * t
            context.insert(old)
        }

        // A genuinely short drive. Short trips are the case a fixed location filter
        // got wrong — 2 km of granularity is 6% of a run like this — so there has to
        // be a fixture for one. `-target short` selects it.
        let hop = Trip(name: "Shore Run", origin: "Newark", destination: "Asbury Park",
                       scoringMode: .unlimited)
        hop.originLat = 40.7357;  hop.originLon = -74.1724
        hop.destinationLat = 40.2204; hop.destinationLon = -74.0121
        hop.startedAt = Date().addingTimeInterval(-3_600)
        context.insert(hop)
        // Unlimited, with a repeat, so the mode's two distinctives — the xN count
        // and the long-press un-check — both have something to show.
        for (offset, code) in ["NJ", "NY", "PA", "DE", "NJ"].enumerated() {
            let seen = Sighting(plateCode: code, trip: hop, player: players[offset % players.count],
                                spottedAt: hop.startedAt.addingTimeInterval(Double(offset) * 400))
            seen.rarityWhenSpotted = PlateRarity.rarity(code, on: hop.route)
            let t = Double(offset) / 4.0
            seen.spottedLat = 40.7357 + (40.2204 - 40.7357) * t
            seen.spottedLon = -74.1724 + (-74.0121 + 74.1724) * t
            context.insert(seen)
        }

        // Two books, so switching between them and the all-time lens is exercisable.
        // The current one is deliberately *not* a superset of the trips: a book you
        // fill on the school run has plates the road trips never saw, and vice versa,
        // which is what makes the all-time view worth having.
        let book = Book(name: "2026 Book")
        book.startedAt = Calendar.current.date(byAdding: .day, value: -180, to: Date()) ?? Date()
        context.insert(book)
        // Scattered around one town rather than strung along a line, because that is
        // what a book *is*: months of school runs and car parks, not a drive. It is
        // also the case the Trail's camera has to survive — every pin inside about
        // fifteen kilometres, where a frame fitted tightly to the pins would zoom to
        // individual buildings.
        for (offset, code) in ["NJ", "NY", "PA", "FL", "TX", "CA", "MD", "VA", "GOV"].enumerated() {
            let errand = Sighting(plateCode: code,
                                  in: book,
                                  player: players[offset % players.count],
                                  spottedAt: book.startedAt.addingTimeInterval(Double(offset) * 86_400 * 9))
            errand.spottedLat = 40.7357 + sin(Double(offset) * 1.7) * 0.06
            errand.spottedLon = -74.1724 + cos(Double(offset) * 2.3) * 0.08
            context.insert(errand)
        }
        // A repeat, so the ×N corner mark has something to draw.
        context.insert(Sighting(plateCode: "NJ", in: book, player: players[0]))
        // And a plate two different people claimed, for the corner's *other* state:
        // a claimant stack rather than a ×N. The two used to render identically,
        // which is how somebody who logged a plate once ended up looking at a ×4.
        // CA on purpose — it is high enough in the grid to be on screen without
        // scrolling, so the case is screenshot-testable.
        context.insert(Sighting(plateCode: "CA", in: book, player: players[1],
                                spottedAt: book.startedAt.addingTimeInterval(86_400 * 60)))

        let oldBook = Book(name: "First Book")
        oldBook.startedAt = Calendar.current.date(byAdding: .day, value: -900, to: Date()) ?? Date()
        context.insert(oldBook)
        for (offset, code) in ["NJ", "NY", "ME", "SC", "ON"].enumerated() {
            context.insert(
                Sighting(plateCode: code,
                         in: oldBook,
                         player: nil,
                         spottedAt: oldBook.startedAt.addingTimeInterval(Double(offset) * 86_400 * 20))
            )
        }
        UserDefaults.standard.set(book.id.uuidString, forKey: PlaySelection.bookKey)

        // `-folded` seeds the shelved-in-a-book state — the finished trip's
        // sightings gain a book reference exactly as `TripsScreen.fold` leaves
        // them, so the ×N marks, the record sheet's remove button and the book's
        // swollen count can all be screenshotted without tapping through the flow.
        if ProcessInfo.processInfo.arguments.contains("-folded") {
            for s in past.allSightings { s.book = book }
            for s in bareDone?.allSightings ?? [] { s.book = book }
        }

        // Point the Drive screen at the live trip, not whichever target a previous
        // launch happened to leave selected. `-target book` opens on the book instead,
        // so the book-filling grid can be screenshotted.
        // `-target past` selects the short finished trip instead, which is the
        // case that matters for the log map: a few sightings inside one state.
        let argv = ProcessInfo.processInfo.arguments
        let chosen = argv.contains("past") ? past
                   : argv.contains("short") ? hop
                   : trip
        UserDefaults.standard.set(chosen.id.uuidString, forKey: TripSelection.key)
        let args = ProcessInfo.processInfo.arguments
        let wantsBook = (args.firstIndex(of: "-target").map { $0 + 1 < args.count && args[$0 + 1] == "book" }) ?? false
        UserDefaults.standard.set(wantsBook ? "book" : "trip", forKey: PlaySelection.kindKey)

        // `-manyTrips` stands up a full list, which is the case the fixture had no
        // answer for. Everything here is sized for one trip and reads fine at that
        // size; the switcher growing past the bottom of the screen only shows up
        // somewhere past ten, and there was no way to get there without tapping
        // "New trip" a dozen times by hand. Half of them finished, so the archive
        // has both kinds in it.
        if argv.contains("-manyTrips") {
            let names = ["Thanksgiving", "Cape Cod", "Blue Ridge", "Route 66",
                         "Maine in Fall", "Florida Keys", "Big Sur", "Yellowstone",
                         "Nova Scotia", "Great Lakes", "Texas Loop", "Utah Parks"]
            for (offset, name) in names.enumerated() {
                let extra = Trip(name: name, scoringMode: .weighted)
                extra.startedAt = Calendar.current.date(
                    byAdding: .day, value: -30 * (offset + 2), to: Date()) ?? Date()
                if offset.isMultiple(of: 3) {
                    let done = extra.startedAt.addingTimeInterval(86_400 * 4)
                    extra.endedAt = done
                    extra.archivedAt = done
                }
                // One pinned, so the ordering and the pin glyph have a case to show.
                // Deliberately an old trip: pinning only proves anything when it
                // jumps something that would otherwise be near the bottom.
                if name == "Utah Parks" { extra.pinnedAt = Date() }
                context.insert(extra)
            }
        }

        // spread the timestamps so "most recent spotter" is well defined
        for (offset, entry) in script.enumerated() {
            let when = trip.startedAt.addingTimeInterval(Double(offset) * 600)
            let sighting = Sighting(plateCode: entry.code,
                                    trip: trip,
                                    player: players[entry.player],
                                    spottedAt: when)
            // Banked from the trip's start point, as a real claim made at the
            // beginning of the drive would have been — without this the fixture
            // cannot show the difference between a claimed and an unclaimed plate.
            sighting.rarityWhenSpotted = PlateRarity.rarity(entry.code, on: trip.route)
            // Strung along the route so the log map has a drive to draw rather than
            // a single dot. Deterministic jitter, not random: a fixture that framed
            // itself differently on every launch would make screenshots useless.
            let t = Double(offset) / Double(max(script.count - 1, 1))
            let wobble = sin(Double(offset) * 1.7) * 0.9
            sighting.spottedLat = 40.7357 + (32.7157 - 40.7357) * t + wobble * 0.35
            sighting.spottedLon = -74.1724 + (-117.1611 + 74.1724) * t + wobble * 0.5

            // `-trailStack` parks five of them on one fix — a rest stop where a run
            // of plates went past in a couple of minutes. The Trail fans co-located
            // pins out rather than collapsing them into a count, and the route
            // spreads every sighting far enough apart that nothing here would ever
            // exercise that path otherwise.
            // `-trailStack3` makes it three instead. An odd count with a card exactly
            // on the centre line behaves differently from an even spread, and three is
            // the smallest group that shows it.
            let stackSize = args.contains("-trailStack3") ? 3
                          : args.contains("-trailStackBig") ? 12 : 5
            if args.contains("-trailStack") || args.contains("-trailStack3")
                || args.contains("-trailStackBig"),
               (5..<(5 + stackSize)).contains(offset) {
                sighting.spottedLat = 39.7392
                sighting.spottedLon = -104.9903
            }
            context.insert(sighting)
        }

        // California twice, by two different people. Under shared claims a plate
        // stays open after the first call, so the tile has to show a group rather
        // than a single chip — and nothing else in the fixture produces one.
        let alsoCalifornia = Sighting(plateCode: "CA", trip: trip, player: players[1],
                                      spottedAt: trip.startedAt.addingTimeInterval(300))
        alsoCalifornia.rarityWhenSpotted = PlateRarity.rarity("CA", on: trip.route)
        alsoCalifornia.spottedLat = 40.6; alsoCalifornia.spottedLon = -75.2
        context.insert(alsoCalifornia)

        // `-foundAll` tops the live trip up to the whole catalog. Reaching the states
        // where everything is found — the all-fifty milestone, a fully green map, the
        // filter's "nothing left" card — otherwise means tapping 65 tiles by hand.
        if args.contains("-foundAll") {
            let already = Set(script.map(\.code))
            for (offset, plate) in Plate.all.filter({ !already.contains($0.code) }).enumerated() {
                context.insert(
                    Sighting(plateCode: plate.code,
                             trip: trip,
                             player: players[offset % players.count],
                             spottedAt: trip.startedAt.addingTimeInterval(Double(offset) * 300))
                )
            }
        }

        try? context.save()

        // Sightings are inserted straight into the store here, which skips the
        // record path where a fact is normally unlocked. Deal a couple per collected
        // plate so the map's detail sheet shows the real thing rather than a wall of
        // locked slots.
        FactBook.reset()
        let collected = Set(script.map(\.code))
            .union(book.seenCodes)
            .union(oldBook.seenCodes)
            .union(past.seenCodes)
        for code in collected {
            _ = FactBook.fact(for: code)
            _ = FactBook.fact(for: code)
        }
        return true
    }
}
#endif
