import SwiftUI
import UIKit

/// The shareable: a collection on a drawn landscape instead of on the app's paper.
///
/// This is what the share button sends. It replaced an album page — cream, with a
/// leather spine — which read beautifully as a page and disappeared completely in a
/// feed of photographs, which is where a poster actually goes. `ShareablePoster`
/// renders it; nothing else should build one.
///
/// The brief was a poster that pops rather than one that looks like a page out of the
/// album. So: a bright sky, a treeline, and the collection floating over it on cards.
/// What it does *not* borrow is a photograph. Every part of this scene is shapes and
/// gradients — the output gets scaled into a Messages bubble and re-encoded by
/// whatever app it lands in, and a photographic backdrop is the first thing to fall
/// apart. The one exception is the route strip, which is a MapKit snapshot and is
/// mounted on a card for exactly that reason. It also keeps the poster honest about
/// being from this app: cream, navy and amber survive the change of background, and
/// a stock forest would not.
///
/// The poster carries no wordmark. There was a route-blue footer band with one across
/// it; it is gone, and what replaces it is the sentence and link that travel beside
/// the image in the share sheet — see `ShareInvite`. The trade is real: a poster sent
/// from the app is attributed, one screenshotted out of a feed is not.
struct ScenicPoster: View {

    let title: String
    let subtitle: String?
    let statesFound: Int
    let bestFind: (code: String, rarity: Int)?
    let plates: [Plate]
    let found: Set<String>
    let standings: [(player: Player, score: Int)]

    /// Who banked each plate, keyed by code.
    ///
    /// Empty when one person is playing, and the tiles then wear no chips at all —
    /// the same rule the Game screen's grid follows. A chip on all fifty tiles
    /// naming the only player is not information, it is a texture.
    var claims: [String: Claim] = [:]

    /// The two facts a tile needs about a plate's owners, which are not the same
    /// fact: `spotter` is who called it *last* and drives the single chip, `all` is
    /// everyone who has banked it and drives the stack. They only coincide when
    /// exactly one person claimed it.
    struct Claim {
        let spotter: Player?
        let all: [Player]
    }

    /// The trip's road, already snapshotted. Nil for a book, for a trip with no places
    /// pinned, and whenever MapKit declined to answer — all three are normal, and the
    /// poster simply has no map that day. Handed in finished because `ImageRenderer`
    /// waits for nothing async; see `PosterRoute`.
    var route: PosterRoute?

    static let width: CGFloat = 700
    private let columns = 6

    // MARK: Scene colours
    //
    // Local, not in `Theme`. The app's palette is a paper palette — cream, navy,
    // amber — and it has no sky in it on purpose. Widening the whole theme for one
    // poster's backdrop would put a bright blue within reach of every screen that
    // should not have one.

    private static let skyHigh   = Color(hex: 0x3EA8E5)
    private static let skyLow    = Color(hex: 0xBFE6F7)
    private static let ridgeHaze = Color(hex: 0xA8CFCB)
    private static let ridgeFar  = Color(hex: 0x74AE9E)
    private static let ridgeMid  = Color(hex: 0x3E8C6E)
    private static let ridgeNear = Color(hex: 0x1F5F4B)

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 16) {
                titleCard
                if let route { mapCard(route) }
                gridCard
                if standings.count > 1 { spotters }
                Spacer(minLength: 0)
            }
            // A band of sky above the first card, so the top of the poster is the
            // scene and not another cream edge. This is where the colour does its
            // job — in a feed, the blue is what stops the thumb.
            .padding(.horizontal, 30)
            .padding(.top, 92)
            // Enough to leave the near stand of trees standing clear below the last
            // card. There was a footer band here; the poster now ends in the scene.
            // Just enough for the near crowns and a strip of floor under them. Most
            // of what this used to be was flat green — the forest is a base for the
            // cards, not a subject, and a poster that ends promptly reads better in a
            // feed than one with a field at the bottom of it.
            .padding(.bottom, 84)
        }
        .frame(width: Self.width)
        .background(Self.skyLow)
    }

    // MARK: - The scene

    /// Sky, sun, three ridges of trees. Drawn back to front, each row lighter and
    /// higher than the one in front of it, which is the whole trick that reads as
    /// distance without a single photograph.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Self.skyHigh, Self.skyLow],
                           startPoint: .top, endPoint: .bottom)

            weather

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // Four stands, each shifted sideways as well as up. Aligned on the
                // same x they stack into stripes and the whole thing reads as a
                // pattern rather than as depth — which is what the first pass did.
                //
                // The haze between the back two is the difference between four rows
                // of trees and a distance. Air is not clear: the further something
                // is, the more sky is stacked in front of it, so it loses contrast
                // towards the sky's own colour. One gradient does the whole job.
                ZStack(alignment: .bottom) {
                    Forest(count: 19, seed: 23, shortest: 0.22)
                        .fill(Self.ridgeHaze)
                        .frame(height: 270)
                        .offset(x: 14, y: -168)
                    Forest(count: 15, seed: 3, shortest: 0.30)
                        .fill(Self.ridgeFar)
                        .frame(height: 300)
                        .offset(x: -22, y: -112)

                    LinearGradient(colors: [Self.skyLow.opacity(0.55),
                                            Self.skyLow.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 300)
                        .offset(y: -80)
                        .allowsHitTesting(false)

                    Forest(count: 12, seed: 19, shortest: 0.38)
                        .fill(Self.ridgeMid)
                        .frame(height: 345)
                        .offset(x: 31, y: -56)
                    // The nearest stand is also the poster's bottom edge, and it has
                    // to hold that on its own now the footer band is gone. Denser
                    // than the others and standing on a deep floor: with ten wide
                    // trees on a shallow one, the gaps between them ran all the way
                    // down and the eye read the pale wedges *between* the trees as
                    // the shapes — a row of arrows pointing at the ground.
                    Forest(count: 14, seed: 7, shortest: 0.44, ground: 0.13)
                        .fill(Self.ridgeNear)
                        .frame(height: 340)
                        .offset(x: -9)
                }
            }
        }
    }

    /// Sun and cloud, pinned to the top band where the sky is actually visible.
    ///
    /// Both were centred in the poster to begin with, which put them behind the
    /// cards — a sun nobody can see is just a slower render.
    private var weather: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.9), .white.opacity(0)],
                        center: .center, startRadius: 6, endRadius: 170))
                    .frame(width: 340, height: 340)
                    .offset(x: 232, y: -40)

                cloud(width: 210).offset(x: -190, y: 6)
                cloud(width: 150).offset(x: 120, y: 40)
                cloud(width: 96).offset(x: 265, y: -6)
            }
            .frame(height: 120)
            Spacer(minLength: 0)
        }
    }

    private func cloud(width: CGFloat) -> some View {
        let unit = width / 3.4
        return ZStack {
            Capsule().frame(width: width, height: unit * 0.92)
            Circle().frame(width: unit * 1.5).offset(x: -unit * 0.55, y: -unit * 0.42)
            Circle().frame(width: unit * 1.15).offset(x: unit * 0.7, y: -unit * 0.34)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    /// A stand of firs, as one path.
    ///
    /// Each tree is three stacked tiers rather than a single triangle. That is the
    /// whole difference between a forest and a row of grass: the first attempt drew
    /// one spike per tree, and at poster size it read as a lawn somebody had mown
    /// badly.
    ///
    /// Deterministic variation from the seed rather than `random`, so two shares of
    /// the same trip are the same picture — a backdrop that reshuffled itself every
    /// render would make one drive look like two.
    private struct Forest: Shape {
        let count: Int
        let seed: Int
        /// The shortest tree as a fraction of the band, so a row never flattens out.
        let shortest: CGFloat
        /// How much of the band is forest floor. Shallow for the distant stands: at a
        /// third they stopped being a floor and became a green wall with a few trees
        /// on top. Deep for the nearest one, which is the poster's own bottom edge —
        /// see the call site.
        var ground: CGFloat = 0.13

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let step = rect.width / CGFloat(count - 1)

            // The ground they stand on. Without it the trunks end in mid-air the
            // moment two neighbours do not overlap.
            path.addRect(CGRect(x: rect.minX - step, y: rect.maxY - rect.height * ground,
                                width: rect.width + step * 2, height: rect.height * ground))

            // One tree past each end, drawn outside the rect. Each stand is offset
            // sideways from the others, and without the overhang that offset opens a
            // wedge of sky at one edge — which is exactly what it did.
            for index in -1...(count + 1) {
                let n = Double(index) + Double(seed)
                // Three out-of-phase sines. Two was not enough variation: at this
                // width the row found a rhythm and the eye read the repeat.
                let wobble = (sin(n * 1.9) + 0.6 * sin(n * 0.73 + 1.3)
                              + 0.35 * sin(n * 3.1 + 0.4)) / 1.95
                let height = rect.height * (shortest + (1 - shortest) * CGFloat(wobble + 1) / 2)
                let width = step * (1.15 + 0.25 * CGFloat(sin(n * 2.7)))
                let x = rect.minX + CGFloat(index) * step
                // Planted just inside the ground band, so the trunks overlap it
                // rather than balancing on its edge.
                let base = rect.maxY - rect.height * ground * 0.7

                // Three tiers, each narrower and starting higher than the one below.
                for tier in 0..<3 {
                    let t = CGFloat(tier)
                    let tierBase = base - height * (0.22 * t)
                    let tierWidth = width * (1 - 0.22 * t)
                    let tierTop = base - height * (0.42 + 0.29 * t)
                    path.move(to: CGPoint(x: x - tierWidth / 2, y: tierBase))
                    path.addLine(to: CGPoint(x: x, y: tierTop))
                    path.addLine(to: CGPoint(x: x + tierWidth / 2, y: tierBase))
                    path.closeSubpath()
                }
            }
            return path
        }
    }

    // MARK: - Cards

    /// Name, road, score.
    ///
    /// Everything here used to be centred, and a stack of five centred lines has no
    /// shape — it reads as a certificate, and the eye has nowhere to enter. So: the
    /// name is ranged left and set large enough to be the first thing seen, the rail
    /// runs the full width of the card, and the score row uses both ends. Three
    /// different alignments in one card is what gives it a structure rather than a
    /// spine.
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.plates(size: 38, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 22)

            if let subtitle {
                Text(subtitle)
                    .font(.plates(size: 14))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 22)
                    .padding(.top, 3)
            }

            // The full-width element, and the app's own idiom rather than a
            // decorative rule: this is the same rail the Game screen puts under a
            // trip. Inset a little from the card's edges because the mile-marker rides
            // *on* the rail — at 50 of 50 a flush rail would push it under the corner.
            RoadRail(progress: Double(statesFound) / Double(Plate.stateTotal))
                .padding(.horizontal, 18)
                .padding(.top, 14)

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(statesFound)")
                        .font(Theme.PlateFont.condensed(46))
                        .monospacedDigit()
                        .foregroundStyle(Theme.route)
                    Text("OF \(Plate.stateTotal) STATES")
                        .font(Theme.PlateFont.condensed(16))
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)

                // The other end of the row, and the one thing on this poster nobody
                // else's has — a headline of "21" is a score anybody can match by
                // driving further.
                //
                // Dark capsule, coloured code. Filling the capsule with the rarity
                // colour was the obvious move and the wrong one: the top tier is
                // amber, and white on amber is barely text. On ink the same colour is
                // the brightest thing in the card.
                if let bestFind, let plate = Plate.plate(for: bestFind.code) {
                    HStack(spacing: 7) {
                        Text("RAREST")
                            .font(Theme.PlateFont.condensed(11))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.65))
                        Text(plate.code)
                            .font(Theme.PlateFont.condensed(18))
                            .foregroundStyle(RarityTier.forRarity(bestFind.rarity).color)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.ink))
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(card)
    }

    /// The road, on the same cream card as everything else.
    ///
    /// A MapKit snapshot is the one photograph on a poster that is otherwise entirely
    /// drawn, which is why it is mounted rather than laid onto the sky: inside a card
    /// it reads as a picture pasted into an album, and floating on the gradient it
    /// read as a rendering fault. The strip brings its own hairline and corners, so
    /// the card only has to hold it.
    ///
    /// Its width is fixed at render time by whoever asked for the snapshot — see
    /// `ShareablePoster.road(of:)`, which sizes it to fit exactly this inset.
    private func mapCard(_ route: PosterRoute) -> some View {
        PosterMapStrip(route: route, startLabel: nil, endLabel: nil)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(card)
    }

    private var gridCard: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
            spacing: 8
        ) {
            ForEach(plates) { plate in
                if found.contains(plate.code) {
                    // The chips are the reason the standings card below is worth
                    // reading. "Mia 56" on its own is a number somebody has to take
                    // on trust; with the grid marked up it is a claim you can check,
                    // and the poster stops being a scoreboard and starts being a
                    // record of who caught what.
                    let claim = claims[plate.code]
                    PlateTile(
                        plate: plate,
                        isFound: true,
                        spotterColor: claim?.spotter.map { Theme.playerColor($0.colorIndex) },
                        spotterInitial: claim?.spotter?.smallFace,
                        spotterIsEmoji: claim?.spotter?.usesEmoji ?? false,
                        claimants: (claim?.all.count ?? 0) > 1 ? claim?.all ?? [] : [])
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
        .padding(16)
        .background(card)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(card)
    }

    /// The cream page every panel is printed on, with the shadow that lifts it off
    /// the sky. The one real shadow here — the plates inside carry their own.
    private var card: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Theme.ground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Theme.ink.opacity(0.22), radius: 14, y: 6)
    }

    // There was a footer band here — a route-blue strip with the wordmark across it.
    // It is gone deliberately, and the poster now carries no name of its own. What
    // that costs: an image that gets saved and re-posted somewhere else says nothing
    // about where it came from. The link and the sentence ride along as the share
    // sheet's second item (see `ShareInvite`), so a poster sent from the app is
    // still attributed; one screenshotted out of a feed is not.
}
