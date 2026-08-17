import SwiftUI

/// Where a balloon should point, and which way it wants to be read.
///
/// `prefersAbove` means sit above the target and point down at it, rather than the
/// default below. For a tile in a grid, below is right: the eye reads downward from
/// the thing being described, and what gets covered is more of the same grid. For a
/// row in a list it is exactly wrong — the space below a row is the *next* row, so a
/// balloon about the Finished section lands squarely on the trip that was just filed
/// there, hiding its own evidence. Both layers still override this when there is not
/// room; a preference is not a promise.
struct GuideTarget {
    let anchor: Anchor<CGRect>
    let prefersAbove: Bool
}

/// Where each of one guide's balloons should point, collected from wherever its
/// target is.
///
/// A dictionary rather than one anchor because a screen can host several targets at
/// once — the grid registers a tile for `firstTap` and another for `uncheck` — and
/// the layer picks whichever one it has actually chosen to show.
///
/// Generic over the item because the coach and the tour are genuinely different
/// features with different item types, and this part of them was not different at
/// all: two copies of the same struct and the same three-line key, kept in step by a
/// comment in each saying it matched the other.
struct GuideAnchorKey<Item: Hashable>: PreferenceKey {
    static var defaultValue: [Item: GuideTarget] { [:] }

    static func reduce(value: inout [Item: GuideTarget],
                       nextValue: () -> [Item: GuideTarget]) {
        // First one wins. Preference order follows view order, so for a grid this is
        // the earliest matching tile — and a caller that marks exactly one view (the
        // usual case) is unaffected either way.
        value.merge(nextValue()) { existing, _ in existing }
    }
}

/// Where a balloon actually goes, and whether its target is on the page at all.
///
/// The coach and the tour are different features and this was never one of the
/// differences: the above-or-below decision, the clamped width, the left edge pulled
/// back inside the margins, and the notch that keeps tracking the target after the
/// box has been clamped were written out twice, character for character, under a
/// comment in each saying it matched the other. `GuideTarget` above was extracted
/// for exactly this pair and stopped at the data half.
///
/// The comment did not hold them in step, which is the whole argument. `onScreen`
/// gained a zero-height guard in the tour and never got it in the coach, so a stop
/// and a tip pointed at the same collapsed view disagreed about whether it was
/// visible. The guard is right — a view laid out at zero height reports a rect that
/// passes the other two tests while being nothing you can point at — so it is here,
/// once, for both.
///
/// The five numbers that genuinely differ are arguments. A tour bubble is a card
/// with a step count and four buttons and needs 215pt reserved; a coach balloon is a
/// sentence and needs 110.
enum GuidePlacement {

    /// Is the target actually on the page right now?
    ///
    /// The anchor doc says a scrolled-away target makes its balloon fade, and in a
    /// *lazy* container that is simply true — the view stops existing and takes its
    /// anchor with it. A plain `ForEach` in a `ScrollView` is not lazy. Every trip
    /// row is realised at all times, so the ninth one reports a rect a few hundred
    /// points below the page, and the placement arithmetic below happily clamps the
    /// balloon to the bottom edge and aims it at the tab bar.
    ///
    /// Nothing is dismissed by failing this. The item keeps its turn and draws the
    /// moment its subject is scrolled into view, which is the only moment it means
    /// anything.
    static func onScreen(_ target: CGRect, in bounds: CGSize) -> Bool {
        target.maxY > 0 && target.minY < bounds.height && target.height > 0
    }

    struct Placed {
        /// Sitting above the target, pointing down at it.
        let above: Bool
        let width: CGFloat
        /// The balloon's left edge, in the layer's coordinates.
        let left: CGFloat
        /// Where the notch sits along the balloon's own width.
        let notchX: CGFloat
    }

    /// Below the target unless the caller asked otherwise, and above it anyway when
    /// there is not room below — reading downward from the thing being described is
    /// the natural direction for a grid, and a balloon above a target covers whatever
    /// heading introduced it. See `GuideTarget` for why a list wants the opposite.
    ///
    /// Judged on room, not on which half of the screen the target sits in. That was
    /// the first attempt and it put the balloon above a tile with 270pt of empty grid
    /// below it, because a tile 59% of the way down a screen is not near the bottom
    /// of anything. `roomNeeded` is a deliberate over-estimate of the balloon's
    /// height — flipping a little early costs nothing, and clipping one against the
    /// tab bar costs the whole thing.
    ///
    /// A preference for above is honoured only when above is actually habitable, for
    /// the same reason: a row near the top of a screen has nothing over it.
    static func place(target: CGRect,
                      in bounds: CGSize,
                      prefersAbove: Bool,
                      gap: CGFloat,
                      margin: CGFloat,
                      roomNeeded: CGFloat,
                      widthCap: CGFloat,
                      notchInset: CGFloat) -> Placed {
        let roomBelow = target.maxY + gap + roomNeeded <= bounds.height
        let roomAbove = target.minY - gap - roomNeeded >= 0
        let above = prefersAbove ? roomAbove || !roomBelow : !roomBelow
        let width = min(widthCap, bounds.width - margin * 2)

        // Centred on the target, then pulled back inside the margins. A tile in the
        // first or last column would otherwise hang the balloon off the page.
        let left = min(max(target.midX - width / 2, margin),
                       bounds.width - margin - width)

        // The notch tracks the target even after the box has been clamped, which is
        // the whole point of clamping the two separately: the balloon slides back on
        // screen, the finger stays pointed at the tile. Held clear of the corner
        // radius at either end.
        let notchX = min(max(target.midX - left, notchInset), width - notchInset)

        return Placed(above: above, width: width, left: left, notchX: notchX)
    }
}

extension View {
    /// Pin a balloon to one edge of the page and push it away from the opposite side.
    ///
    /// Aligned and padded rather than centred with `.position`, which is the one
    /// thing worth reading twice here. `.position` needs the balloon's height to put
    /// its *edge* against the target, and the obvious way to learn that — a size
    /// preference read back out — does not work from inside
    /// `overlayPreferenceValue`: the nested preference never propagates, `size`
    /// stays zero, and the balloon renders half a box out of place forever. Pinning
    /// an edge and pushing it away from the opposite side needs no measurement.
    func guidePlaced(_ placed: GuidePlacement.Placed,
                     target: CGRect,
                     in bounds: CGSize,
                     gap: CGFloat) -> some View {
        frame(width: placed.width, alignment: .leading)
            .padding(.leading, placed.left)
            .padding(.top, placed.above ? 0 : max(0, target.maxY + gap))
            .padding(.bottom, placed.above ? max(0, bounds.height - target.minY + gap) : 0)
    }
}
