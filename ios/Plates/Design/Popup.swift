import SwiftUI
import Observation

/// A single, app-wide popup slot.
///
/// The system's `confirmationDialog` slides an action sheet up from the bottom
/// edge, which on a phone puts the choices under your thumb but a long way from
/// whatever you were looking at. Every one of these prompts is *about* something
/// on screen — the plate you just tapped, the player you are removing — so they
/// read better centred over it.
///
/// It lives at the root, above the tab bar, so a popup is never boxed inside one
/// tab's layout. The one thing it cannot cover is a `sheet`: UIKit presents those
/// in their own window, above this layer. Dismiss the sheet first and present the
/// popup from `onDismiss`.
@MainActor
@Observable
final class PopupHost {

    struct Item: Identifiable {
        let id = UUID()
        /// Already-resolved `Text` rather than the words themselves, so the two
        /// `present` overloads below can decide *how* a string becomes text —
        /// through the String Catalog, or as-is — and the card need not care.
        let title: Text
        let message: Text?
        let dismissOnScrimTap: Bool
        let content: AnyView
    }

    var item: Item?

    /// The content closure is evaluated once, at presentation. That is deliberate
    /// — these prompts are decisions about a fixed set of options, and a list that
    /// reshuffled itself under your thumb would be worse than a stale one.
    ///
    /// `LocalizedStringKey` and not `String`, which is the whole reason this file
    /// changed: the compiler harvests every `LocalizedStringKey` literal into the
    /// String Catalog, and harvests nothing at all from a `String`. Every popup in
    /// the app used to be invisible to `Localizable.xcstrings` for exactly that
    /// reason — a hundred-odd sentences that could not be reworded without going
    /// back into the source. Interpolation still works and is in fact better here:
    /// `"Remove \(plate.name)?"` becomes the key `"Remove %@?"`, one catalog entry
    /// covering all sixty-five plates.
    func present(_ title: LocalizedStringKey,
                 message: LocalizedStringKey? = nil,
                 dismissOnScrimTap: Bool = true,
                 @ViewBuilder content: () -> some View) {
        // A closure, not `Text.init`: the bare initializer reference resolves to
        // the generic `StringProtocol` overload, which a key does not satisfy.
        show(Text(title), message.map { Text($0) }, dismissOnScrimTap, content)
    }

    /// For a title that is somebody's data rather than the app's words — a plate
    /// name, a trip name. Passing one of those as a key would look it up in the
    /// catalog, so a book called "Cancel" would come out translated.
    func present(verbatim title: String,
                 message: LocalizedStringKey? = nil,
                 dismissOnScrimTap: Bool = true,
                 @ViewBuilder content: () -> some View) {
        show(Text(verbatim: title), message.map { Text($0) }, dismissOnScrimTap, content)
    }

    private func show(_ title: Text,
                      _ message: Text?,
                      _ dismissOnScrimTap: Bool,
                      @ViewBuilder _ content: () -> some View) {
        // Stacked here rather than in the layer: an `AnyView` wrapping a tuple of
        // buttons is one opaque child to whatever contains it, so the spacing has
        // to be applied on this side of the erasure.
        item = Item(title: title,
                    message: message,
                    dismissOnScrimTap: dismissOnScrimTap,
                    content: AnyView(VStack(spacing: 8) { content() }))
        Haptics.popup()
    }

    func dismiss() { item = nil }
}

// MARK: - The layer

struct PopupLayer: View {
    let host: PopupHost

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let item = host.item {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if item.dismissOnScrimTap { host.dismiss() }
                        }
                        .transition(.opacity)

                    // A fresh card per item, so the height it measured for the last
                    // popup does not carry into the next one.
                    PopupCard(item: item, ceiling: geo.size.height * 0.8)
                        .id(item.id)
                        .transition(.scale(scale: 0.90).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.snappy(duration: 0.26, extraBounce: 0.06), value: host.item?.id)
    }
}

/// The card itself, which grows with its content and then stops.
///
/// It used to just grow. That is fine for a two-button confirmation and broken for
/// a list: the trip switcher builds one row per trip, and somewhere around ten trips
/// the card was taller than the phone. The rows in the middle were fine — the two
/// buttons at the *bottom*, "New trip" and "New book", were off the screen entirely
/// with no way to scroll to them.
///
/// So the content scrolls, but only once it has to. A ScrollView takes every point
/// it is offered, which would stretch a two-button popup to the full height of the
/// display, so its height is pinned to what the content actually measures and the
/// ceiling does the clamping.
private struct PopupCard: View {
    let item: PopupHost.Item
    /// Most of the screen, not all of it: a card that reaches both edges stops
    /// reading as something sitting *over* the app.
    let ceiling: CGFloat

    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    /// Card padding above and below, plus the gap under the header. Card chrome is
    /// the one part of the height that is not measured, because it is fixed.
    private static let chrome: CGFloat = 20 + 20 + 18

    /// The tallest the scrolling part may be: whatever is left of the ceiling once
    /// the title, the message and the padding have taken their share.
    private var scrollCeiling: CGFloat {
        max(140, ceiling - headerHeight - Self.chrome)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                item.title
                    .font(.plates(size: 17, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                if let message = item.message {
                    message
                        .font(.plates(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }

            ScrollView {
                item.content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = $0
                    }
            }
            // A *fixed* height, not a cap, and this is the whole trick. `maxHeight`
            // leaves a ScrollView flexible, so it still swelled to fill the card and
            // the card swelled to fill the ceiling — a six-row popup came up with a
            // hand's width of empty paper above and below it. Pinned to exactly what
            // the content measures, clamped to what is left of the screen, the card
            // has no slack to take up and hugs its content again.
            .frame(height: contentHeight > 0 ? min(contentHeight, scrollCeiling) : nil)
            // No rubber-banding on a popup that is not actually scrolling.
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, 18)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.30), radius: 28, y: 12)
        )
        .padding(.horizontal, 32)
    }
}

// MARK: - Buttons

/// The standard full-width popup button. Kept here rather than at each call site
/// so every popup in the app has the same hit target and the same weights.
struct PopupButton: View {
    enum Kind { case primary, destructive, quiet }

    /// Every button in the app says one of about thirty fixed things — "Cancel",
    /// "Remove it", "Keep them". A key, so all thirty are in the String Catalog.
    let title: LocalizedStringKey
    var kind: Kind = .quiet
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.plates(size: 15.5, weight: kind == .quiet ? .medium : .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(PopupPressStyle())
    }

    private var foreground: Color {
        switch kind {
        case .primary:     return .white
        case .destructive: return .red
        case .quiet:       return Theme.inkMuted
        }
    }

    private var background: Color {
        switch kind {
        case .primary:     return Theme.route
        case .destructive: return Color.red.opacity(0.11)
        case .quiet:       return Theme.ground
        }
    }
}

/// A pickable row inside a popup — a player, a trip. The leading dot carries the
/// identity color so "who spotted it" can be answered by color alone.
struct PopupChoice<Trailing: View>: View {
    /// Resolved `Text`, because these rows carry both kinds of words: "Stack
    /// everything" is the app talking and belongs in the catalog, while the trip
    /// named "Cape Cod" in the switcher below it is the reader's own. The two
    /// initialisers underneath are the fork; nothing else has to know.
    let title: Text
    var subtitle: Text?
    var dotColor: Color?
    var dotInitial: String?
    var isSelected: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    init(title: LocalizedStringKey,
         subtitle: LocalizedStringKey? = nil,
         dotColor: Color? = nil,
         dotInitial: String? = nil,
         isSelected: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing,
         action: @escaping () -> Void) {
        self.init(text: Text(title), subtitle: subtitle.map { Text($0) },
                  dotColor: dotColor, dotInitial: dotInitial,
                  isSelected: isSelected, trailing: trailing, action: action)
    }

    init(verbatimTitle: String,
         verbatimSubtitle: String? = nil,
         dotColor: Color? = nil,
         dotInitial: String? = nil,
         isSelected: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing,
         action: @escaping () -> Void) {
        self.init(text: Text(verbatim: verbatimTitle),
                  subtitle: verbatimSubtitle.map { Text(verbatim: $0) },
                  dotColor: dotColor, dotInitial: dotInitial,
                  isSelected: isSelected, trailing: trailing, action: action)
    }

    private init(text: Text,
                 subtitle: Text?,
                 dotColor: Color?,
                 dotInitial: String?,
                 isSelected: Bool,
                 @ViewBuilder trailing: @escaping () -> Trailing,
                 action: @escaping () -> Void) {
        self.title = text
        self.subtitle = subtitle
        self.dotColor = dotColor
        self.dotInitial = dotInitial
        self.isSelected = isSelected
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text(dotInitial ?? "")
                                .font(Theme.PlateFont.condensed(14))
                                .foregroundStyle(Theme.ink)
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.plates(size: 15.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        subtitle
                            .font(.plates(size: 11.5))
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.ground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isSelected ? Theme.route : .clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PopupPressStyle())
    }
}

extension PopupChoice where Trailing == EmptyView {
    init(title: LocalizedStringKey,
         subtitle: LocalizedStringKey? = nil,
         dotColor: Color? = nil,
         dotInitial: String? = nil,
         isSelected: Bool = false,
         action: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, dotColor: dotColor,
                  dotInitial: dotInitial, isSelected: isSelected,
                  trailing: { EmptyView() }, action: action)
    }

    init(verbatimTitle: String,
         verbatimSubtitle: String? = nil,
         dotColor: Color? = nil,
         dotInitial: String? = nil,
         isSelected: Bool = false,
         action: @escaping () -> Void) {
        self.init(verbatimTitle: verbatimTitle, verbatimSubtitle: verbatimSubtitle,
                  dotColor: dotColor, dotInitial: dotInitial,
                  isSelected: isSelected, trailing: { EmptyView() }, action: action)
    }
}

private struct PopupPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
