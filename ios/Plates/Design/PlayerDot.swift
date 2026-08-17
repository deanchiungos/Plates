import SwiftUI

/// One person, as a colored disc with their face in it.
///
/// Seven screens drew this by hand: a `Circle`, a `Theme.playerColor` fill, a fixed
/// frame, an overlay `Text`, and a conditional font because an emoji and a pair of
/// letters do not want the same size. Seven copies of five lines is a nuisance. What
/// made it worth extracting is that they did not agree, and the disagreement was a
/// bug.
///
/// A letter inside a circle has to be drawn with `Theme.PlateFont.glyph`, not
/// `condensed`. The circle is a raw point value and does not move; `condensed`
/// scales with the reader's text-size setting, so at the accessibility sizes the
/// letters grow straight out of the disc — "DA" in the Settings header sits about
/// half outside its own green circle at XXXL, and the same thing happens on the
/// Players list and in a trip's plate log. `AvatarStack` and `TripHeader` had
/// already worked this out and written it down; the other five had not. It is the
/// same rule the plate tiles follow, and for the same reason: this is an
/// illustration of a person, not prose, and what actually helps somebody who needs
/// large text is the name beside it — which still scales — and the accessibility
/// label, not an initial that has burst its frame.
struct PlayerDot: View {

    /// Which of a player's three glyphs to show. They are genuinely different
    /// sizes of the same idea; see `Player.face`.
    enum Glyph {
        /// Up to two letters, or their emoji. For anything 20pt and up.
        case face
        /// One letter, or their emoji. For the chip in a tile's corner.
        case small
        /// One letter, never an emoji. For the places that have always shown a
        /// letter and would read as a different design with a face in them.
        case initial
    }

    let color: Color
    let text: String
    let isEmoji: Bool
    var size: CGFloat = 24
    /// A ring around the disc, in whatever color it is sitting on, so two dots in
    /// similar colors do not merge into one blob. Nil for no ring.
    var ring: Color?
    /// Overrides the derived type size. For the poster, which is rendered at a fixed
    /// scale into an image and so has no overflow to fix — only a look to keep.
    var glyphSize: CGFloat?
    /// The glyph's own color. Only the "+N" circle wants anything but ink.
    var ink: Color = Theme.ink

    @MainActor
    init(_ player: Player,
         showing glyph: Glyph = .face,
         size: CGFloat = 24,
         ring: Color? = nil,
         glyphSize: CGFloat? = nil) {
        self.color = Theme.playerColor(player.colorIndex)
        switch glyph {
        case .face:    self.text = player.face
        case .small:   self.text = player.smallFace
        case .initial: self.text = player.initial
        }
        // `.initial` is letters by definition, whatever the player picked.
        self.isEmoji = glyph == .initial ? false : player.usesEmoji
        self.size = size
        self.ring = ring
        self.glyphSize = glyphSize
    }

    /// For the callers that have no `Player` to hand: the "+N" circle, the stand-in
    /// shown before this phone has been introduced, and the avatar picker previewing
    /// a face nobody has chosen yet.
    ///
    /// `glyphSize` is deliberately not offered here. It is an override for a caller
    /// that has measured a specific layout, and the one such caller has a `Player`;
    /// offering it on this initializer too would be a second way to spell something
    /// nobody was asking for.
    init(color: Color, text: String, isEmoji: Bool = false,
         size: CGFloat = 24, ring: Color? = nil,
         ink: Color = Theme.ink) {
        self.color = color
        self.text = text
        self.isEmoji = isEmoji
        self.size = size
        self.ring = ring
        self.glyphSize = nil
        self.ink = ink
    }

    /// Emoji get the system face at a larger size: the condensed plate font does not
    /// carry them, and a glyph drawn from a fallback at letter-size sits small in the
    /// circle. Two letters need to be smaller than one — the pair has to fit across a
    /// diameter, a single letter only has to fit inside it.
    private var derived: CGFloat {
        if let glyphSize { return glyphSize }
        if isEmoji { return size * 0.55 }
        return text.count > 1 ? size * 0.42 : size * 0.62
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(text)
                    .font(isEmoji ? .system(size: derived)
                                  : Theme.PlateFont.glyph(derived))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            )
            .overlay {
                if let ring {
                    Circle().strokeBorder(ring, lineWidth: size * 0.08)
                }
            }
    }
}
