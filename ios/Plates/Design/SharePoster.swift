import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// The one-pager you text somebody at the end of a drive.
///
/// A collection is only worth having if it can be shown to somebody, and until now
/// the only way to show this one was to hand over the phone. This renders a trip or
/// a book to a single image.
///
/// The picture itself is `ScenicPoster`. What used to live here was a second poster
/// view — the album page, with a leather spine down its left edge and the collection
/// laid out on cream. It is gone rather than kept behind a flag: two posters is not a
/// feature, it is two things to keep in step, and the one that survived is the one
/// that reads in a feed. The spine went with it and has no equivalent, which is a
/// real loss of a nice detail and the price of the page not being a page any more.
///
/// Laid out in points at a fixed width and rendered at `scale`, so the output is a
/// predictable size whatever phone it came from. Nothing in the poster reads the
/// environment: an `ImageRenderer` draws outside the view hierarchy and gets no
/// `@Environment`, no safe area and no color scheme, so everything it needs is
/// passed in.

// MARK: - Making one

@MainActor
enum ShareablePoster {

    /// A trip or book rendered to an image, or nil if the renderer could not produce
    /// one — which it can, on a memory-starved device, and a crash would be a poor
    /// way to end a nice drive.
    ///
    /// `scale: 2` rather than the screen's. The output has to be the same on every
    /// phone, and 2× of a 700pt page is a 1400px image: sharp in a Messages bubble,
    /// small enough to send over a bad connection at the end of a road trip.
    /// Async now, and only because of the map: `MKMapSnapshotter` is the one part
    /// of this that cannot be done inside `ImageRenderer`, which runs no tasks and
    /// waits for nothing. The picture has to be finished before the poster is laid
    /// out, so it is fetched here and handed in.
    static func image(for collection: any PlateCollection,
                      players: [Player]) async -> UIImage? {
        let index = collection.plateIndex()
        let people = collection.participants(from: players,
                                             me: DevicePlayer.resolve(from: players))
        let seen = Set(everyPlate.map(\.code).filter { index.has($0) })
        // Only worth drawing when more than one person is on it. A book filled alone
        // and a trip driven alone both get the collection and nothing else — and the
        // same test gates the chips on the tiles, so the standings and the marks that
        // let you check them appear and disappear together.
        let shared = people.count > 1
        return image(
            title: collection.name,
            subtitle: subtitle(for: collection),
            statesFound: Plate.states.count { seen.contains($0.code) },
            bestFind: rarestPlate(in: seen, scoredBy: collection.rarity(of:)),
            found: seen,
            standings: shared ? collection.standings(among: people) : [],
            claims: shared ? claims(from: index, over: seen) : [:],
            logged: collection.sightings?.count ?? 0,
            newHere: firsts(in: collection, over: seen),
            route: await road(of: collection)
        )
    }

    /// How many of these plates this phone had never logged anywhere before.
    ///
    /// The one number on the poster that needs more than the collection it is about:
    /// "new" is a claim against everything else you have ever done, so it is answered
    /// against every sighting in the store rather than against this trip's. A drive
    /// that turned up twenty states and one you had not already banked is a different
    /// afternoon from one that turned up four fresh ones, and the collection's own
    /// count cannot tell them apart.
    ///
    /// Provenance is by container name, which is what `PlateBook` already records and
    /// what the app shows everywhere else it says where a plate came from. Two
    /// collections sharing a name would confuse it; the failure is a count that is
    /// slightly generous on a poster, which is the right way for this to be wrong.
    ///
    /// Returns nil when there is nothing to say, so the pill, the middle card and the
    /// closing line all stand down together rather than one of them printing a zero.
    private static func firsts(in collection: any PlateCollection,
                               over seen: Set<String>) -> (count: Int, label: String)? {
        let all = (try? PlatesStore.context.fetch(FetchDescriptor<Sighting>())) ?? []
        guard !all.isEmpty else { return nil }
        let everything = PlateBook(sightings: all)
        let mine = collection.name
        let count = seen.count { everything.entry(for: $0)?.firstIn == mine }
        guard count > 0 else { return nil }
        return (count, collection is Trip
                ? String(localized: "NEW THIS DRIVE")
                : String(localized: "NEW IN THIS BOOK"))
    }

    /// Who banked each plate. Built once from the index rather than scanned per tile,
    /// for the reason `PlateIndex` exists at all.
    private static func claims(from index: PlateIndex,
                               over seen: Set<String>) -> [String: ScenicPoster.Claim] {
        Dictionary(uniqueKeysWithValues: seen.map {
            ($0, ScenicPoster.Claim(spotter: index.spotter($0), all: index.claimants($0)))
        })
    }

    /// The poster and the words that go with it, which is what a share actually is.
    ///
    /// Callers want both or neither, so they are built together rather than left for
    /// three call sites to remember to pair up.
    static func poster(for collection: any PlateCollection,
                       players: [Player]) async -> PosterToShare? {
        guard let image = await image(for: collection, players: players) else { return nil }
        let index = collection.plateIndex()
        return PosterToShare(
            image: image,
            caption: ShareInvite.line(for: collection.name,
                                      states: Plate.states.count { index.has($0.code) }))
    }

    static func poster(allTime book: PlateBook) -> PosterToShare? {
        guard let image = image(allTime: book) else { return nil }
        return PosterToShare(
            image: image,
            // No name to use — the lens is not a collection and has none — so the
            // sentence says what it is instead.
            caption: ShareInvite.line(for: String(localized: "Every plate so far"),
                                      states: Plate.states.count { book.foundCodes.contains($0.code) }))
    }

    /// The all-time lens, which is not a `PlateCollection` and never will be — you
    /// cannot collect into it, which is the whole distinction. It is still the most
    /// shareable thing in the app: everything anybody has ever spotted on this phone.
    ///
    /// No standings. A lifetime spans trips and books with different people on them,
    /// and a leaderboard drawn across all of it would be comparing somebody's one
    /// afternoon in the car against somebody else's four years.
    /// Books and the lifetime lens get no map. A book is not a journey — it has no
    /// two ends — which is the same reason `Book.route` is a single point rather
    /// than a line.
    static func image(allTime book: PlateBook) -> UIImage? {
        image(
            title: "All time",
            subtitle: book.firstEverSighting.map {
                "Since \($0.formatted(.dateTime.month(.abbreviated).year()))"
            },
            statesFound: Plate.states.count { book.foundCodes.contains($0.code) },
            // Scored against the national table, since a lifetime has no one route
            // to judge distance from.
            bestFind: rarestPlate(in: book.foundCodes) { PlateRarity.rarity($0, on: nil) },
            found: book.foundCodes,
            standings: [],
            // No standings here, so no chips either: the same rule as a solo trip.
            // A lifetime's claimants also span parties that never met.
            claims: [:],
            logged: book.totalSightings
        )
    }

    private static let everyPlate = Plate.states + Plate.bonus + Plate.provinces

    /// The road, when there is one to draw. Only a trip with both ends pinned has
    /// one — no places, no map, and the poster is simply shorter that day.
    private static func road(of collection: any PlateCollection) async -> PosterRoute? {
        guard let trip = collection as? Trip,
              let start = trip.originCoordinate,
              let end = trip.destinationCoordinate else { return nil }
        // Sized to land exactly inside the card that mounts it: the poster is 700
        // wide, the card stack is inset 16 a side, and the card pads the strip by 10.
        // Asked for here rather than measured there, because a snapshot has to be
        // ordered at a size before anything is laid out. See `ScenicPoster.mapCard`.
        //
        // These numbers have to be kept in step by hand, and the last time the page
        // margin moved they were not: the strip stayed 620 wide inside a slot that had
        // grown to 648, and MapKit's own scale bar and logo were being stretched 4%
        // across to fill it. Taller as well as wider — a road across a continent in a
        // 3.6:1 letterbox is mostly two oceans.
        return await PosterRoute.make(
            start: start, end: end,
            size: CGSize(width: ScenicPoster.width - 52, height: 200))
    }

    private static func image(title: String,
                              subtitle: String?,
                              statesFound: Int,
                              bestFind: (code: String, rarity: Int)?,
                              found: Set<String>,
                              standings: [(player: Player, score: Int)],
                              claims: [String: ScenicPoster.Claim],
                              logged: Int,
                              newHere: (count: Int, label: String)? = nil,
                              route: PosterRoute? = nil) -> UIImage? {
        let poster = ScenicPoster(title: title,
                                  subtitle: subtitle,
                                  statesFound: statesFound,
                                  bestFind: bestFind,
                                  plates: everyPlate,
                                  found: found,
                                  standings: standings,
                                  newHere: newHere,
                                  logged: logged,
                                  claims: claims,
                                  route: route)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        return renderer.uiImage
    }

    #if DEBUG
    /// `-poster` writes the current target's poster into Documents, which is the only
    /// way to look at the thing without a share sheet and a finger. Same code path as
    /// the real one — if this renders, so does what people send.
    static func exportForInspection() async -> String {
        let players = (try? PlatesStore.context.fetch(FetchDescriptor<Player>())) ?? []
        let started = Date()
        // `-poster alltime` covers the lens, which is not a collection and so takes
        // the other entry point entirely.
        let args = ProcessInfo.processInfo.arguments
        let wantsAllTime = LaunchFlags.value(after: "-poster") == "alltime"
        // `-poster scenic` used to render the draft here alongside the old album
        // page. The draft is the poster now, so there is one path again.
        let made: UIImage?
        if wantsAllTime {
            let all = (try? PlatesStore.context.fetch(FetchDescriptor<Sighting>())) ?? []
            made = image(allTime: PlateBook(sightings: all))
        } else {
            guard let target = PlatesStore.currentTarget() else { return "no target" }
            made = await image(for: target, players: players)
        }
        guard let image = made else { return "render failed" }
        let drew = Date().timeIntervalSince(started)
        guard let data = image.pngData() else { return "encode failed" }
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("poster.png")
        try? data.write(to: url)
        // Pixels, not points. `image.size` is points and the file is `scale` times
        // that, so reporting size alone reads as half the image it wrote.
        return String(format: "poster %dx%d px in %.0f ms -> %@",
                      Int(image.size.width * image.scale),
                      Int(image.size.height * image.scale), drew * 1000, url.path)
    }
    #endif

    /// The route if there was one, otherwise when it happened. A drive with no
    /// pinned places still has dates, and a poster with nothing under the name looks
    /// like it failed to load.
    private static func subtitle(for collection: any PlateCollection) -> String? {
        if let trip = collection as? Trip {
            if let route = trip.routeLabel { return route }
            let started = trip.startedAt.formatted(.dateTime.month(.abbreviated).day().year())
            guard let ended = trip.endedAt else { return "Since \(started)" }
            return "\(started) to \(ended.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return (collection as? Book)?.sinceLabel
    }
}
