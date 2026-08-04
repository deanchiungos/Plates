import SwiftUI

/// The filter control, sat beside the search bar.
///
/// It states its own setting rather than being a bare icon: a filter you cannot see
/// is on is indistinguishable from missing plates. When something is hidden the chip
/// carries the count that is left, which doubles as the answer to "how many more do I
/// need" — the thing you actually want to know mid-drive.
struct PlateFilterChip: View {
    let filter: PlateFilter
    let leftCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.plates(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .foregroundStyle(filter.isActive ? .white : Theme.route)
            .padding(.horizontal, label == nil ? 0 : 14)
            .frame(minWidth: 48)
            .frame(height: 48)
            .background(
                Capsule()
                    .fill(filter.isActive ? Theme.route : Theme.surface)
                    .overlay(Capsule().strokeBorder(
                        filter.isActive ? .clear : Theme.line, lineWidth: 1))
                    .shadow(color: Theme.ink.opacity(0.10), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.isActive
            ? "Filter, on. \(leftCount) plates left to find."
            : "Filter plates")
        .accessibilityHint("Choose which plates to show")
    }

    /// Nil means icon-only: with nothing filtered there is no state to report.
    private var label: String? {
        if filter.hideFound { return "\(leftCount) left" }
        guard filter.isActive else { return nil }
        if filter.sets.count == 1, let only = filter.sets.first { return only.filterLabel }
        return "\(filter.sets.count) sets"
    }
}

// MARK: - The panel

/// Lives inside the app-wide popup.
///
/// It reads `@AppStorage` itself rather than taking a binding, which is what makes it
/// work at all: `PopupHost.present` evaluates its content closure once, so a panel
/// built from values captured at presentation would show stale checkmarks forever.
/// A view that observes the store re-renders on every toggle even though its identity
/// was fixed when the popup opened.
struct PlateFilterPanel: View {
    @AppStorage(PlateFilter.key) private var filter = PlateFilter()

    /// Live counts, so each row can say how much of it you have left. Passed in
    /// because only the calling screen knows which collection is being played.
    let leftInRegion: (PlateRegion) -> Int
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            PopupChoice(title: "Only what's left",
                        subtitle: "Hide plates you have already found",
                        isSelected: filter.hideFound,
                        trailing: { Tick(on: filter.hideFound) },
                        action: {
                            filter.hideFound.toggle()
                            Haptics.selection()
                        })

            Text("SETS")
                .font(.plates(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.leading, 4)

            ForEach(PlateRegion.allCases, id: \.self) { region in
                let on = filter.includes(region)
                PopupChoice(title: region.filterLabel,
                            subtitle: on
                                ? "\(leftInRegion(region)) left of \(region.plates.count)"
                                : region.filterDetail,
                            isSelected: on,
                            trailing: { Tick(on: on) },
                            action: {
                                filter.toggle(region)
                                Haptics.selection()
                            })
            }

            if filter.isActive {
                PopupButton(title: "Show everything", kind: .quiet) {
                    filter = PlateFilter()
                    Haptics.selection()
                }
                .padding(.top, 4)
            }

            PopupButton(title: "Done", kind: .primary, action: onDone)
        }
    }
}

/// A checkbox, not a switch — these are all "is this included", and four switches in
/// a column reads as four unrelated settings.
private struct Tick: View {
    let on: Bool

    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19))
            .foregroundStyle(on ? Theme.route : Theme.line)
    }
}
