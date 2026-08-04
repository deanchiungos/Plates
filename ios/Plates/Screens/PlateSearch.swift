import SwiftUI

enum PlateSearch {

    /// Prefix matching on the code and on ANY word of the name, so "n" keeps
    /// Nebraska, Nevada, New Jersey, New York and North Carolina, while "york"
    /// and "carolina" also find their states without typing the first word.
    ///
    /// NAMES AND CODES ONLY. It used to search what the plate *looks like* too —
    /// "cactus" for Arizona — which sounds like a strict improvement and is not. This
    /// field sits above a grid of sixty-five tiles you are trying to find one of, and
    /// appearance terms turn a narrowing tool into a widening one: "green" dims forty
    /// tiles and highlights eleven, none of which is the one being looked for.
    ///
    /// Describing a plate you cannot name is a real thing to want, and it has its own
    /// screen — Plate lookup, which ranks by appearance and shows photographs. That is
    /// where the vocabulary belongs.
    static func matches(_ plate: Plate, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }

        if plate.code.lowercased().hasPrefix(q) { return true }

        let name = plate.name.lowercased()
        if name.hasPrefix(q) { return true }
        for word in name.split(whereSeparator: { $0 == " " || $0 == "-" }) {
            if word.hasPrefix(q) { return true }
        }

        return false
    }

    static func firstMatch(query: String) -> Plate? {
        Plate.all.first { matches($0, query: query) }
    }

    static func matchCount(query: String) -> Int {
        Plate.all.filter { matches($0, query: query) }.count
    }

    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One container that changes width, rather than two views swapping. A 48pt-wide
/// capsule IS a circle, so collapsed and expanded are the same shape at different
/// sizes and the morph comes for free — no crossfade, no popping.
struct PlateSearchBar<Accessory: View>: View {
    @Binding var query: String
    @Binding var isOpen: Bool
    var matchCount: Int

    /// Sits to the left of the collapsed circle and gets out of the way when the
    /// field opens — the expanded bar plus Cancel already fills the row, and search
    /// stands the filter down anyway, so a filter control would be lying there.
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var focused: Bool

    private let collapsed: CGFloat = 48

    var body: some View {
        HStack(spacing: 10) {
            if !isOpen {
                Spacer(minLength: 0)
                accessory()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.route)
                    .frame(width: 22)

                if isOpen {
                    TextField("State or code", text: $query)
                        .focused($focused)
                        .font(.plates(size: 16))
                        .foregroundStyle(Theme.ink)
                        // Was `.characters`. Forcing caps made sense when this
                        // only took two-letter codes; it fights you the moment
                        // the field also takes "cactus" or "covered bridge".
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .accessibilityLabel("Search plates by state or code")

                    if PlateSearch.isActive(query) {
                        Text("\(matchCount)")
                            .font(.plates(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkMuted)
                            .transition(.opacity)

                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.inkMuted.opacity(0.7))
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
            }
            .padding(.horizontal, isOpen ? 15 : 0)
            .frame(maxWidth: isOpen ? .infinity : collapsed)
            .frame(height: collapsed)
            .searchGlass()
            .contentShape(Capsule())
            .onTapGesture {
                guard !isOpen else { return }
                open()
            }
            .accessibilityLabel(isOpen ? "Search plates" : "Find a plate")
            .accessibilityAddTraits(isOpen ? [] : .isButton)

            if isOpen {
                Button("Cancel") { close() }
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.route)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .frame(height: 60)
        // one spring drives width, the trailing button and the field together
        .animation(.smooth(duration: 0.38, extraBounce: 0.14), value: isOpen)
        .animation(.snappy(duration: 0.2), value: PlateSearch.isActive(query))
    }

    private func open() {
        isOpen = true
        // focus after the morph starts so the keyboard does not fight the spring
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { focused = true }
    }

    private func close() {
        focused = false
        query = ""
        isOpen = false
    }
}

extension PlateSearchBar where Accessory == EmptyView {
    init(query: Binding<String>, isOpen: Binding<Bool>, matchCount: Int) {
        self.init(query: query, isOpen: isOpen, matchCount: matchCount,
                  accessory: { EmptyView() })
    }
}

private extension View {
    /// Liquid Glass on iOS 26, a plain surface capsule before that.
    @ViewBuilder
    func searchGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(
                Capsule()
                    .fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    .shadow(color: Theme.ink.opacity(0.10), radius: 6, y: 2)
            )
        }
    }
}
