import SwiftUI

/// The bubble a tour speaks through.
///
/// A `CoachMark` with three things added, and each of them is the reason this is a
/// separate view rather than a parameter on that one. It carries **its place in a
/// sequence**, because "2 of 5" is the difference between an interruption you can see
/// the end of and one you cannot. It carries **its own Next**, because a tour is the
/// one thing in this app that genuinely needs an answer before it moves. And it
/// carries **a way out**, on every single stop, because an onboarding you cannot leave
/// is a hostage situation.
///
/// Skip is deliberately quiet rather than hidden. A tour whose exit is a small grey
/// word is one most people finish; a tour with no exit at all is one people finish by
/// force quitting, and the app never learns they were not interested.
///
/// There are two of those exits, and they are different sizes on purpose. "Skip" ends
/// the tour you are standing in and is a tap, because it costs you one screen's worth
/// of explanation and the next tab will offer its own. "Hold to skip all" ends every
/// tour and every balloon, so it is a hold — see `HoldToSkipAll`.
struct TourBubble: View {
    let text: LocalizedStringResource
    let step: Int
    let total: Int
    /// What the confirming button says: "Next" mid-tour, "Done" at the end of the
    /// last one, and "Go to Map" at the end of one that has somewhere to send you.
    let actionTitle: String
    /// Which way the notch points, toward the target.
    let pointing: Edge
    let notchX: CGFloat
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onSkipAll: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let notchHeight: CGFloat = 10
    private let notchWidth: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            if pointing == .top { notch(up: true) }

            VStack(alignment: .leading, spacing: 11) {
                Text(text)
                    .font(.plates(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.route)
            )

            if pointing == .bottom { notch(up: false) }
        }
        .shadow(color: Theme.ink.opacity(0.28), radius: 16, y: 5)
        // Not combined into one element the way a coach mark is: this one has three
        // controls in it, and flattening them would leave a VoiceOver user with a
        // paragraph they can hear and no way to move on.
        .accessibilityElement(children: .contain)
        .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.94).combined(with: .opacity))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                // The counter, and on the way past it the only affordance that says
                // this ends. Dots were the first attempt and they stop being countable
                // at about five, which is exactly the length these tours are.
                Text("\(step) of \(total)")
                    .font(Theme.PlateFont.condensed(12))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.62))
                    .accessibilityLabel("Step \(step) of \(total)")

                Spacer(minLength: 6)

                if step > 1 {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous step")
                }

                Button(action: onNext) {
                    Text(actionTitle)
                        .font(.plates(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.route)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
            }

            // Both ways out, on their own row.
            //
            // Pushed to the two edges rather than bunched at the leading one, so the row
            // reads as a pair of columns against the row above it: the quiet word under
            // the quiet counter, the thing with an outline under the button. Bunched
            // left they were a clump with dead space beside them, and the capsule's own
            // edge had nothing to line up with.
            //
            // That does put the capsule directly under Next, which for a *tap* target
            // would be the wrong side of this trade. It is safe here for the reason the
            // control exists: a thumb that lands slightly low costs a touch that goes
            // nowhere, because nothing happens until it has stayed there for a second.
            // Distance is what protects a tap; duration is what protects this.
            HStack(spacing: 14) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.plates(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this tour")

                Spacer(minLength: 8)

                HoldToSkipAll(action: onSkipAll)
            }
        }
    }

    private func notch(up: Bool) -> some View {
        NotchShape(pointingUp: up)
            .fill(Theme.route)
            .frame(width: notchWidth, height: notchHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: notchX - notchWidth / 2)
    }

    private struct NotchShape: Shape {
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

// MARK: - Hold to skip all

/// The one control in the app that has to be held.
///
/// "Skip" leaves the tour you are standing in; this leaves all nine, and the balloons
/// with them. That asymmetry is the whole argument for the hold: undoing it means
/// finding "Replay the tour" in Settings, so it should not be reachable by the same
/// idle thumb that reaches for "Skip", and it should not be reachable at all by a
/// pocket or a passenger's elbow. A second of deliberate pressure is the cheapest
/// confirmation there is — no sheet, no "are you sure", no second decision to make.
///
/// The ring is not decoration. Without it a held finger is a finger holding a button
/// that appears broken, and people let go at about 400ms; with it the same wait reads
/// as a thing in progress, and the fill is also the instruction — it says *keep
/// holding* better than the words next to it do.
private struct HoldToSkipAll: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var countdown: Task<Void, Never>?

    /// Long enough that no accidental press reaches it, short enough that a deliberate
    /// one does not feel like it has hung. Measured against the ring rather than picked:
    /// much under a second and the fill is a flicker nobody can read as progress.
    private let hold: TimeInterval = 1.1

    private let ring: CGFloat = 17

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    // Trim starts at three o'clock; a progress ring that does not start
                    // at the top reads as a decoration that happens to be moving.
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: ring, height: ring)

            Text("Hold to skip all")
                .font(.plates(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(progress > 0 ? 0.9 : 0.55))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.white.opacity(progress > 0 ? 0.14 : 0.07))
        )
        .contentShape(Capsule())
        // A drag with no minimum distance rather than `LongPressGesture`, because the
        // half that matters here is the release. A long press reports that it began and
        // that it succeeded; a finger lifted at 700ms produces neither, so the ring
        // would sit there half full with nothing to reset it.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // A finger that has wandered off the control is no longer holding
                    // it, the same way a button cancels when you slide away.
                    if abs(value.translation.width) > 40
                        || abs(value.translation.height) > 40 {
                        release()
                    } else {
                        press()
                    }
                }
                .onEnded { _ in release() }
        )
        // A cancelled touch delivers no `onEnded`, and destroying the `@State` that
        // holds the Task does not cancel it. So a hold interrupted by an incoming
        // call, by a popup being presented, or by the bubble being rebuilt when the
        // stop changes, ran to completion with nothing on screen — and ended every
        // tour and every coach mark in the app, recoverable only from Settings.
        .onDisappear { release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skip all tours")
        .accessibilityHint("Ends the walkthrough on every screen")
        .accessibilityAddTraits(.isButton)
        // VoiceOver cannot hold anything, and a control it can only fail at is a
        // control it does not have. Activating it does what the hold does; the
        // deliberation the hold buys is already there in having to find it.
        .accessibilityAction { fire() }
    }

    private func press() {
        guard countdown == nil else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .linear(duration: hold)) { progress = 1 }
        countdown = Task {
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    private func release() {
        guard countdown != nil else { return }
        countdown?.cancel()
        countdown = nil
        withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
    }

    private func fire() {
        countdown?.cancel()
        countdown = nil
        Haptics.holdConfirmed()
        progress = 0
        action()
    }
}

// MARK: - Anchoring

struct TourTarget {
    let anchor: Anchor<CGRect>
    let prefersAbove: Bool
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [Tour.Stop: TourTarget] = [:]

    static func reduce(value: inout [Tour.Stop: TourTarget],
                       nextValue: () -> [Tour.Stop: TourTarget]) {
        // First wins, matching `CoachAnchorKey`: preference order follows view order,
        // so in a grid this is the earliest matching tile.
        value.merge(nextValue()) { existing, _ in existing }
    }
}

extension View {
    /// Marks this view as what a tour stop points at and cuts the spotlight around.
    func tourAnchor(_ stop: Tour.Stop,
                    active: Bool = true,
                    prefersAbove: Bool = false) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) {
            active ? [stop: TourTarget(anchor: $0, prefersAbove: prefersAbove)] : [:]
        }
    }

    /// Marks the container the tour scrolls to before pointing at this stop.
    ///
    /// Separate from `tourAnchor` on purpose, and usually on a different view. The
    /// anchor wants to be as tight as possible — one tile, one row — so the spotlight
    /// cuts around the actual subject. The scroll target wants to be the section that
    /// contains it, because scrolling a lazy grid to a tile that has not been realised
    /// yet does nothing at all. Putting `.id` on the tile itself would also fight the
    /// id it already carries for search.
    func tourStop(_ stop: Tour.Stop) -> some View {
        id(stop.scrollID)
    }

    /// Hosts the tour for one screen. Goes last in the screen's modifier chain.
    func tourLayer(_ screen: Tour.Screen,
                   _ copy: [Tour.Stop: LocalizedStringResource]) -> some View {
        TourLayer(screen: screen, copy: copy) { self }
    }
}

// MARK: - Scrolling

/// Drives the page from inside a `ScrollViewReader`, so each stop is on screen before
/// the bubble points at it.
///
/// This is the part that makes it a tour rather than five balloons. It lives as a
/// modifier applied *inside* the reader because a `ScrollViewProxy` is only valid
/// there, and it takes the proxy rather than reaching for one so that a screen with an
/// unusual layout can still put its reader where it needs it.
private struct TourScrolling: ViewModifier {
    @Environment(TourGuide.self) private var tour
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            // `initial` matters: the first stop is set in the same breath as the tour
            // starting, and a plain `onChange` misses it. Without this the tour opens
            // wherever the reader had already scrolled to.
            .onChange(of: tour.stop, initial: true) { _, stop in
                guard let stop else { return }
                // A frame later, so a stop that only exists because the previous one
                // expanded something has been laid out before we aim at it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.snappy(duration: 0.45)) {
                        proxy.scrollTo(stop.scrollID, anchor: stop.scrollAnchor)
                    }
                }
            }
            // The clean slate. Whatever the tour scrolled past on the way through, the
            // reader gets the top of their own screen back when it ends.
            .onChange(of: tour.restoreRequest) { _, _ in
                guard let finished = tour.restoredScreen,
                      let first = Tour.stops(of: finished).first else { return }
                withAnimation(.snappy(duration: 0.45)) {
                    proxy.scrollTo(first.scrollID, anchor: .top)
                }
            }
    }
}

extension View {
    /// Lets the running tour scroll this screen. Apply inside the `ScrollViewReader`.
    func tourScrolling(_ proxy: ScrollViewProxy) -> some View {
        modifier(TourScrolling(proxy: proxy))
    }
}

// MARK: - The layer

/// Draws the scrim, the spotlight and the bubble for whichever stop is up.
///
/// Per screen rather than at the root, for the reason `CoachLayer` documents at
/// length: the anchor and the balloon have to be measured in the same coordinate
/// space, or the first scroll leaves the bubble pointing at empty paper. Since this
/// one does the scrolling itself, that would be immediate and constant.
///
/// Unlike a coach mark, this **does** dim and **does** intercept. A tour has taken the
/// page over: it is scrolling for you, and a tap that lands on a plate tile mid-tour
/// logs a sighting nobody meant to log. The scrim is what makes the takeover honest,
/// and tapping it is a second, larger Next.
struct TourLayer<Content: View>: View {
    @Environment(TourGuide.self) private var tour
    @Environment(PopupHost.self) private var popup
    /// Only for the hand-off. The layer is the one part of this that knows a tour has
    /// ended *and* has somewhere to send the reader next.
    @Environment(Router.self) private var router

    let screen: Tour.Screen
    let copy: [Tour.Stop: LocalizedStringResource]
    @ViewBuilder var content: Content

    private let gap: CGFloat = 10
    private let margin: CGFloat = 14

    /// A deliberate over-estimate of the bubble's height, scaled for text size. Same
    /// reasoning as `CoachLayer.roomNeeded`, with more to reserve: this bubble carries
    /// two rows of controls under its sentence.
    @ScaledMetric(relativeTo: .footnote) private var roomNeeded: CGFloat = 215

    var body: some View {
        content.overlayPreferenceValue(TourAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if tour.screen == screen,
                   let stop = tour.stop,
                   let words = copy[stop],
                   popup.item == nil {
                    let target = anchors[stop].map { proxy[$0.anchor] }
                    let prefersAbove = anchors[stop]?.prefersAbove ?? false
                    stage(stop, words,
                          target: target.flatMap { onScreen($0, in: proxy.size) ? $0 : nil },
                          prefersAbove: prefersAbove,
                          in: proxy.size)
                }
            }
        }
    }

    private func onScreen(_ target: CGRect, in bounds: CGSize) -> Bool {
        target.maxY > 0 && target.minY < bounds.height && target.height > 0
    }

    /// Scrim, spotlight and bubble.
    ///
    /// `target` is optional, and the nil case is the one worth reading. A stop whose
    /// subject has not been scrolled into view yet, or which a screen decided not to
    /// draw after all, still gets its sentence — centred, with no cutout — rather than
    /// leaving the reader looking at a dimmed screen with nothing on it and no Next
    /// button to escape with. Losing the pointer is a worse tour; losing the way out
    /// is a bug report.
    @ViewBuilder
    private func stage(_ stop: Tour.Stop,
                       _ words: LocalizedStringResource,
                       target: CGRect?,
                       prefersAbove: Bool,
                       in bounds: CGSize) -> some View {
        ZStack {
            scrim(around: target, in: bounds)

            if let target {
                bubble(stop, words, target: target,
                       prefersAbove: prefersAbove, in: bounds)
            } else {
                bubble(stop, words,
                       target: CGRect(x: bounds.width / 2, y: bounds.height * 0.38,
                                      width: 0, height: 0),
                       prefersAbove: false, in: bounds)
            }
        }
    }

    /// How far past the layer's own bounds the dimming is painted.
    ///
    /// The scrim has to cover the status bar and the tab bar, and the obvious way to
    /// say that — `.ignoresSafeArea()` — is the one thing it must not do. This layer's
    /// `GeometryReader` is inset by the safe areas, every anchor rect is measured in
    /// that inset space, and expanding the view to ignore them moves the origin out
    /// from under the arithmetic: the hole lands somewhere above the thing it is meant
    /// to be cut around, by exactly the height of the status bar. Overdrawing keeps one
    /// coordinate space for the whole layer.
    private let overdraw: CGFloat = 400

    private func scrim(around target: CGRect?, in bounds: CGSize) -> some View {
        // One path with two subpaths and an even-odd fill, rather than a color plus a
        // `destinationOut` rectangle over a compositing group. Both cut a real hole;
        // this one does it without a second offscreen buffer, and a scrim that is
        // recomposited every frame of a 0.45s scroll animation is worth not having.
        Path { p in
            p.addRect(CGRect(x: -overdraw, y: -overdraw,
                             width: bounds.width + overdraw * 2,
                             height: bounds.height + overdraw * 2))
            if let target {
                p.addRoundedRect(in: target.insetBy(dx: -6, dy: -6),
                                 cornerSize: CGSize(width: 12, height: 12),
                                 style: .continuous)
            }
        }
        .fill(Theme.ink.opacity(0.55), style: FillStyle(eoFill: true))
        .contentShape(Rectangle())
        // The whole scrim is Next. Every stop still has a real button, because a
        // surface that silently advances is not discoverable, but nobody should have
        // to aim for it.
        .onTapGesture {
            Haptics.selection()
            tour.advance()
        }
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    /// Finish this stop, and if the tour is over, move the reader on.
    ///
    /// The scrim's tap goes through `TourGuide.advance` directly and so never hands
    /// off, which is deliberate: tapping the backdrop is "yes, carry on", and it should
    /// not be able to change tabs under somebody who was only trying to dismiss a
    /// bubble. Changing where you are is a decision, and decisions get the button.
    private func advance(to handoff: Tour.Screen?) {
        guard let handoff, let index = handoff.tabIndex else { return tour.advance() }
        tour.stop(restoring: true)
        withAnimation(.snappy(duration: 0.35)) { router.tab = index }
    }

    private func bubble(_ stop: Tour.Stop,
                        _ words: LocalizedStringResource,
                        target: CGRect,
                        prefersAbove: Bool,
                        in bounds: CGSize) -> some View {
        // Identical arithmetic to `CoachLayer.balloon`, and identical for a reason:
        // that placement was worked out against real screens, including the two
        // mistakes its comments record. See it for why room is judged by measurement
        // rather than by which half of the screen the target sits in, and why this
        // pins an edge instead of using `.position`.
        let roomBelow = target.maxY + gap + roomNeeded <= bounds.height
        let roomAbove = target.minY - gap - roomNeeded >= 0
        let above = prefersAbove ? roomAbove || !roomBelow : !roomBelow
        let width = min(300, bounds.width - margin * 2)
        let left = min(max(target.midX - width / 2, margin),
                       bounds.width - margin - width)
        let notchX = min(max(target.midX - left, 20), width - 20)

        // Only the final stop hands off, and only when there is a tab left to hand to.
        let handoff = tour.isLast ? tour.nextTab : nil

        return ZStack(alignment: above ? .bottomLeading : .topLeading) {
            Color.clear.allowsHitTesting(false)

            TourBubble(
                text: words,
                step: tour.step,
                total: tour.total,
                actionTitle: handoff.map { String(localized: "Go to \($0.tabName)") }
                    ?? (tour.isLast ? String(localized: "Done") : String(localized: "Next")),
                pointing: above ? .bottom : .top,
                notchX: notchX,
                onNext: { Haptics.selection(); advance(to: handoff) },
                onBack: { Haptics.selection(); tour.back() },
                onSkip: { Haptics.undo(); tour.stop(restoring: true) },
                onSkipAll: { tour.skipAll() }
            )
            .id(stop)
            .frame(width: width, alignment: .leading)
            .padding(.leading, left)
            .padding(.top, above ? 0 : max(0, target.maxY + gap))
            .padding(.bottom, above ? max(0, bounds.height - target.minY + gap) : 0)
        }
    }
}
