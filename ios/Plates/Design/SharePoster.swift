import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// The one-pager you text somebody at the end of a drive.
///
/// A collection is only worth having if it can be shown to somebody, and until now
/// the only way to show this one was to hand over the phone. This renders a trip or
/// a book to a single image: the name at the top, what it came to, and the plates
/// themselves as the picture.
///
/// Empty slots are drawn, not omitted. A grid of only the plates you found looks the
/// same whether you got nine or forty-nine — the gaps are what make the count mean
/// something, and they are the same debossed pressings the Book tab uses, so the
/// image looks like the app rather than like a report about it.
///
/// Laid out in points at a fixed width and rendered at `scale`, so the output is a
/// predictable size whatever phone it came from. Nothing here reads the environment:
/// an `ImageRenderer` draws outside the view hierarchy and gets no `@Environment`,
/// no safe area and no colour scheme, so everything it needs is passed in.
struct SharePoster: View {

    let title: String
    /// The line under the name — a route, or how long a book has been going.
    let subtitle: String?
    /// The rarest thing on it, which is the one number nobody else's poster will
    /// have. Nil when nothing has been collected yet.
    let bestFind: (code: String, rarity: Int)?
    /// Every plate worth drawing, in the order the app draws them.
    let plates: [Plate]
    let found: Set<String>
    /// Who spotted what, for the strip along the bottom. Empty for a solo trip or a
    /// book nobody shares, which is most of them — and the strip disappears rather
    /// than showing one person beating nobody.
    let standings: [(player: Player, score: Int)]
    /// The trip's road, already snapshotted. Nil for a book, for a trip with no
    /// places pinned, and whenever MapKit declined to answer — all three are normal,
    /// and the poster simply has no map that day.
    var route: PosterRoute?

    /// Wide enough that a 10-across grid of plates is legible when Messages shrinks
    /// it into a bubble.
    static let width: CGFloat = 700

    private let columns = 6

    // Counted here, from the very set the grid below draws, so a number in the
    // header cannot disagree with the plates under it.
    //
    // This is not theoretical. The first version asked the collection for
    // `bonusFound`, which is `region != .state` — and that includes the Canadian
    // provinces, so a trip with two Ontario plates reported "2 bonus" and "2 Canada"
    // about the same two plates, while the all-time poster counting the `Plate.bonus`
    // catalogue said 0. Two definitions of one word, disagreeing in the same row.
    private var statesFound: Int { count(Plate.states) }
    private var bonusFound: Int { count(Plate.bonus) }
    private var provincesFound: Int { count(Plate.provinces) }

    private func count(_ region: [Plate]) -> Int {
        region.filter { found.contains($0.code) }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            spine
            VStack(spacing: 0) {
                header
                if let route {
                    PosterMapStrip(route: route, startLabel: nil, endLabel: nil)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 22)
                }
                grid
                if standings.count > 1 { spotters }
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.width)
        .background(Theme.ground)
    }

    /// Bookbinder's tan. Local to the poster rather than added to `Theme`, because
    /// the palette has no brown on purpose — it is cream, navy and amber — and one
    /// decorative edge is not a reason to widen it. The first version used
    /// `Theme.route`, and a navy spine on a cream page read as a UI element that had
    /// wandered in rather than as a binding.
    private static let leather = Color(hex: 0x9A6B3F)

    /// The bound edge, so the page is a page out of something.
    ///
    /// A trip gets one as well as a book. The app's whole idea of a collection is an
    /// album — debossed slots, mounted plates, a shelf you fill — and a trip's plates
    /// end up in exactly that album, so a poster that looked like a loose sheet was
    /// the one place the metaphor stopped. It costs nothing to carry it through.
    ///
    /// Drawn rather than shaded from an image: three bands and a gradient are enough
    /// for the eye to read "spine", and the whole thing survives being scaled into a
    /// Messages bubble, which a photographic texture would not.
    private var spine: some View {
        ZStack {
            // Rolled rather than flat: dark at the outer edge where the cover turns
            // away, catching the light across the curve, darkening again into the
            // crease. Four stops is the fewest that reads as round instead of
            // striped, and they sit close together — a spine is one material
            // catching light, not a set of stripes.
            //
            // The dark end is on the left because the spine is on the left. This is
            // the front of a book, and a front cover's binding is on the hand you
            // hold it by.
            LinearGradient(
                colors: [Self.leather.opacity(0.44), Self.leather.opacity(0.31),
                         Self.leather.opacity(0.24), Self.leather.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing)

            // The shadow the page casts into the gutter. On the inner edge — the one
            // against the page — which is the side the light cannot reach.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, Theme.ink.opacity(0.16)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 12)
            }

            // Binding bands, the way a hardback is stitched. Light on dark, so they
            // read as raised cord under the cloth rather than as gaps in it.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(Theme.ground.opacity(0.34))
                        .frame(height: 10)
                    if index < 2 { Spacer().frame(height: 52) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: 34)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.plates(size: 34, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(.plates(size: 15))
                    .foregroundStyle(Theme.inkMuted)
            }

            HStack(alignment: .top, spacing: 0) {
                stat("\(statesFound)", "of 50 states")
                divider
                stat("\(bonusFound)", "bonus")
                divider
                stat("\(provincesFound)", "Canada")
                if let bestFind, let plate = Plate.plate(for: bestFind.code) {
                    divider
                    stat(plate.code, "rarest",
                         tint: RarityTier.forRarity(bestFind.rarity).color)
                }
            }
            .padding(.top, 12)
        }
        .padding(.top, 34)
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
    }

    private func stat(_ value: String, _ label: String,
                      tint: Color = Theme.ink) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Theme.PlateFont.condensed(40))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.plates(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    /// A hairline between the numbers rather than spacing alone. Four figures set in
    /// the same face, side by side and evenly spaced, read as one long number.
    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 34)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(plates) { plate in
                if found.contains(plate.code) {
                    PlateTile(plate: plate, isFound: true)
                } else {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .fill(Theme.slot)
                        .aspectRatio(Theme.tileAspect, contentMode: .fit)
                        .overlay(
                            Text(plate.code)
                                .font(Theme.PlateFont.condensed(19))
                                .foregroundStyle(Theme.ink.opacity(0.22))
                        )
                }
            }
        }
        .padding(.horizontal, 30)
    }

    private var spotters: some View {
        HStack(spacing: 16) {
            ForEach(Array(standings.enumerated()), id: \.element.player.id) { index, entry in
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.playerColor(entry.player.colorIndex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Text(entry.player.face)
                                .font(entry.player.usesEmoji
                                      ? .system(size: 12)
                                      : Theme.PlateFont.condensed(13))
                                .foregroundStyle(Theme.ink)
                        )
                    Text(entry.player.name)
                        .font(.plates(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(entry.score)")
                        .font(Theme.PlateFont.condensed(18))
                        .monospacedDigit()
                        .foregroundStyle(index == 0 ? Theme.route : Theme.inkMuted)
                }
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 30)
    }

    private var footer: some View {
        Text("PLATES")
            .font(Theme.PlateFont.condensed(16))
            .tracking(4)
            .foregroundStyle(Theme.inkMuted.opacity(0.8))
            .padding(.top, 26)
            .padding(.bottom, 28)
    }
}

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
        return image(
            title: collection.name,
            subtitle: subtitle(for: collection),
            bestFind: rarest(in: seen, scoredBy: collection.rarity(of:)),
            found: seen,
            // Only worth drawing when more than one person is on it. A book filled
            // alone and a trip driven alone both get the collection and nothing else.
            standings: people.count > 1 ? collection.standings(among: people) : [],
            route: await road(of: collection)
        )
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
            // Scored against the national table, since a lifetime has no one route
            // to judge distance from.
            bestFind: rarest(in: book.foundCodes) { PlateRarity.rarity($0, on: nil) },
            found: book.foundCodes,
            standings: []
        )
    }

    private static let everyPlate = Plate.states + Plate.bonus + Plate.provinces

    /// The rarest plate on it, by whatever rarity the caller judges with — a trip
    /// scores against its own route, a lifetime against the national table.
    private static func rarest(in found: Set<String>,
                               scoredBy rarity: (String) -> Int) -> (code: String, rarity: Int)? {
        found.map { (code: $0, rarity: rarity($0)) }
            // Ties broken by code so two runs of the same collection cannot disagree
            // about which plate was the best one.
            .max { ($0.rarity, $1.code) < ($1.rarity, $0.code) }
    }

    /// The road, when there is one to draw. Only a trip with both ends pinned has
    /// one — no places, no map, and the poster is simply shorter that day.
    private static func road(of collection: any PlateCollection) async -> PosterRoute? {
        guard let trip = collection as? Trip,
              let start = trip.originCoordinate,
              let end = trip.destinationCoordinate else { return nil }
        return await PosterRoute.make(
            start: start, end: end,
            size: CGSize(width: SharePoster.width - 60, height: 190))
    }

    private static func image(title: String,
                              subtitle: String?,
                              bestFind: (code: String, rarity: Int)?,
                              found: Set<String>,
                              standings: [(player: Player, score: Int)],
                              route: PosterRoute? = nil) -> UIImage? {
        let poster = SharePoster(title: title,
                                 subtitle: subtitle,
                                 bestFind: bestFind,
                                 plates: everyPlate,
                                 found: found,
                                 standings: standings,
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
        let wantsAllTime = args.firstIndex(of: "-poster")
            .map { $0 + 1 < args.count && args[$0 + 1] == "alltime" } ?? false
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
            return "\(started) \u{2013} \(ended.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return (collection as? Book)?.sinceLabel
    }
}
