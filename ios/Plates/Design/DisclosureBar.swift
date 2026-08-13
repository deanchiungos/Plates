import SwiftUI

/// A collapsed section's header: glyph, label, an optional count, and a chevron
/// that turns.
///
/// Three of these grew independently at the bottom of the Trips tab — Finished,
/// Archived and Compare trips — and no two of them agreed. Different type sizes,
/// two chevrons on the left and one on the far right, one wrapped in padding the
/// others did not have. They do the same job and sit within a thumb's width of each
/// other, so three treatments read as three unrelated controls rather than one list
/// of sections.
///
/// The chevron rotates rather than swapping symbol. A glyph that turns tells you
/// which way the section is about to move; a `chevron.up` replaced by a
/// `chevron.down` just blinks.
struct DisclosureBar: View {
    let symbol: String
    let title: LocalizedStringKey
    /// Nil where there is nothing worth counting — "Compare trips" is not a pile of
    /// anything, it is a view of one.
    var count: Int?
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.plates(size: 13, weight: .semibold))
                if let count {
                    Text("\(count)")
                        .font(.plates(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkMuted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Spacer()
            }
            .foregroundStyle(Theme.inkMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }
}
