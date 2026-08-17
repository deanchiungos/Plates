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
