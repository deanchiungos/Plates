import SwiftUI
import UIKit

/// The Mile Marker tokens. One accent (route blue) carries state; one signal
/// (road-paint amber) is reserved for rarity and progress.
///
/// The neutrals are warm — eggshell paper rather than white. They used to be
/// biased cool toward the route blue, which is the safe choice and also the
/// invisible one: a near-white cool grey is what an app looks like when nobody
/// picked a background. Cream is what a road atlas, a glovebox map and a
/// printed plate specimen are all on, and navy ink over it is the pairing the
/// whole app is already built out of.
///
/// The tint lives in `ground` alone. `surface` is white, which is the whole of
/// how a card is told apart from the page it is on — when both were cream the
/// two ran together and the app lost the shape of its own layout. The page is
/// still only a few percent off white; it just no longer has to carry the
/// separation as well as the colour.
enum Theme {

    // MARK: Colour
    static let ground     = Color(hex: 0xFAF7EF)
    static let surface    = Color(hex: 0xFFFFFF)
    static let route      = Color(hex: 0x12395E)
    static let routeEdge  = Color(hex: 0x0D2C4A)
    static let routeRing  = Color(hex: 0x2B5A87)
    static let paint      = Color(hex: 0xF0B429)
    static let ink        = Color(hex: 0x1B2231)
    /// Warm grey, not blue-grey. On cream the old cool muted text read as
    /// faintly purple, which is the usual tell that a palette was recoloured
    /// halfway.
    static let inkMuted   = Color(hex: 0x8A8377)
    static let line       = Color(hex: 0xE7E1D1)
    /// Map only. Green is not otherwise in the palette, and it earns its place
    /// there: on a map, filled-in means collected in a way no accent colour does.
    static let found      = Color(hex: 0x2FB574)
    static let unfound    = Color(hex: 0xE9E3D5)
    /// The recessed pressing an uncollected plate goes into, in the book. Darker
    /// than `unfound` because it takes an inner shadow and has to read as a
    /// hollow rather than as a disabled tile.
    static let slot       = Color(hex: 0xE0DACA)

    /// The selected region on the map, and nothing else.
    ///
    /// Yellow, by preference — and it is worth recording that this collides with one
    /// thing on purpose. Legendary rarity fills a region pale amber, so in Rarity
    /// mode a selected legendary state is a yellow ring around a yellowish fill.
    /// Everywhere else it is unmistakable: every other map fill is pale blue, pale
    /// violet or grey, and the found green in the other mode is nowhere near it.
    ///
    /// It gets away with it because the ring is far more saturated than any fill and
    /// carries a glow, so the two read as different objects rather than the same
    /// colour twice. If that ever stops being true, the fix is to darken the
    /// legendary map fill rather than to move the selection colour again.
    static let mapSelection = Color(hex: 0xFFC400)

    /// The serial and state name on a plate nobody has spotted yet.
    ///
    /// Black, like a real serial. It was a pale warm grey on the theory that an
    /// unfound plate should look faint, and that theory was wrong twice over: it
    /// made the grid look washed out, and a blank plate with grey lettering is
    /// not a thing that exists — every unissued plate stock is stamped in ink you
    /// can read across a car park. What says "not yet" is the empty white field,
    /// not weak type on it.
    static let plateIdle  = Color(hex: 0x14161B)
    static let plateSub   = Color(hex: 0x6C6455)
    static let plateOnSub = Color(hex: 0x8FB4D6)

    /// Player colours, chosen to stay distinguishable against the route-blue fill
    /// and from each other. Players store an index into this array.
    static let playerColors: [Color] = [
        Color(hex: 0x3DDC84),   // green
        Color(hex: 0xFF7A45),   // orange
        Color(hex: 0x4DA3FF),   // blue
        Color(hex: 0xFFD23F),   // yellow
        Color(hex: 0xC77DFF),   // violet
        Color(hex: 0xFF5D8F)    // pink
    ]

    static func playerColor(_ index: Int) -> Color {
        playerColors[((index % playerColors.count) + playerColors.count) % playerColors.count]
    }

    // MARK: Type
    //
    // Two faces. DIN Condensed is the road-sign face real plates are set in — it is
    // the subject's own vernacular, and it is restricted to plate glyphs, numerals
    // and eyebrows. Everything read as a sentence is Avenir Next.
    //
    // Both ship with iOS, so neither costs bundle size or a licence. Avenir replaced
    // the system face because SF Pro is what an app uses when nobody chose a font,
    // and it makes every iOS app look like the same app.
    /// Avenir Next, in the six weights iOS actually ships.
    ///
    /// There is no Light and no face literally called SemiBold — Demi Bold is the
    /// semibold — so `.light` borrows Ultra Light and `.semibold` maps to Demi Bold.
    /// Anything heavier than bold lands on Heavy.
    static func avenir(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "AvenirNext-UltraLight"
        case .medium:                    return "AvenirNext-Medium"
        case .semibold:                  return "AvenirNext-DemiBold"
        case .bold:                      return "AvenirNext-Bold"
        case .heavy, .black:             return "AvenirNext-Heavy"
        default:                         return "AvenirNext-Regular"
        }
    }

    /// The Dynamic Type style a fixed point size should scale against.
    ///
    /// `Font.custom(_:size:relativeTo:)` needs a text style to know how far to scale,
    /// and the app was written in absolute points. Rather than reclassify 130-odd call
    /// sites by hand, this maps a size onto the style whose default size is nearest —
    /// so a 17pt line scales like body text and a 12pt caption scales like a caption,
    /// which is what someone raising their text size expects.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5:  return .caption2
        case ..<13:    return .caption
        case ..<15:    return .footnote
        case ..<16.5:  return .subheadline
        case ..<19:    return .body
        case ..<21:    return .title3
        case ..<25:    return .title2
        case ..<30:    return .title
        default:       return .largeTitle
        }
    }

    enum PlateFont {
        // Memoising this by size was tried and measured no faster — SwiftUI
        // already caches the resolved face — so it stays a plain call rather
        // than carrying a lock and a mutable static for nothing.

        /// Condensed type that is *read*: eyebrows, scores, tier words, headline
        /// numerals. Scales with the reader's text-size setting, like all prose.
        static func condensed(_ size: CGFloat) -> Font {
            // .custom falls back to the system face if the family is ever unavailable.
            .custom("DINCondensed-Bold", size: size)
        }

        /// Condensed type that is *drawn*: the serial on a plate, the code in a map
        /// callout chip, the lettering on the app icon. Locked to the size given.
        ///
        /// `Font.custom(_:size:)` scales with Dynamic Type; every dimension of a
        /// plate does not. The card is a fixed 5:3 rectangle and its corner radius,
        /// its embossed-edge inset and its rarity hairline are raw point values, so
        /// at XXXL the glyphs grew 29% inside a tile that stayed exactly 153px tall
        /// and the state names ran to both edges. On a trail marker at wide zoom —
        /// a card about 26pt across — the same multiplier puts the code straight
        /// over the sides, which reads as the plate having shrunk out from under
        /// its own text.
        ///
        /// This is not ignoring Dynamic Type, it is declining to apply it to an
        /// illustration. Everything read as language still scales, and the plate is
        /// still announced in full to VoiceOver by the tile's accessibility label —
        /// which is the accommodation that actually helps here, since a serial
        /// spilling off its plate is not more legible for being larger.
        static func glyph(_ size: CGFloat) -> Font {
            .custom("DINCondensed-Bold", fixedSize: size)
        }
    }

    // MARK: Metrics
    static let tileAspect: CGFloat = 5.0 / 3.0
    static let tileRadius: CGFloat = 7
    static let cardRadius: CGFloat = 16
    static let gridGap: CGFloat = 8
    static let screenPadding: CGFloat = 16

    /// The grid adapts rather than fixing a column count: 4 across on a phone,
    /// more on an iPad, without the tiles ballooning to fill the width.
    static let tileMinWidth: CGFloat = 78
    static let tileMaxWidth: CGFloat = 104

    // MARK: System controls

    /// Repaint the UIKit controls SwiftUI has no colour hooks for.
    ///
    /// A segmented control draws its own track and its own selected pill, and
    /// both are system greys — cool ones. Against a warm page they were the two
    /// coldest things on the screen and, being at the top of the Map and the
    /// Collection, the first two things you saw. Everything else in the app is a
    /// shape we draw ourselves, so this appearance proxy is the whole of the
    /// UIKit surface area; called once, from the app's initialiser.
    @MainActor
    static func applyToSystemControls() {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(surface)
        segmented.backgroundColor = UIColor(line)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(ink)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(ink.opacity(0.7))],
                                         for: .normal)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// The app's text face: Avenir Next, sized in points, scaling with Dynamic Type.
    ///
    /// A drop-in replacement for `.system(size:weight:)`, which is what every call
    /// site used before — chosen so the switch could be mechanical and so the sizes
    /// already tuned against each layout did not have to be re-picked.
    ///
    /// Two things it fixes at once. Avenir Next is not the system face, so the app
    /// stops looking like every other iOS app; and `relativeTo:` means text finally
    /// responds to the reader's text-size setting, which nothing in the app did while
    /// every size was an absolute point value.
    ///
    /// SF Symbols deliberately still use `.system` — a symbol takes its stroke weight
    /// from the font it is given, and handing one a text face loses that.
    static func plates(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(Theme.avenir(weight),
                size: size,
                relativeTo: Theme.textStyle(for: size))
    }
}
