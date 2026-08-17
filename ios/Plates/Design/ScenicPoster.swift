import SwiftUI
import UIKit

/// The shareable: a collection on open sky instead of on the app's paper.
///
/// This is what the share button sends. It replaced an album page — cream, with a
/// leather spine — which read beautifully as a page and disappeared completely in a
/// feed of photographs, which is where a poster actually goes. `ShareablePoster`
/// renders it; nothing else should build one.
///
/// The brief was a poster that pops rather than one that looks like a page out of the
/// album. So: a bright sky and the collection floating over it on cards. What it does
/// *not* borrow is a photograph. Sky and cloud here are shapes and gradients — the
/// output gets scaled into a Messages bubble and re-encoded by whatever app it lands
/// in, and a photographic backdrop is the first thing to fall apart. The one exception
/// is the route strip, which is a MapKit snapshot and is mounted on a card for exactly
/// that reason.
///
/// There was a forest along the bottom: four stands of firs receding into haze, and
/// the nicest drawing in the app. It is gone. At the size a poster is actually looked
/// at it was a dark green band under the cards competing with the only thing anybody
/// opens the image to read, and a backdrop that has to be scrolled past is not a
/// backdrop. Sky does the same job — it says *outdoors*, it stops a thumb in a feed —
/// and it does it without asking for a fifth of the image.
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

    /// How many of these were new to this phone, and what to call them.
    ///
    /// Nil for the all-time lens, where the question has no meaning: everything in a
    /// lifetime was new to it once. The label comes from the caller because only the
    /// caller knows whether this is a drive or a book.
    var newHere: (count: Int, label: String)?

    /// Every sighting filed, repeats included — the third stat on the strip.
    ///
    /// Deliberately not the same number as `statesFound`, and the gap between them is
    /// the point: fifty-odd logged against twenty-one found is a car that kept calling
    /// them out long after the map stopped changing.
    let logged: Int

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

    /// What one tile in the grid below actually measures: the poster's width, less the
    /// page margins, less the grid card's own padding, divided six ways with the gaps
    /// taken out. Written down because the rarest-find plate has to be drawn at this
    /// size and then scaled, and a guess here shows up as lettering of the wrong weight.
    private static let gridTile: CGFloat = (width - 32 - 32 - 40) / 6
    private static let rarestScale: CGFloat = 0.68

    // MARK: Scene colors
    //
    // Local, not in `Theme`. The app's palette is a paper palette — cream, navy,
    // amber — and it has no sky in it on purpose. Widening the whole theme for one
    // poster's backdrop would put a bright blue within reach of every screen that
    // should not have one.

    // The mock's sky is much paler than the one this started with. The saturated
    // 0x3EA8E5 was fine as a top band and wrong as a full-height field: with the
    // treeline gone it ran the whole left and right edge of the poster, and two
    // saturated verticals either side of a column of cream cards read as side bars
    // rather than as sky. Pale blue mounts the cards; strong blue frames them.
    private static let skyHigh = Color(hex: 0x86C9EE)
    private static let skyLow  = Color(hex: 0xD9EDFA)
    private static let cloudFill = Color(hex: 0xFFFFFF)

    /// The mock's accent for anything that means *new*, and near enough to the app's
    /// own found-green to belong to it.
    private static let fresh = Color(hex: 0x2FB574)

    private static let mapMount = Color(hex: 0xEAF5FD)
    private static let mapEdge  = Color(hex: 0xCFE4F3)

    /// The third stat label's accent, and the only color invented for this poster.
    ///
    /// `Theme.paint` is the app's amber and the obvious pick, and it fails the one test
    /// that matters here: amber on cream, at twelve points, tracked out, is a label you
    /// can see but not read. This is that same amber taken down until it holds against
    /// `Theme.ground`.
    private static let statAmber = Color(hex: 0xC07414)

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 12) {
                titleCard
                if let route { mapCard(route) }
                gridCard
                footer
                Spacer(minLength: 0)
            }
            // Sixteen points a side, down from thirty. The cards are the poster; the
            // sky is what they are mounted on, and a mount that wide had turned into
            // two blue stripes running the full height of the image.
            .padding(.horizontal, 16)
            // A band of sky above the first card, so the top of the poster is the
            // scene and not another cream edge. This is the one place the blue does
            // real work — in a feed, it is what stops the thumb.
            .padding(.top, 86)
            .padding(.bottom, 20)
        }
        .frame(width: Self.width)
        .background(Self.skyLow)
        .clipped()
    }

    // MARK: - The scene

    /// Sky and weather, and nothing else.
    ///
    /// One gradient, top to bottom, running the whole height of the poster. It is
    /// darkest where the clouds are and palest by the last card, which is the only
    /// depth cue left now the treeline has gone — and at a glance it is enough.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Self.skyHigh, Self.skyLow],
                           startPoint: .top, endPoint: .bottom)

            weather
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

                cloud(width: 230).offset(x: -196, y: 4)
                cloud(width: 160).offset(x: 128, y: 42)
                cloud(width: 104).offset(x: 272, y: -8)
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
        .foregroundStyle(Self.cloudFill.opacity(0.92))
    }

    // MARK: - Cards

    /// Name, road, score.
    ///
    /// Everything here used to be centred, and a stack of five centred lines has no
    /// shape — it reads as a certificate, and the eye has nowhere to enter. So: the
    /// name is ranged left and set large enough to be the first thing seen, and the
    /// numbers underneath split into two columns with a rule between them.
    ///
    /// The split is the whole of this card's structure. Stacked, the count and the
    /// rail were two full-width rows saying the same thing at different sizes; side by
    /// side they are a fraction and a picture of that fraction, and the card reads in
    /// one pass instead of three.
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.plates(size: 38, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.55)

            if let subtitle {
                Text(subtitle)
                    .font(.plates(size: 15))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }

            HStack(alignment: .center, spacing: 0) {
                // The headline number, and the only thing on the poster set this big.
                HStack(alignment: .center, spacing: 11) {
                    Text("\(statesFound)")
                        .font(Theme.PlateFont.condensed(76))
                        .monospacedDigit()
                        .foregroundStyle(Theme.route)

                    // Beside the number rather than under it. Stacked, the label was a
                    // caption and the pill under it a second caption, and the column got
                    // taller than the road it sits next to; set alongside, the three read
                    // as one statement and the two halves of the card are the same height.
                    VStack(alignment: .leading, spacing: 0) {
                        Text("OF \(Plate.stateTotal) STATES")
                            .font(Theme.PlateFont.condensed(15))
                            .tracking(1.5)
                            .foregroundStyle(Theme.inkMuted)

                        // The mock's green pill, and the one number on the poster that
                        // says something the big one cannot: how much of this was new.
                        // Twenty-one states on a drive is impressive until you learn that
                        // twenty of them were already in the book.
                        if let newHere, newHere.count > 0 {
                            HStack(spacing: 5) {
                                Text("+\(newHere.count)")
                                    .font(Theme.PlateFont.condensed(15))
                                    .monospacedDigit()
                                    .foregroundStyle(Self.fresh)
                                Text(newHere.label)
                                    .font(Theme.PlateFont.condensed(11))
                                    .tracking(1.1)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Self.fresh.opacity(0.13))
                                    .overlay(Capsule().strokeBorder(Self.fresh.opacity(0.34),
                                                                    lineWidth: 1))
                            )
                            .padding(.top, 7)
                        }
                    }
                }

                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1, height: 88)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(percentComplete)
                            .font(Theme.PlateFont.condensed(26))
                            .monospacedDigit()
                            .foregroundStyle(Self.fresh)
                        Text("COMPLETE")
                            .font(Theme.PlateFont.condensed(15))
                            .tracking(1.4)
                            .foregroundStyle(Theme.inkMuted)
                    }

                    road
                        .padding(.top, 4)

                    Text(remainingLine)
                        .font(.plates(size: 14, weight: .semibold))
                        .foregroundStyle(Self.fresh)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 16)

            // Inside the header rather than under it. Floating below, the three of them
            // were a fourth panel in a stack of panels and the poster had no hierarchy
            // left — every band the same weight, all the way down. Nested, the top of
            // the poster is one thing that says how the drive went, and the reader is
            // through it before the grid starts.
            statStrip
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .background(card())
    }

    /// The mock's road, drawn here rather than borrowed from the app.
    ///
    /// `RoadRail` was in this slot and is a better fit for a screen than for a poster:
    /// its marker is a bead, and the two things the mock's bar does — a car standing at
    /// the head of the fill, a pin over it saying how far that is — are exactly what a
    /// still image needs and a live screen does not. Teaching those to the shared
    /// component would put a labelled pin on every trip header in the app to serve one
    /// picture, so the poster draws its own.
    private var road: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let p = min(max(Double(statesFound) / Double(Plate.stateTotal), 0), 1)
            // The head is where the fill ends, and everything that rides on the road
            // hangs off it. Kept off both ends so the car and the pin stay inside the
            // column at 0% and at 50 of 50.
            let head = min(max(w * p, 22), w - 22)

            ZStack(alignment: .topLeading) {
                pin.offset(x: head - 26, y: 0)

                Capsule()
                    .fill(Theme.line)
                    .frame(width: w, height: 12)
                    .offset(y: 46)

                // Nothing at all at zero, rather than a minimum stub. A capsule floored
                // at twelve points is a circle, and a circle at the start of an empty
                // road with one dash inside it reads as a rendering fault — which is
                // exactly what the first poster of a fresh trip showed.
                if p > 0 {
                    Capsule()
                        .fill(Theme.route)
                        .frame(width: max(14, w * p), height: 12)
                        .offset(y: 46)
                }

                // Road paint, and only over the part that has been driven. Dashes the
                // whole length was the first attempt and it made the unfilled remainder
                // look like more road rather than like what is left. Below a couple of
                // states there is no room for even one dash, so none is drawn.
                if w * p > 34 {
                    Path { path in
                        path.move(to: CGPoint(x: 8, y: 52))
                        path.addLine(to: CGPoint(x: w * p - 8, y: 52))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [9, 9]))
                    .foregroundStyle(Theme.paint)
                }

                // The two ends of the scale, which is what turns a filled bar into a
                // fraction. Without them the road says "some of the way" and nothing else.
                Text(0.formatted())
                    .font(Theme.PlateFont.condensed(11))
                    .foregroundStyle(Theme.inkMuted)
                    .offset(x: 0, y: 60)
                Text(Plate.stateTotal.formatted())
                    .font(Theme.PlateFont.condensed(11))
                    .foregroundStyle(Theme.inkMuted)
                    .offset(x: w - 14, y: 60)

                // Facing the way the road runs. `car.side.fill` is drawn in profile
                // pointing left, so the flip actually turns it around; the plain
                // `car.fill` is a front view and mirroring it does nothing at all.
                Image(systemName: "car.side.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .scaleEffect(x: -1, y: 1)
                    .foregroundStyle(Theme.route)
                    .shadow(color: .white, radius: 2)
                    .shadow(color: .white, radius: 2)
                    .offset(x: head - 15, y: 30)
            }
        }
        .frame(height: 80)
    }

    private var pin: some View {
        VStack(spacing: 0) {
            Text(percentComplete)
                .font(Theme.PlateFont.condensed(14))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Self.fresh))
            PinTail()
                .fill(Self.fresh)
                .frame(width: 10, height: 6)
        }
        .frame(width: 52)
    }

    private struct PinTail: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }

    /// Already formatted, and formatted rather than built with a literal "%".
    ///
    /// `Text("\(n)%")` is a `LocalizedStringKey`, so it lands in the String Catalog as
    /// "%lld%%" for somebody to translate — and a percentage is not copy. This gets the
    /// locale's own numerals and its own placement of the sign for free.
    private var percentComplete: String {
        (Double(statesFound) / Double(Plate.stateTotal))
            .formatted(.percent.precision(.fractionLength(0)))
    }

    /// What is left, or the one line that only prints once.
    ///
    /// No exclamation mark and no encouragement at the halfway point. A poster is read
    /// by whoever it was sent to as often as by the person who made it, and cheering
    /// somebody else's car on is a strange thing for a picture to do.
    private var remainingLine: String {
        let left = Plate.stateTotal - statesFound
        return left <= 0
            ? String(localized: "All fifty found")
            : String(localized: "\(left) to go")
    }

    // MARK: - The stat strip
    //
    // Three small cards under the header, and three is the count on purpose: two look
    // like a mistake in a six-column poster and four leave nothing big enough to read
    // at thumbnail size.
    //
    // Every one of them is a fact this app already holds. The obvious fourth and fifth
    // — a streak, a "new this drive" — would each need a history the app does not
    // keep, and a poster is the last place to start estimating.

    private var statStrip: some View {
        HStack(spacing: 10) {
            rarestCard

            // The mock puts "new this drive" here as well as in the pill above, and
            // that is one place too many: the same count was then printed twice inside
            // one card and a third time in the closing line, so a poster of a good drive
            // spent three of its four statements on the same nineteen plates. The pill
            // keeps it — it is where the number qualifies the fraction it sits under —
            // and this slot goes to something nothing else on the poster says.
            statCard(label: String(localized: "BEYOND THE 50"),
                     accent: Theme.found,
                     value: "\(beyondFound)",
                     detail: String(localized: "of \(beyondTotal) outside the states"))

            statCard(label: String(localized: "PLATES LOGGED"),
                     accent: Self.statAmber,
                     value: "\(logged)",
                     detail: String(localized: "including repeats"))
        }
    }

    /// The one card nobody else's poster has. A headline of "21" is a score anybody
    /// can match by driving further; the rarest plate on the run is not.
    ///
    /// It carries the plate's own art rather than a symbol beside a word. That art is
    /// the thing the whole app is about, and at this size it is also the only picture
    /// in the strip — which is what stops three cream boxes reading as a table.
    @ViewBuilder
    private var rarestCard: some View {
        if let bestFind, let plate = Plate.plate(for: bestFind.code) {
            let tier = RarityTier.forRarity(bestFind.rarity)
            VStack(alignment: .leading, spacing: 0) {
                statLabel(String(localized: "RAREST FIND"), RarityTier.epic.color)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plate.short)
                            .font(.plates(size: 19, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(tier.label)
                            .font(Theme.PlateFont.condensed(12))
                            .tracking(1.1)
                            .foregroundStyle(tier.color)
                    }

                    Spacer(minLength: 4)

                    // `PlateLettering` sets its type at a fixed size rather than as a
                    // fraction of the tile, so a plate asked for at 62 points wide came
                    // out with full-size grid lettering on a two-thirds plate — the code
                    // filling it corner to corner. Drawn at the width the grid uses and
                    // scaled down as a whole, which is the only way to keep the
                    // proportions the artwork was drawn for.
                    PlateTile(plate: plate, isFound: true)
                        .frame(width: Self.gridTile)
                        .scaleEffect(Self.rarestScale)
                        .frame(width: Self.gridTile * Self.rarestScale,
                               height: Self.gridTile / Theme.tileAspect * Self.rarestScale)
                }
                .padding(.top, 8)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(innerCard())
        } else {
            // Nothing found yet, so nothing is the rarest. The strip keeps its three
            // columns rather than reflowing to two, because a poster of an empty
            // collection is still a poster and should be the same shape as a full one.
            statCard(label: String(localized: "RAREST FIND"),
                     accent: RarityTier.epic.color,
                     value: String(localized: "None yet"),
                     detail: String(localized: "the first one counts"))
        }
    }

    private func statCard(label: String, accent: Color,
                          value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statLabel(label, accent)
            Text(value)
                .font(Theme.PlateFont.condensed(34))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            Text(detail)
                .font(.plates(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(innerCard())
    }

    /// A card's heading, in its own color.
    ///
    /// Three different accents across three small cards is more color than this poster
    /// would otherwise spend, and it buys the row its structure: at thumbnail size the
    /// labels are what separate three cream boxes from a table with no rules in it.
    /// The values underneath stay ink so the color never competes with the number.
    private func statLabel(_ text: String, _ accent: Color) -> some View {
        Text(text)
            .font(Theme.PlateFont.condensed(12))
            .tracking(1.3)
            .foregroundStyle(accent)
    }

    /// Everything on the board that is not one of the fifty.
    private var beyondTotal: Int { plates.count - Plate.stateTotal }
    private var beyondFound: Int {
        plates.count { $0.region != .state && found.contains($0.code) }
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
        PosterMapStrip(route: route)
            .padding(10)
            .frame(maxWidth: .infinity)
            // Pale blue rather than cream, which is the mock's one departure from the
            // paper and worth copying: the snapshot is the only photograph on the
            // poster, and a cream mount put warm paper against green-and-blue map at
            // every edge. Sky against sky simply stops being a boundary.
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Self.mapMount)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Self.mapEdge, lineWidth: 1)
                    )
            )
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
                    let others = (claim?.all.count ?? 0) > 1 ? claim?.all ?? [] : []
                    // Exactly the test `PlateTile` uses to draw its chip, which is the
                    // point: this asks whether the corner is taken, and only the tile
                    // knows. Asking `claim == nil` instead — which is what stood here —
                    // is a different question with the same answer most of the time.
                    // A claim with no spotter is an ordinary thing: every sighting
                    // logged before anybody made a player has one, and so does every
                    // plate pulled in from a shared book whose owner is not on this
                    // phone. Those tiles drew no chip, because there is nobody to draw,
                    // *and* no tick, because there was a claim. A found plate with
                    // nothing on it at all, on the one artifact whose whole job is
                    // showing what was found.
                    let cornerTaken = others.count > 1 || claim?.spotter != nil
                    PlateTile(
                        plate: plate,
                        isFound: true,
                        spotter: claim?.spotter,
                        claimants: others)
                    // A tick in the corner, but only where the corner is free.
                    //
                    // On a shared collection that corner already carries the spotter's
                    // chip, which says *found* and also says by whom — a check beside it
                    // would be the same fact twice, in the same 14 points of tile. Solo,
                    // there are no chips at all, and the grid was relying entirely on
                    // colored artwork against grey slots to show what had been caught.
                    .overlay(alignment: .topLeading) {
                        if !cornerTaken { foundTick.padding(3) }
                    }
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
        .background(card())
    }

    /// The green tick a found tile wears when nobody's chip is on it.
    ///
    /// White ring around the disc, because the artwork underneath is not one color: the
    /// same green sits on a pale Iowa sky and on a near-black Wyoming, and without the
    /// ring it disappears into one of them.
    private var foundTick: some View {
        Circle()
            .fill(Theme.found)
            .frame(width: 15, height: 15)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
            )
    }

    private var spotters: some View {
        HStack(spacing: 16) {
            ForEach(Array(standings.enumerated()), id: \.element.player.id) { index, entry in
                HStack(spacing: 7) {
                    // Keeps its own type size. The poster is drawn at a fixed
                    // scale into an image, so it has no overflow to fix — only a
                    // look to hold still.
                    PlayerDot(entry.player, size: 22,
                              glyphSize: entry.player.usesEmoji ? 12 : 13)
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
    }

    /// The mock's closing line, without the mock's button.
    ///
    /// A button on a poster is a button that cannot be pressed: this is a flat image
    /// that lands in Messages, in a feed, in somebody's camera roll, and nothing drawn
    /// in it is tappable anywhere it goes. The sentence is the part that survives being
    /// an image, so it is the part that stayed.
    /// The scores, when there are scores.
    ///
    /// The mock closes on a sentence and this does not, because every sentence worth
    /// putting there was a restatement: "19 plates here for the first time" is the pill,
    /// "21 of 50 states on the board" is the headline. A poster that ends by repeating
    /// its own opening line is padding, and a solo one now simply ends at the grid.
    @ViewBuilder
    private var footer: some View {
        if standings.count > 1 {
            spotters.background(card())
        }
    }

    /// The cream page every panel is printed on. Flat, and that is the point.
    ///
    /// There was a soft drop shadow under each of these, and four of them stacked read
    /// as four beveled slabs floating at different heights — the poster looked assembled
    /// rather than printed. A hairline does the whole job of saying *this is a panel*
    /// without pretending the image has depth it cannot have.
    private func card(_ radius: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.ground)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }

    /// The lighter panel a stat sits on, inside the cream one.
    ///
    /// White rather than more cream: nested on the same color, the three of them needed
    /// their borders to do all the separating, and a hairline is not enough contrast to
    /// carve three boxes out of one field.
    private func innerCard(_ radius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }

    // There was a footer band here — a route-blue strip with the wordmark across it.
    // It is gone deliberately, and the poster now carries no name of its own. What
    // that costs: an image that gets saved and re-posted somewhere else says nothing
    // about where it came from. The link and the sentence ride along as the share
    // sheet's second item (see `ShareInvite`), so a poster sent from the app is
    // still attributed; one screenshotted out of a feed is not.
}
