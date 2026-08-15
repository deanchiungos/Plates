import SwiftUI

/// The core component. 5:3 plate proportions, an inner light ring standing in for
/// the embossed edge, and — when several people are playing — a color bar along
/// the bottom showing who called it. The bar rather than a full tint, so the tile
/// still reads as a plate.
struct PlateTile: View {
    let plate: Plate
    let isFound: Bool
    var spotterColor: Color? = nil
    var spotterInitial: String? = nil
    /// True when `spotterInitial` is an emoji rather than a letter, so the chip can
    /// pick a font that actually has the glyph.
    var spotterIsEmoji: Bool = false
    /// Everyone who has banked this plate. Empty or one under the ordinary rules;
    /// several once a party lets more than one person claim the same state.
    var claimants: [Player] = []
    var repeatCount: Int = 0          // shown only in unlimited scoring
    var showsRepeats: Bool = false

    /// Rarity 1...10 on the current trip. Defaults to the plate's national value so
    /// the tile still works outside a trip — the gallery, previews.
    var rarity: Int? = nil

    /// Draws the found/not-found pip in the corner. Off by default: it only earns
    /// its space in a grid that actually contains both states, and a screen where
    /// every plate is already found would just get a filled dot on every tile.
    var showsProgressDot: Bool = false

    private var tier: RarityTier {
        RarityTier.forRarity(rarity ?? plate.points)
    }

    /// Spotting a plate reveals its own colors. Unfound stays paper, so the
    /// found/unfound read is still instant even once every state is styled.
    private var style: PlateStyle? {
        isFound ? (PlateStyle.style(for: plate.code) ?? .fallback) : nil
    }

    /// The color the plate itself paints its serial, once found. Anything drawn
    /// over the artwork — the repeat count as much as the code — reads as part
    /// of the plate, so it all takes the same ink.
    private var ink: Color? {
        guard let style else { return nil }
        return PlateArtwork.ink(plate.code) ?? style.ink
    }

    var body: some View {
        ZStack {
            if let style {
                PlateBackground(code: plate.code, style: style)
            } else {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.surface)
            }

            // embossed edge
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(isFound ? Color.white.opacity(0.35) : Color.white, lineWidth: 1.5)
                .padding(1)

            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(isFound ? Color.black.opacity(0.22) : Theme.line, lineWidth: 1)

            if let style {
                PlateLettering(code: plate.code, style: style, name: plate.short)
            } else {
                // Unfound stays paper: the plate's own colors are the reward for
                // spotting it, so they cannot leak into the not-yet state.
                VStack(spacing: 2) {
                    Text(plate.code)
                        .font(Theme.PlateFont.glyph(19))
                        .tracking(0.6)
                        .foregroundStyle(Theme.plateIdle)

                    Text(plate.short.uppercased())
                        .font(Theme.PlateFont.glyph(8))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                        .foregroundStyle(Theme.plateSub)
                }
            }

            // Progress pip — top right. Empty ring until you spot it, then filled.
            //
            // The *empty* one is deliberately neutral. It was once tier-colored on
            // both states, which told you what a plate was worth before you had any
            // right to know: the grid pre-announced the good ones and the reveal on
            // the find card had nothing left to reveal.
            //
            // Once it is yours that argument is spent — the find card already said
            // LEGENDARY — so the filled dot wears the tier it was banked at. Which
            // is what makes the grid worth scanning after the fact: a wall of found
            // plates with two gold dots in it is a record of the trip's best moments,
            // and a grey dot means the same plate that was a banner in Sacramento was
            // nothing at all where you actually caught it.
            //
            // The white ring is what keeps it legible once the tile is wearing the
            // plate's own artwork behind it.
            if showsProgressDot {
                VStack {
                    HStack {
                        Spacer()
                        ProgressDot(tier: tier, isFound: isFound)
                    }
                    Spacer()
                }
                .padding(5)
            }

            // Who spotted it: a chip in the top-left, opposite the rarity pip.
            // Tried a bottom bar and a colored border first — the bar sat exactly
            // where every motif's horizon is, and the border read as "selected"
            // rather than "Mia got this one". The chip also shows *who*, not just
            // a color, so it works without the player strip in view.
            // Several claimants get the overlapping stack instead of one chip — a
            // shared-claims party turns "who got this" into "who all got this", and
            // three chips in a row would not fit a tile this size anyway. One
            // claimant keeps exactly the chip it always had.
            if isFound, claimants.count > 1 {
                VStack {
                    HStack {
                        AvatarStack(players: claimants, limit: 3, size: 13,
                                    background: .white.opacity(0.9))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
            } else if isFound, let spotterColor, let spotterInitial {
                VStack {
                    HStack {
                        Text(spotterInitial)
                            .font(spotterIsEmoji ? .system(size: 8)
                                                 : .plates(size: 8, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 12, height: 12)
                            .background(Circle().fill(spotterColor))
                            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
            }

            // bottom-left, so it never collides with the spotter chip above it
            if showsRepeats, repeatCount > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(repeatCount)")
                            .font(.plates(size: 8.5, weight: .heavy))
                            .foregroundStyle((ink ?? Theme.plateSub).opacity(0.75))
                        Spacer()
                    }
                }
                .padding(5)
            }
        }
        .aspectRatio(Theme.tileAspect, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var parts: [String] = [isFound ? "Spotted" : "Not yet spotted"]
        // Only after the find. Reading the tier out on an unspotted plate would
        // hand VoiceOver users the spoiler the pip no longer shows anyone else.
        if isFound { parts.append(tier.label.lowercased()) }
        if isFound, showsRepeats, repeatCount > 1 { parts.append("seen \(repeatCount) times") }
        return parts.joined(separator: ", ")
    }
}

/// The mark in the tile's top corner: an empty ring until you spot the plate, then a
/// lit bead in the tier it was banked at.
///
/// It was a flat disc of tier color, and at seven points across that is a sticker —
/// legible, and completely uninteresting. Three things now separate it from the
/// artwork it sits on and from the tiers below it: an off-centre highlight so the
/// light has a direction, a bloom of the tier's own color past the edge, and, for
/// legendary alone, a second wider bloom on top of the first. Compounding two shadows
/// rather than widening one keeps a hot core with a soft falloff, which is what
/// actually reads as *lit* — a single large-radius shadow just makes a bigger,
/// flatter smudge.
///
/// The empty state is untouched, and deliberately. It is neutral because a
/// tier-colored ring would pre-announce which unfound plates are worth having, and
/// nothing about making the found ones brighter changes that.
private struct ProgressDot: View {
    let tier: RarityTier
    let isFound: Bool

    /// The top two tiers are drawn wider than the rest. At this size a point is a
    /// seventh of the dot, which is plenty — and these are the tiers where the mark
    /// is the point of the tile rather than a footnote on it.
    ///
    /// Mythic used to be excluded from this and from the outer glow below, both of
    /// which tested `== .legendary`. The crimson dot came out *smaller and dimmer*
    /// than the gold one under it, so the rarest thing on the grid was the quietest
    /// mark on it — and since mythic is a different color rather than one more step
    /// up the ramp, size and glow are the only cues left saying it outranks gold.
    private var size: CGFloat {
        guard isFound else { return 7 }
        switch tier {
        case .mythic:    return 9
        case .legendary: return 8
        default:         return 7
        }
    }

    var body: some View {
        ZStack {
            if isFound {
                Circle()
                    .fill(RadialGradient(colors: [tier.highlight, tier.color],
                                         center: UnitPoint(x: 0.33, y: 0.28),
                                         startRadius: 0,
                                         endRadius: size * 0.85))
                    .shadow(color: tier.color.opacity(0.9), radius: tier.glowRadius)
                    .shadow(color: tier >= .legendary ? tier.color.opacity(0.55) : .clear,
                            radius: tier.glowRadius * 1.9)
            }

            // Kept over the top of the bead rather than under it, because the ring is
            // what holds the dot apart from whatever the plate's artwork is doing
            // behind it — and the busiest artwork is exactly where the glow is least
            // able to do that on its own.
            Circle()
                .strokeBorder(isFound ? Color.white.opacity(0.85)
                                      : Theme.inkMuted.opacity(0.45),
                              lineWidth: 1.2)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    return LazyVGrid(columns: cols, spacing: 8) {
        PlateTile(plate: Plate.plate(for: "OH")!, isFound: false)
        PlateTile(plate: Plate.plate(for: "CO")!, isFound: true)
        PlateTile(plate: Plate.plate(for: "AK")!, isFound: false)
        PlateTile(plate: Plate.plate(for: "MT")!, isFound: true,
                  spotterColor: Theme.playerColor(1))
    }
    .padding()
    .background(Theme.ground)
}
