import SwiftUI

/// A balloon that points at the thing it is talking about.
///
/// The alternative was the centred `PopupHost` card, which the app already has and
/// which is wrong for this: a popup is a *decision* — it takes the screen because it
/// needs an answer before anything else happens. A tip needs no answer. It is an
/// aside about one control, and an aside that dims the screen and blocks every tap
/// to say "swipe left on a row" is louder than the thing it is describing.
///
/// So: no scrim, no dimming, nothing intercepted. The mark floats over the page with
/// a notch aimed at its subject, and somebody who ignores it entirely and plays the
/// game is using the app exactly right. It goes away when they do the thing, when
/// they tap it, or when they leave.
///
/// The shadow here is the one real shadow in the app. Everywhere else depth is a
/// hairline and a fill, because the whole surface is meant to read as printed paper.
/// This is the exception that proves it: the balloon is the only element that is
/// genuinely *above* the page rather than part of it, and it needs to look it or it
/// reads as a blue box somebody left in the layout.
struct CoachMark: View {
    /// A resource rather than a `LocalizedStringKey`, because the words are needed
    /// twice: drawn, and spoken to VoiceOver. A key can only be drawn — there is no
    /// way to resolve one back to a string — and the catalog harvests a literal in
    /// this position just the same.
    let text: LocalizedStringResource
    /// Which way the notch points — toward the target, so the balloon sits opposite.
    let pointing: Edge
    /// Where the notch sits along the balloon's width, as a point in balloon space.
    /// Clamped by the layer so it never rides off a rounded corner.
    let notchX: CGFloat
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let notchHeight: CGFloat = 10
    private let notchWidth: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if pointing == .top { notch(up: true) }

            Text(text)
                .font(.plates(size: 13.5, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                // Fills whatever width the layer gives it, so every balloon in the
                // app is the same width. Left to size itself, a three-word tip and a
                // two-line one are visibly different objects — and the notch, which
                // is positioned against the layer's idea of the width, would hang off
                // the end of the short one.
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.route)
                )

            if pointing == .bottom { notch(up: false) }
        }
        .shadow(color: Theme.ink.opacity(0.18), radius: 10, y: 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // One element, not a text plus a shape. The hint says what tapping does,
        // because a balloon is not a control anybody has met before.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismisses this tip")
        .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.92).combined(with: .opacity))
    }

    private func notch(up: Bool) -> some View {
        Triangle(pointingUp: up)
            .fill(Theme.route)
            .frame(width: notchWidth, height: notchHeight)
            // Positioned along the balloon's width rather than centred: the notch has
            // to land on the target, and the target is rarely under the middle of the
            // text that describes it.
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: notchX - notchWidth / 2)
    }

    private struct Triangle: Shape {
        let pointingUp: Bool

        func path(in rect: CGRect) -> Path {
            var path = Path()
            if pointingUp {
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            } else {
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            }
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Anchoring

/// See `GuideAnchorKey`, which the tour shares.
typealias CoachAnchorKey = GuideAnchorKey<Coach.Tip>

extension View {
    /// Marks this view as what a tip's balloon points at.
    ///
    /// Apply it to the *specific* view the tip is about — the one unfound tile, the
    /// first trip row — not to a container. In a lazy grid or list the anchor exists
    /// only while the view is realised, which is exactly the behaviour wanted: scroll
    /// the target away and the balloon fades rather than chasing something else.
    /// `active` rather than an `if` around the modifier. A conditional modifier gives
    /// the two branches different view identities, so the tile the balloon points at
    /// would be torn down and rebuilt the moment it stopped being the target — losing
    /// its find animation at exactly the moment that animation is the whole reward.
    func coachAnchor(_ tip: Coach.Tip,
                     active: Bool = true,
                     prefersAbove: Bool = false) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) {
            active ? [tip: GuideTarget(anchor: $0, prefersAbove: prefersAbove)] : [:]
        }
    }

    /// Hosts the balloons for one screen. Goes last in a screen's modifier chain, so
    /// the mark draws above that screen's own content and below the tab bar.
    ///
    /// Pass `copy` as a stored property, not as a literal written out here. Every screen used to spell its copy out inline here, which reads well and
    /// costs more than it looks: a dictionary literal in a modifier chain is solved
    /// as part of the chain, so each entry is another term in the same constraint
    /// system as every modifier around it. `GameScreen` is where that stopped being
    /// theoretical — a third entry was the change that put its `body` past what the
    /// type checker will attempt, and the fix was moving the words to a `static let`
    /// in the same type. The words stay beside the screen they describe, which was
    /// always the reason not to file them in a table somewhere else; they just stop
    /// being part of an expression that has better things to solve.
    func coachLayer(_ copy: [Coach.Tip: LocalizedStringResource]) -> some View {
        CoachLayer(copy: copy) { self }
    }
}

/// The per-screen host that draws whichever balloon is up.
///
/// Per-screen, and not at `RootView` beside `PopupLayer`, for one reason: a balloon
/// has to move with its target. Most targets live inside a `ScrollView` — a grid
/// tile, a row in the trips list — and an overlay hung at the root reads its anchor
/// in the root's coordinate space, so the first flick of a finger leaves the balloon
/// pointing at empty paper. Hosted here, the anchor and the balloon are measured in
/// the same space and the geometry simply stays true.
///
/// Wraps a screen's content rather than being placed inside it, so the balloon is
/// above everything on that screen and below the tab bar and any sheet.
struct CoachLayer<Content: View>: View {
    @Environment(CoachPresenter.self) private var coach
    @Environment(PopupHost.self) private var popup
    @Environment(TourGuide.self) private var tour

    /// The words for each tip, supplied by the screen that owns them. Copy lives
    /// next to the trigger that fires it rather than in a table far away, so
    /// changing what a tip says never means editing two files.
    let copy: [Coach.Tip: LocalizedStringResource]
    @ViewBuilder var content: Content

    private let gap: CGFloat = 8
    private let margin: CGFloat = 12

    /// How much space a balloon is assumed to want. Scaled, because the one thing
    /// that changes a balloon's height is the reader's text size — at accessibility
    /// sizes the same sentence is four lines instead of two, and a fixed reserve
    /// would tuck it neatly under the tab bar.
    @ScaledMetric(relativeTo: .footnote) private var roomNeeded: CGFloat = 110

    var body: some View {
        content.overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let tip = coach.showing,
                   let words = copy[tip],
                   let target = anchors[tip],
                   // A balloon under a popup's scrim is furniture. It stands down
                   // rather than being dismissed, and returns when the popup goes.
                   popup.item == nil,
                   // And the same under a tour's, which covers the sliver between the
                   // two settle delays where a mark can be promoted a fraction before
                   // a tour arms over the top of it. Read through the guide rather
                   // than `TourGuide.isRunning` because a static is not observable,
                   // and this has to redraw when it changes.
                   tour.screen == nil,
                   onScreen(proxy[target.anchor], in: proxy.size) {
                    balloon(tip, words,
                            target: proxy[target.anchor],
                            prefersAbove: target.prefersAbove,
                            in: proxy.size)
                }
            }
        }
    }

    /// Is the target actually on the page right now?
    ///
    /// The anchor doc says a scrolled-away target makes its balloon fade, and in a
    /// *lazy* container that is simply true — the view stops existing and takes its
    /// anchor with it. A plain `ForEach` in a `ScrollView` is not lazy. Every trip
    /// row is realised at all times, so the ninth one reports a rect a few hundred
    /// points below the page, and the placement arithmetic below happily clamps the
    /// balloon to the bottom edge and aims it at the tab bar.
    ///
    /// Nothing is dismissed by failing this. The tip keeps its turn and draws the
    /// moment its subject is scrolled into view, which is the only moment it means
    /// anything.
    private func onScreen(_ target: CGRect, in bounds: CGSize) -> Bool {
        target.maxY > 0 && target.minY < bounds.height
    }

    private func balloon(_ tip: Coach.Tip,
                         _ words: LocalizedStringResource,
                         target: CGRect,
                         prefersAbove: Bool,
                         in bounds: CGSize) -> some View {
        // Below the target unless the caller asked otherwise, and above it anyway
        // when there is not room below — reading downward from the thing being
        // described is the natural direction for a grid, and a balloon above a
        // target covers whatever heading introduced it. See `GuideTarget` for why a
        // list wants the opposite.
        //
        // Judged on room, not on which half of the screen the target sits in. That
        // was the first attempt and it put the balloon above a tile with 270pt of
        // empty grid below it, because a tile 59% of the way down a screen is not
        // near the bottom of anything. `roomNeeded` is a deliberate over-estimate of
        // the balloon's height — flipping a little early costs nothing, and clipping
        // one against the tab bar costs the whole tip.
        //
        // A preference for above is honoured only when above is actually habitable,
        // for the same reason: a row near the top of a screen has nothing over it.
        let roomBelow = target.maxY + gap + roomNeeded <= bounds.height
        let roomAbove = target.minY - gap - roomNeeded >= 0
        let above = prefersAbove ? roomAbove || !roomBelow : !roomBelow
        let width = min(260, bounds.width - margin * 2)

        // Centred on the target, then pulled back inside the margins. A tile in the
        // first or last column would otherwise hang the balloon off the page.
        let left = min(max(target.midX - width / 2, margin),
                       bounds.width - margin - width)

        // The notch tracks the target even after the box has been clamped, which is
        // the whole point of clamping the two separately: the balloon slides back on
        // screen, the finger stays pointed at the tile. Held clear of the corner
        // radius at either end.
        let notchX = min(max(target.midX - left, 18), width - 18)

        // Aligned and padded rather than centred with `.position`, which is the one
        // thing worth reading twice here. `.position` needs the balloon's height to
        // put its *edge* against the target, and the obvious way to learn that — a
        // size preference read back out — does not work from inside
        // `overlayPreferenceValue`: the nested preference never propagates, `size`
        // stays zero, and the balloon renders half a box out of place forever.
        // Pinning an edge and pushing it away from the opposite side needs no
        // measurement at all.
        return ZStack(alignment: above ? .bottomLeading : .topLeading) {
            // `Color.clear` is hit-testable — it is a view, not a hole — so this
            // full-screen spacer silently ate every touch on whatever screen a mark
            // was showing on. The grid would not scroll and no plate could be tapped
            // until the balloon was dismissed, which is the exact opposite of the
            // one rule this component has. Nothing but a finger finds this: it is
            // invisible, and every screenshot of it looks perfect.
            Color.clear.allowsHitTesting(false)

            CoachMark(text: words,
                      pointing: above ? .bottom : .top,
                      notchX: notchX) {
                Haptics.selection()
                coach.dismiss(tip)
            }
            .onAppear { coach.didDraw(tip, saying: words) }
            .frame(width: width, alignment: .leading)
            .padding(.leading, left)
            .padding(.top, above ? 0 : max(0, target.maxY + gap))
            .padding(.bottom, above ? max(0, bounds.height - target.minY + gap) : 0)
        }
    }
}
