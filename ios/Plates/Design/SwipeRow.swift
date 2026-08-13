import SwiftUI

/// Trailing swipe actions for a card that is not in a `List`.
///
/// `.swipeActions` only exists on `List` rows, and the trips are deliberately not a
/// List — they are cards on the app's own paper, with a route-blue spine and a
/// folded corner that a List's own chrome would fight. So the gesture is rebuilt
/// here rather than the design being given up to get it.
///
/// Worth having because of what it replaces. Marking a trip done was: tap the
/// sliders, scroll the editor, tap, confirm. Four steps to say "that one's over" is
/// enough friction that nobody does it, which is how the list gets long in the first
/// place. One swipe and one tap makes tidying up cheap enough to actually happen.
/// **What the content may not be: a full-width `Button`.** A button cancels its own
/// press when the finger leaves its frame, and a row-sized button has no frame worth
/// leaving — a 78pt sideways swipe is still well inside it. The press survives the
/// whole gesture and fires on touch-up, so the swipe opens the row *and* whatever
/// tapping the row does. Neither guard below can help: the drag is simultaneous by
/// necessity, so it never wins the way an exclusive gesture would, and
/// `allowsHitTesting` does not retract a press already in flight. Give the card a
/// `.onTapGesture` instead — a tap gesture cancels on movement, which is the thing
/// actually wanted. See `TripRow`.
///
/// Declared outside `SwipeRow` rather than nested in it. A type nested in a generic
/// can only be named with the generic's arguments filled in, so `SwipeRow.Action`
/// is unspellable at the call site that has to build the array *before* the row.
struct SwipeAction: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let perform: () -> Void
}

struct SwipeRow<Content: View>: View {

    let actions: [SwipeAction]
    /// Fired when the row settles open, not when an action is chosen. The two are
    /// different facts and only one of them is "this person knows the gesture
    /// exists" — which is all the `swipeTrip` coach mark is waiting to hear.
    var onOpen: (() -> Void)?
    @ViewBuilder var content: Content

    /// Per-button width. Two buttons is the practical ceiling on a phone — three
    /// leaves less of the card showing than the actions covering it.
    private let buttonWidth: CGFloat = 78

    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0
    @GestureState private var dragging = false

    private var openWidth: CGFloat { CGFloat(actions.count) * buttonWidth }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Only while the row is actually open.
            //
            // They used to be drawn always and simply covered by the card, which
            // holds right up until the card is not opaque. The archived trips are
            // dimmed to 65%, so the Reopen button showed straight through a closed
            // row — a grey slab under the plate count with its label crossing the
            // edit button. Covering something is not the same as hiding it, and a
            // row that has not been swiped has no actions to show.
            if offset != 0 {
                buttons
                    .transition(.identity)
            }

            content
                .offset(x: offset)
                // Closing by tapping the card is the behaviour every list has, and
                // without it the only way back is an exact swipe in the other
                // direction. `highPriorityGesture` so it beats the card's own button.
                .highPriorityGesture(
                    TapGesture().onEnded { close() },
                    including: offset < 0 ? .all : .subviews
                )
        }
        // Simultaneous, not exclusive. A plain `.gesture` on a row inside a
        // ScrollView wins the drag outright and the list stops scrolling wherever
        // your thumb happens to land on a card — which is everywhere. Running
        // alongside the scroll view means vertical drags are never taken away from
        // it, and the axis check below is what stops the row sliding while you
        // scroll past it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { value in
                    // Horizontal only. Without this the row slides sideways while
                    // the list is being scrolled vertically past it.
                    guard abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    // Rubber-banding past fully open, so the row does not simply
                    // stop dead against an invisible wall.
                    let raw = settled + value.translation.width
                    offset = raw < -openWidth
                        ? -openWidth + (raw + openWidth) / 4
                        : min(0, raw)
                }
                .onEnded { value in
                    // Predicted end, not where the finger left: a quick flick should
                    // open the row even though it barely moved.
                    let projected = settled + value.predictedEndTranslation.width
                    withAnimation(.snappy(duration: 0.24)) {
                        if projected < -openWidth / 2 {
                            if settled == 0 { onOpen?() }
                            offset = -openWidth
                            settled = -openWidth
                        } else {
                            offset = 0
                            settled = 0
                        }
                    }
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.perform()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(action.title)
                            .font(.plates(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                }
                .buttonStyle(.plain)
            }
        }
        // Hidden from VoiceOver: swiping is a sighted-pointer idiom, and every one
        // of these actions is also in the trip's editor, which is where a screen
        // reader will find them laid out as ordinary buttons.
        .accessibilityHidden(true)
    }

    private func close() {
        guard offset != 0 else { return }
        withAnimation(.snappy(duration: 0.22)) {
            offset = 0
            settled = 0
        }
    }
}
