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
    let statesFound: Int
    let platesFound: Int
    /// Every plate worth drawing, in the order the app draws them.
    let plates: [Plate]
    let found: Set<String>
    /// Who spotted what, for the strip along the bottom. Empty for a solo trip or a
    /// book nobody shares, which is most of them — and the strip disappears rather
    /// than showing one person beating nobody.
    let standings: [(player: Player, score: Int)]

    /// Wide enough that a 10-across grid of plates is legible when Messages shrinks
    /// it into a bubble.
    static let width: CGFloat = 700

    private let columns = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
            if standings.count > 1 { spotters }
            footer
        }
        .frame(width: Self.width)
        .background(Theme.ground)
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

            HStack(spacing: 22) {
                stat("\(statesFound)", "of 50 states")
                stat("\(platesFound)", platesFound == 1 ? "plate" : "plates")
            }
            .padding(.top, 10)
        }
        .padding(.top, 34)
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Theme.PlateFont.condensed(44))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.plates(size: 12))
                .foregroundStyle(Theme.inkMuted)
        }
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
    static func image(for collection: any PlateCollection,
                      players: [Player]) -> UIImage? {
        let index = collection.plateIndex()
        let people = collection.participants(from: players,
                                             me: DevicePlayer.resolve(from: players))
        return image(
            title: collection.name,
            subtitle: subtitle(for: collection),
            statesFound: collection.statesFound,
            platesFound: collection.platesFound,
            found: Set(everyPlate.map(\.code).filter { index.has($0) }),
            // Only worth drawing when more than one person is on it. A book filled
            // alone and a trip driven alone both get the collection and nothing else.
            standings: people.count > 1 ? collection.standings(among: people) : []
        )
    }

    /// The all-time lens, which is not a `PlateCollection` and never will be — you
    /// cannot collect into it, which is the whole distinction. It is still the most
    /// shareable thing in the app: everything anybody has ever spotted on this phone.
    ///
    /// No standings. A lifetime spans trips and books with different people on them,
    /// and a leaderboard drawn across all of it would be comparing somebody's one
    /// afternoon in the car against somebody else's four years.
    static func image(allTime book: PlateBook) -> UIImage? {
        image(
            title: "All time",
            subtitle: book.firstEverSighting.map {
                "Since \($0.formatted(.dateTime.month(.abbreviated).year()))"
            },
            statesFound: book.statesFound,
            platesFound: book.totalFound,
            found: book.foundCodes,
            standings: []
        )
    }

    private static let everyPlate = Plate.states + Plate.bonus + Plate.provinces

    private static func image(title: String,
                              subtitle: String?,
                              statesFound: Int,
                              platesFound: Int,
                              found: Set<String>,
                              standings: [(player: Player, score: Int)]) -> UIImage? {
        let poster = SharePoster(title: title,
                                 subtitle: subtitle,
                                 statesFound: statesFound,
                                 platesFound: platesFound,
                                 plates: everyPlate,
                                 found: found,
                                 standings: standings)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 2
        return renderer.uiImage
    }

    #if DEBUG
    /// `-poster` writes the current target's poster into Documents, which is the only
    /// way to look at the thing without a share sheet and a finger. Same code path as
    /// the real one — if this renders, so does what people send.
    static func exportForInspection() -> String {
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
            made = image(for: target, players: players)
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
