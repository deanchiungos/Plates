import SwiftUI

/// A list of things to pick from inside a popup, with a search field once the list
/// gets long enough to need one.
///
/// Every screen that asks "which trip?" was building its own `ForEach` of rows, and
/// every one of them was fine at three trips and useless at twenty: the switcher, the
/// book picker, the Trail's scope menu. Scrolling a list of twenty near-identical
/// names to find "Cape Cod" is not picking, it is hunting. One component so that
/// fixing it fixes all of them, and so the threshold is one number rather than three.
///
/// The search field appears past `threshold` and not before. A search box over four
/// items is clutter that also implies the list is longer than it looks.
struct PopupPicker: View {

    struct Entry: Identifiable {
        let id: UUID
        let title: String
        var subtitle: String?
        /// The number on the right — states found, usually. Nil draws nothing.
        var count: Int?
        var isSelected: Bool = false
        /// Extra words that should match a search without being shown, so typing a
        /// destination finds the trip that goes there.
        var keywords: String = ""
        let action: () -> Void
    }

    struct Group: Identifiable {
        let id = UUID()
        /// Nil for a group that needs no heading — a single ungrouped list.
        var title: String?
        var entries: [Entry]
        /// Show only this many until asked for the rest. Nil shows everything.
        ///
        /// Most switches are back to something used in the last few days, so a long
        /// list is mostly rows nobody is reading. Showing the recent handful and
        /// keeping the rest one tap away costs the common case nothing and stops the
        /// popup being a scroll.
        var collapseTo: Int?
    }

    let groups: [Group]
    /// How many entries there have to be before a search field is worth the room.
    var threshold: Int = 10

    @State private var query = ""
    @State private var expanded: Set<UUID> = []
    @FocusState private var searching: Bool

    private var total: Int { groups.reduce(0) { $0 + $1.entries.count } }
    private var showsSearch: Bool { total > threshold }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Groups with non-matching entries removed, and empty groups dropped so a
    /// heading never sits above nothing.
    ///
    /// Carries the *original* group alongside its surviving entries rather than
    /// rebuilding it. A rebuilt `Group` mints a fresh `id`, which would both churn
    /// the `ForEach` identity on every keystroke and lose track of which groups the
    /// reader had expanded.
    private var filtered: [(group: Group, entries: [Entry])] {
        groups.compactMap { group in
            guard !trimmed.isEmpty else { return (group, group.entries) }
            let kept = group.entries.filter { entry in
                (entry.title + " " + (entry.subtitle ?? "") + " " + entry.keywords)
                    .lowercased()
                    .contains(trimmed)
            }
            return kept.isEmpty ? nil : (group, kept)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsSearch { field }

            if filtered.isEmpty {
                Text("Nothing called \u{201C}\(query)\u{201D}")
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            ForEach(filtered, id: \.group.id) { group, matches in
                if let title = group.title {
                    Text(title)
                        .font(.plates(size: 9.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }

                let shown = visible(matches, in: group)

                ForEach(shown) { entry in
                    PopupChoice(
                        title: entry.title,
                        subtitle: entry.subtitle,
                        isSelected: entry.isSelected,
                        trailing: {
                            if let count = entry.count {
                                Text("\(count)")
                                    .font(Theme.PlateFont.condensed(19))
                                    .monospacedDigit()
                                    .foregroundStyle(entry.isSelected ? Theme.route : Theme.inkMuted)
                            }
                        },
                        action: entry.action
                    )
                }

                if shown.count < matches.count {
                    Button {
                        let id = group.id
                        withAnimation(.snappy(duration: 0.22)) { expanded.insert(id) }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Show all \(matches.count)")
                                .font(.plates(size: 13, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Theme.route)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The entries actually drawn: everything while searching or once expanded,
    /// otherwise the first `collapseTo`.
    ///
    /// Whatever is currently selected is always among them. Collapsing the list so
    /// that the thing you are already on is hidden makes the popup look like it has
    /// forgotten what you picked.
    private func visible(_ matches: [Entry], in group: Group) -> [Entry] {
        guard let limit = group.collapseTo,
              trimmed.isEmpty,
              !expanded.contains(group.id),
              matches.count > limit
        else { return matches }

        var shown = Array(matches.prefix(limit))
        if let selected = matches.first(where: \.isSelected),
           !shown.contains(where: { $0.id == selected.id }) {
            shown[shown.count - 1] = selected
        }
        return shown
    }

    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)

            TextField("Search \(total)", text: $query)
                .font(.plates(size: 14))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkMuted.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            Capsule().fill(Theme.ground)
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        )
    }
}
