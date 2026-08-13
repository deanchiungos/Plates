import SwiftUI

/// The reference page: everything the app does, written down once.
///
/// The third and last layer of the onboarding, and the only one that is *pull*
/// rather than push. The welcome card interrupts you once; the coach marks speak up
/// when a control is in front of you and never again. Both are deliberately thin,
/// and both are allowed to be thin only because this page exists — a tip that goes
/// unread is not lost information if there is somewhere to go and look it up.
///
/// So this is where anything that would otherwise grow as an explanatory footer on
/// a working screen belongs. The trips list used to carry a sentence about the
/// swipe gesture, Settings used to carry the Siri phrases; both are here now, and
/// the screens they came from are shorter for it.
///
/// **No screenshots, but pictures.** A captured screenshot of an app inside the app
/// rots the first time a control moves, and the rot is invisible — nothing fails to
/// compile, the page just quietly starts lying. So every drawing on this page is
/// built from the app's own live vocabulary instead: real `PlateTile`s with real
/// artwork, the actual tab-bar symbols, `RarityTier`'s actual colours. A picture
/// here cannot disagree with the app, because it *is* the app — restyle a tile and
/// this page restyles with it.
///
/// They are decoration and they know it: every one is `accessibilityHidden`, and
/// each section reads correctly with the pictures removed. Somebody scrolling for an
/// answer navigates by them; somebody reading top to bottom is not required to.
struct HowToPlayScreen: View {
    @Environment(CoachPresenter.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    game
                    tripsAndBooks
                    folding
                    rarity
                    mapAndTrail
                    together
                    handsFree
                    widgetAndLookup
                    replay
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("How to play")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The sections

    private var game: some View {
        SettingsGroup("The game") {
            Illustration { Art.tiles }
            Paragraph("Spot a plate through the window, then tap it on the Game tab. The tile turns over to that state's artwork and the plate is yours for this trip.")
            Paragraph("How it scores depends on the trip. Classic gives a point a state, however many times you see it. Weighted gives more for plates from far away. Unlimited counts every single sighting, so the same state can keep earning \u{2014} hold a plate there to take a count back.")
        }
    }

    private var tripsAndBooks: some View {
        SettingsGroup("Trips and books") {
            Illustration { Art.tripAndBook }
            Paragraph("A trip is one drive. It has a route, it has a finish, and its score is about that journey. A book never ends \u{2014} it is the one you keep in the car and fill over years.")
            Paragraph("Make either from its own tab, and use SWITCH at the top of the Game tab to choose which one your taps go into.")
            Paragraph("Swipe a trip left in the list to pin it to the top, or to mark it done. A finished trip stops collecting and files itself under Finished, where you can open it for its map and its story. Reopen it whenever you like.")
        }
    }

    private var folding: some View {
        SettingsGroup("Adding a trip to a book") {
            Illustration { Art.fold }
            Paragraph("Open a finished trip and choose Add to book. Stack everything, and every sighting carries over; fill the gaps, and only the plates the book is missing do.")
            Paragraph("The trip keeps its own plates either way \u{2014} the book is showing them, not taking them. Take them back out whenever you like.")
        }
    }

    private var rarity: some View {
        SettingsGroup("Rarity") {
            Illustration { Art.rarityRamp }
            Paragraph("Every plate is scored from common to legendary against where you are driving, using how many of that state's cars are actually on the road. A New Jersey plate is nothing in Newark and a banner in Sacramento.")
            Paragraph("A plate keeps the value it had when you called it. Driving on afterwards never quietly rewrites what a find was worth.")
        }
    }

    private var mapAndTrail: some View {
        SettingsGroup("The Map and the Trail") {
            Illustration { Art.mapAndTrail }
            Paragraph("The Map answers which states you have collected. The Trail answers where you were when you collected them \u{2014} it needs location, which the Game tab offers to turn on.")
        }
    }

    private var together: some View {
        SettingsGroup("Playing together") {
            Illustration { Art.together }
            Paragraph("A party is for one car. Everybody opens Plates, one person starts it, the rest join over the local network, and the same drive is scored on every phone with a colored corner on each tile showing who called it. No account and no signal needed.")
            Paragraph("A shared book is for people who are not together. Invite somebody from a book you own and you both add plates to it from wherever you are, over iCloud.")
        }
    }

    private var handsFree: some View {
        SettingsGroup("Hands free") {
            Illustration { Art.voice }
            // Verbatim, and staying verbatim. A Siri phrase that is nearly right does
            // nothing at all, so this is the one section on the page where the exact
            // wording is load-bearing rather than editorial.
            Paragraph("Say \u{201C}Hey Siri, log a plate in Plates\u{201D}, or name it outright: \u{201C}log New Jersey in Plates\u{201D}. Either one opens voice mode and keeps listening, so the rest of the trip needs no phone at all. Say \u{201C}stop\u{201D} when you are done.")
        }
    }

    private var widgetAndLookup: some View {
        SettingsGroup("The widget and the lookup") {
            Illustration { Art.widgetAndLookup }
            Paragraph("Add the Collection widget to your Home Screen to see how the trip or book you are filling is doing without opening the app.")
            Paragraph("Plate lookup, under More, is for the one you could not read in time: describe the colors and what was on it, and it shows you the designs that match.")
        }
    }

    /// Run the introduction again. Moved here from Settings, which is where it lived
    /// until this page existed — see `SettingsScreen`'s note on why it ships in
    /// Release at all.
    ///
    /// At the bottom, and quiet. It is the least useful thing on the page for
    /// somebody who came here with a question, and the most useful for somebody
    /// deciding whether the tips are any good.
    private var replay: some View {
        SettingsGroup("The tips") {
            Button {
                Haptics.selection()
                coach.replayTour()
                // Back to the app, or the tour replays behind a reference page.
                // `RootView` moves to the Game tab on its own; this is what gets the
                // page out of the way so the card is the thing on screen.
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Replay the tour")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text("Tips appear once, as things come up. This brings them back, along with the introduction. Nothing you have collected changes.")
                        .font(.plates(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Pictures

/// The band a drawing sits in: the app's paper, inset at the top of a white card.
///
/// On `ground` rather than `surface` so the picture reads as something laid on the
/// card instead of as the card's first paragraph, and so a drawing made of pale
/// shapes has something to sit against. The hairline underneath is the same one the
/// settings rows use, which is what stops the band floating.
private struct Illustration<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Theme.ground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            // Decoration. Every one of these restates its own paragraph and none of
            // them adds a fact, so a screen reader that skips them loses nothing and
            // is spared eight descriptions of shapes.
            .accessibilityHidden(true)
    }
}

/// The drawings.
///
/// Assembled from things the app already draws rather than invented for this page.
/// That is the whole discipline here: a bespoke illustration of a plate is one more
/// thing to redraw when the tile changes, and it will not be redrawn — it will just
/// slowly stop looking like the app. A real `PlateTile` cannot.
private enum Art {

    /// Three real tiles, the middle one found, at the size the grid draws them.
    ///
    /// The turn from paper to artwork *is* the game, and it is much better shown
    /// than described. Arizona in the middle for the same reason the welcome card
    /// uses it: it reads as a place at a glance rather than as letters in a box.
    @ViewBuilder
    static var tiles: some View {
        HStack(spacing: 7) {
            tile("AL", found: false)
            tile("AZ", found: true)
            tile("AR", found: false)
        }
    }

    @ViewBuilder
    private static func tile(_ code: String, found: Bool) -> some View {
        if let plate = Plate.plate(for: code) {
            PlateTile(plate: plate, isFound: found, rarity: 5, showsProgressDot: true)
                .frame(width: 68, height: 68 / Theme.tileAspect)
        }
    }

    /// A drive that ends, beside a book that does not.
    ///
    /// The left half is the trip header's own progress bar in miniature — gold dot,
    /// gold dashes, and the checkered flag the Finished section is labelled with. The
    /// right half is the Books tab's symbol with the one mark that says "no end".
    static var tripAndBook: some View {
        HStack(spacing: 20) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.paint)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))

                Capsule()
                    .strokeBorder(Theme.paint,
                                  style: StrokeStyle(lineWidth: 3, dash: [5, 4]))
                    .frame(width: 46, height: 3)

                Image(systemName: "flag.checkered")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.route)
            }

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 34)

            HStack(spacing: 5) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.route)
                Image(systemName: "infinity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    /// A trip going into a book — the Trips tab's symbol, an arrow, the Books tab's.
    static var fold: some View {
        HStack(spacing: 14) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.route)

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.inkMuted)

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.route)
        }
    }

    /// Five plates climbing, in the five tier colours.
    ///
    /// The colours come from `RarityTier` itself, so this ramp is the same ladder the
    /// find card and the map are using — grey, green, blue, violet, gold. Growing
    /// rather than just recolouring, because colour alone is not a scale to somebody
    /// who cannot separate green from blue.
    static var rarityRamp: some View {
        let tiers: [RarityTier] = [.common, .uncommon, .rare, .epic, .legendary]
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(tiers.enumerated()), id: \.offset) { index, tier in
                let width = 22 + CGFloat(index) * 7
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tier.color)
                    .frame(width: width, height: width / Theme.tileAspect)
                    // The inset hairline every real plate has. Without it these are
                    // five coloured rectangles; with it they are five plates, which
                    // is the difference between a legend and a picture.
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                            .padding(2.5)
                    )
            }
        }
    }

    /// Which states, beside where you were.
    ///
    /// A dozen tiles with five filled is the Map's question in one glance; a dashed
    /// line with pins on it is the Trail's. Drawn side by side because the pair of
    /// them is the point — the paragraph exists only to say which is which.
    static var mapAndTrail: some View {
        HStack(spacing: 20) {
            let filled: Set<Int> = [0, 1, 4, 6, 9]
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(filled.contains(row * 4 + column)
                                      ? Theme.found : Theme.unfound)
                                .frame(width: 13, height: 9)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 34)

            // The three stops are placed against the same unit box the path is drawn
            // in, rather than asked of the path. A `Path` cannot hand back points
            // along itself, and three constants beat carrying a bezier solver around
            // for a decoration.
            GeometryReader { proxy in
                ZStack {
                    TrailPath()
                        .stroke(Theme.route.opacity(0.45),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                   dash: [4, 4]))
                    ForEach(Array(TrailPath.stops.enumerated()), id: \.offset) { _, stop in
                        Circle()
                            .fill(Theme.route)
                            .frame(width: 7, height: 7)
                            .position(x: stop.x * proxy.size.width,
                                      y: stop.y * proxy.size.height)
                    }
                }
            }
            .frame(width: 62, height: 34)
        }
    }

    /// A car full of people, and two people who are not in it.
    ///
    /// Overlapping for the party — one car, shoulder to shoulder — and separated
    /// across a cloud for the shared book. The colours are the app's real player
    /// palette, so these are the same discs that appear on a tile's corner.
    static var together: some View {
        HStack(spacing: 20) {
            HStack(spacing: -9) {
                ForEach(0..<3, id: \.self) { index in
                    face(Theme.playerColor(index))
                }
            }

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 34)

            HStack(spacing: 7) {
                face(Theme.playerColor(3))
                Image(systemName: "icloud.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkMuted.opacity(0.7))
                face(Theme.playerColor(4))
            }
        }
    }

    private static func face(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(Theme.ground, lineWidth: 2))
    }

    /// The waveform button, at the size it is on the Game screen and in the same
    /// white circle — so the thing to reach for is recognisable before it is read
    /// about.
    static var voice: some View {
        Image(systemName: "waveform")
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Theme.route)
            .frame(width: 58, height: 58)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
    }

    /// A home-screen tile with a progress bar, and a plate under a magnifier.
    static var widgetAndLookup: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.inkMuted.opacity(0.4))
                    .frame(width: 26, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.slot)
                    .frame(width: 40, height: 5)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.paint)
                            .frame(width: 25, height: 5)
                    }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 34)

            // A plate you could not quite read, with a glass over it. The inset
            // hairline and the two smudged characters are what make this a plate
            // rather than a white box — an empty rectangle under a magnifier is a
            // picture of searching for anything at all.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 52, height: 52 / Theme.tileAspect)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.inkMuted.opacity(0.45), lineWidth: 1)
                        .padding(3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .overlay(alignment: .center) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.ink.opacity(0.22))
                                .frame(width: 6, height: 10)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.route)
                        .shadow(color: Theme.ground, radius: 2)
                        .offset(x: 6, y: 6)
                }
        }
    }

    /// The Trail's shape: a road that wanders. Drawn in a unit box and scaled, so
    /// the stops below can be given as fractions and stay put at any size.
    private struct TrailPath: Shape {
        /// Where the pins sit, in the same unit space.
        static let stops: [CGPoint] = [
            CGPoint(x: 0.06, y: 0.80),
            CGPoint(x: 0.50, y: 0.30),
            CGPoint(x: 0.94, y: 0.72)
        ]

        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            path.move(to: point(0.06, 0.80))
            path.addQuadCurve(to: point(0.50, 0.30), control: point(0.24, 0.20))
            path.addQuadCurve(to: point(0.94, 0.72), control: point(0.76, 0.44))
            return path
        }
    }
}

/// One block of body text inside a `SettingsGroup`.
///
/// A view rather than a `Text` modifier chain repeated nine times, because the
/// thing that goes wrong on a page like this is drift: one paragraph at 12.5pt and
/// its neighbour at 13 reads as a mistake even when nobody can say which one is
/// wrong. Stacked paragraphs in the same card share the card and get their spacing
/// from the padding, so no divider is needed between them — a rule between two
/// sentences of the same explanation would be dividing an argument from itself.
private struct Paragraph: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.plates(size: 13.5))
            // Full ink, unlike the same size elsewhere in the app. Everywhere else
            // body text at this size is a *subtitle* under a heading in ink, and the
            // muted grey is what says "supporting". Here it is the whole content of
            // the page — nine cards of grey is a page that reads as a disclaimer.
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            // Half the gap a card's own padding would give, because two of these
            // stacked contribute one each and the sum is what the eye sees.
            .padding(.vertical, 11)
    }
}
