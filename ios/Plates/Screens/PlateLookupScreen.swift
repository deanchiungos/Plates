import SwiftUI

/// Describe a plate you saw; get back the ones that look like that.
///
/// The photograph is the answer, not the text. Someone using this has already
/// seen the plate and is trying to recognise it again, so the job is to put
/// candidate pictures in front of them fast — the description underneath is
/// there to confirm a hunch, not to be read first.
struct PlateLookupScreen: View {
    var initialQuery: String = ""

    @State private var query = ""
    @State private var selected: PlateLookup.Design?
    @FocusState private var focused: Bool

    /// Starters, for the blank state. Chosen to show the range of what works:
    /// an object, a colour, a landscape, an era.
    /// Deliberately *not* localised, and the only user-facing text in the app that
    /// is deliberately left out of the String Catalog.
    ///
    /// Tapping one of these puts it in the search field verbatim, and the corpus it
    /// searches — `PlateLookup.designs`, built from the plate-history CSV — is
    /// written in English. Translating the chip would translate the query with it
    /// and every one of these eight would return nothing. Making them searchable in
    /// another language means translating the corpus first, which is a much larger
    /// job than translating a label.
    private let starters = ["lighthouse", "cactus", "covered bridge", "palm tree",
                            "yellow with a bison", "mountains at sunset",
                            "green gradient", "1970s"]

    @State private var expanded: Set<String> = []
    /// Held in state rather than recomputed in `body`. As a computed property it
    /// ran a 400-result search twice per evaluation — once for the empty check
    /// and once for the list — on every keystroke.
    @State private var groups: [PlateLookup.Group] = []

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                field

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    blank
                } else if groups.isEmpty {
                    noResults
                } else {
                    results
                }
            }
        }
        .navigationTitle("Plate lookup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { PlateDesignDetail(design: $0) }
        .onAppear { if query.isEmpty { query = initialQuery } }
        .onChange(of: query) {
            groups = PlateLookup.grouped(query)
            // A new search should not inherit the last one's open rows.
            expanded.removeAll()
            #if DEBUG
            // `-expandFirst` opens the top group, which is otherwise a tap away
            // and so unreachable from a launch argument.
            if ProcessInfo.processInfo.arguments.contains("-expandFirst"),
               let first = groups.first {
                expanded.insert(first.code)
            }
            // `-openFirst` presents the detail sheet for the top result, which
            // is otherwise a tap away.
            if ProcessInfo.processInfo.arguments.contains("-openFirst"),
               let first = groups.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    selected = first.best
                }
            }
            #endif
        }
    }

    // MARK: - Field

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.route)

            // Deliberately not `.characters`: this field takes sentences, not
            // codes. Autocorrection stays on — "lighthosue" should still work.
            // Short enough to survive the field. The old placeholder listed what
            // to type and then truncated halfway through the list, which is a
            // worse instruction than none; the list lives under the field now,
            // where it has the room to be read.
            TextField("Describe the plate you saw", text: $query)
                .font(.plates(size: 16))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($focused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkMuted.opacity(0.7))
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            Capsule().fill(Theme.surface)
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        )
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: - States

    private var blank: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Saw a plate you couldn't name?")
                    .font(.plates(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)

                // Written as instructions, not as a description of the feature.
                // The old copy said what the database contained; nobody standing
                // in front of an empty search box needs to know that. What they
                // need to know is what counts as a valid thing to type.
                VStack(alignment: .leading, spacing: 9) {
                    Text("Type whatever you remember about it. Any of these work:")
                    // One key, newlines and all. Split across five `+` fragments it
                    // was five `String`s the catalog never saw; as one literal it is
                    // a single entry a translator can reorder and re-bullet.
                    Text("""
                         • a color, like blue or orange and black
                         • something drawn on it, like a lighthouse or mountains
                         • a word printed on it, like Vacationland
                         • roughly when it was from, like 1970s
                         • the state or province name, if you got that much
                         """)
                    Text("Mixing them works best: green plate with a lighthouse. Tap any result to see the photo big, alongside every other plate that state has issued.")
                }
                .font(.plates(size: 14))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

                Text("TRY ONE")
                    .font(Theme.PlateFont.condensed(12))
                    .tracking(1)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 2)

                FlowChips(items: starters) { chip in
                    query = chip
                    focused = false
                }

                Text("\(PlateLookup.designs.count) designs, current and historic, each with a photograph.")
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted.opacity(0.75))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.screenPadding)
        }
    }

    private var noResults: some View {
        // Naming the word that failed matters. "loon" and "moose" find nothing
        // because no plate description contains them — that is a gap in the
        // descriptions, not a search that broke, and an empty screen reads as
        // the latter.
        let unknown = PlateLookup.unknownTerms(in: query)
        return VStack(spacing: 8) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.inkMuted.opacity(0.6))
            Text("Nothing matched that")
                .font(.plates(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)

            if !unknown.isEmpty {
                // The joined list is built first so the sentence around it is one
                // key rather than three fragments glued together at runtime.
                Text("No plate description mentions \(unknown.map { "“\($0)”" }.joined(separator: " or ")).")
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
            }

            Text("Try a color, something drawn on it, or a word printed on it.")
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            Spacer()
        }
        .padding(.horizontal, 40)
        // Without this the Spacers have no height to expand into — the stack
        // collapses to nothing and the message renders as a blank screen, which
        // is the exact failure it exists to prevent.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(groups) { group in
                    PlateGroupCard(
                        group: group,
                        isExpanded: expanded.contains(group.code),
                        onToggle: {
                            withAnimation(.snappy(duration: 0.22)) {
                                if expanded.contains(group.code) {
                                    expanded.remove(group.code)
                                } else {
                                    expanded.insert(group.code)
                                }
                            }
                        },
                        onSelect: { selected = $0 }
                    )
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - Group card

/// One jurisdiction. Collapsed it shows the variant that matched; expanded it
/// lists every other design of that place that also matched.
private struct PlateGroupCard: View {
    let group: PlateLookup.Group
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (PlateLookup.Design) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button { onSelect(group.best) } label: {
                PlateResultRow(design: group.best,
                               variantCount: group.variants.count,
                               isExpanded: isExpanded,
                               onDisclosure: group.isSingle ? nil : onToggle)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(group.variants.filter { $0.key != group.best.key }) { design in
                    Divider().padding(.leading, 14)
                    Button { onSelect(design) } label: {
                        PlateVariantRow(design: design)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}

/// "This one is on the road right now", said without saying it.
///
/// It used to be a capsule reading CURRENT, which is a label explaining a fact
/// the picture could carry on its own, and it sat there shouting on a screen
/// that is meant to be looked at rather than read. A filled dot is the same
/// signal every recording light and every online-status indicator uses, and on a
/// list ordered newest-first it lands on the top row where you would expect it
/// anyway.
///
/// Just the dot. It had a soft ring around it for a while and the halo read as a
/// glow — an animation caught mid-pulse, or something asking to be tapped. The
/// dot alone says the same thing and sits still while it says it.
struct LiveDot: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.found)
            .frame(width: size, height: size)
            // The outer frame stays the size the halo used to be. It is what the
            // timeline rail spaces its nodes by, and the hollow node opposite it
            // reserves exactly this much — shrink it and the years either side of
            // the current design sit closer together than all the others.
            .frame(width: size * 2.1, height: size * 2.1)
            .accessibilityHidden(true)
    }
}

/// The other designs of a jurisdiction, under the one that matched.
private struct PlateVariantRow: View {
    let design: PlateLookup.Design

    var body: some View {
        HStack(spacing: 12) {
            PlatePhoto(key: design.key)
                .frame(width: 78, height: 39)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                // The span carries it. "2014 – 2016" has ended and "2016 – now"
                // has not, which is the whole of what a CURRENT badge was
                // saying — using a line that had to be on the row anyway rather
                // than a second ornament beside it.
                Text(PlateDates.range(design.years))
                    .font(.plates(size: 13, weight: .bold))
                    .foregroundStyle(design.isCurrent ? Theme.ink : Theme.inkMuted)
                    .lineLimit(1)
                Text(design.graphics.isEmpty ? design.base : design.graphics)
                    .font(.plates(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PlateDates.range(design.years)
            + (design.isCurrent ? ", in use today" : ""))
    }
}

// MARK: - Row

private struct PlateResultRow: View {
    let design: PlateLookup.Design
    var variantCount: Int = 1
    var isExpanded: Bool = false
    /// Nil when the jurisdiction has only the one matching design, so a row
    /// with nothing to reveal gets no control suggesting otherwise.
    var onDisclosure: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            PlatePhoto(key: design.key)
                .frame(width: 112, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(design.jurisdiction)
                    .font(.plates(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(PlateDates.range(design.years))
                    .font(.plates(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)

                // The graphic is what someone remembers, so it is the line that
                // gets the room — falling back to the base colour when a design
                // has no picture on it at all.
                Text(design.graphics.isEmpty ? design.base : design.graphics)
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)

            if let onDisclosure {
                Button(action: onDisclosure) {
                    VStack(spacing: 2) {
                        Text("\(variantCount)")
                            .font(.plates(size: 12, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Theme.route)
                    .frame(width: 34, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.route.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded
                    ? "Hide the other \(variantCount - 1) designs"
                    : "Show all \(variantCount) designs")
            }
        }
        .padding(10)
        .contentShape(Rectangle())
    }
}

/// A bundled plate photograph, or a labelled placeholder if one is missing.
struct PlatePhoto: View {
    let key: String

    var body: some View {
        if let image = PlateLookup.photo(key) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Theme.line.opacity(0.5))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.inkMuted.opacity(0.6))
                )
        }
    }
}

// MARK: - Detail

/// The plate, big, and almost nothing else.
///
/// The written description used to be here — caption, background, lettering,
/// graphics, the quoted legends. All of it is gone deliberately. Someone opening
/// this has already seen the plate through a car window and is asking one
/// question: *is this the one?* That is answered by looking, and a paragraph
/// about sheeting and terminals is in the way of looking. The description still
/// earns its keep — it is what the search matches against — it just does not
/// need to be read.
struct PlateDesignDetail: View {
    let design: PlateLookup.Design
    @Environment(\.dismiss) private var dismiss

    /// Which design is in the big frame. Tapping one on the timeline swaps it
    /// up here rather than pushing another screen, because the question being
    /// asked is "which of these was it?" and that is answered by flicking
    /// between them in one place.
    @State private var shown: PlateLookup.Design

    init(design: PlateLookup.Design) {
        self.design = design
        _shown = State(initialValue: design)
    }

    /// Every design this jurisdiction has used, current first and then newest
    /// down to oldest.
    ///
    /// All of them, including the one in the frame. A timeline with a gap where
    /// the design you are looking at should be does not read as a timeline; it
    /// reads as a list that lost something.
    private var history: [PlateLookup.Design] {
        PlateLookup.designs(for: design.code)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlatePhoto(key: shown.key)
                        .aspectRatio(2, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1)
                        )
                        .id(shown.key)
                        .transition(.opacity)

                    header

                    if history.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EVERY \(design.jurisdiction.uppercased()) DESIGN")
                                .font(Theme.PlateFont.condensed(12))
                                .tracking(1)
                                .foregroundStyle(Theme.inkMuted)

                            // A timeline rather than a stack of thumbnails. The
                            // stack answered "what else is there" and nothing
                            // else, which left a lot of white space doing no
                            // work; a rail running down the years puts each
                            // design somewhere, shows how long the gaps between
                            // redesigns were, and gives the live marker a top
                            // of the line to sit on.
                            VStack(spacing: 0) {
                                ForEach(Array(history.enumerated()), id: \.element.id) {
                                    index, other in
                                    TimelineRow(
                                        design: other,
                                        isFirst: index == 0,
                                        isLast: index == history.count - 1,
                                        isShown: other.key == shown.key,
                                        onTap: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                shown = other
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    credit
                }
                .padding(Theme.screenPadding)
                .padding(.bottom, 12)
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shown.jurisdiction)
                .font(.plates(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
            // No marker beside it. The span itself ends in "now" when the design
            // is still being issued, which says the same thing without adding a
            // second thing to look at — and the timeline below has the dot.
            Text(PlateDates.range(shown.years))
                .font(.plates(size: 14, weight: .bold))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shown.jurisdiction + ", " + PlateDates.range(shown.years)
            + (shown.isCurrent ? ", in use today" : ""))
    }

    /// Who took the photograph. Most of these are Wikimedia Commons uploads
    /// under CC BY or CC BY-SA, and naming the photographer is a condition of
    /// using them, not a courtesy — so it goes on the screen the photograph is
    /// on, not in a settings page nobody opens.
    @ViewBuilder
    private var credit: some View {
        if let attribution = shown.attribution {
            Text("Photo: \(attribution)")
                .font(.plates(size: 11))
                .foregroundStyle(Theme.inkMuted.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }
}

/// One design on the jurisdiction's timeline.
private struct TimelineRow: View {
    let design: PlateLookup.Design
    let isFirst: Bool
    let isLast: Bool
    let isShown: Bool
    let onTap: () -> Void

    private let thumbHeight: CGFloat = 68

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                rail

                PlatePhoto(key: design.key)
                    .frame(width: thumbHeight * 2, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isShown ? Theme.route : Theme.line,
                                          lineWidth: isShown ? 2 : 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(PlateDates.range(design.years))
                        .font(.plates(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    // How long the look lasted, which is the question a timeline
                    // invites and the raw date string buried. It replaced a
                    // second copy of the same span written out in full.
                    if let duration = PlateDates.duration(design.years) {
                        Text(duration)
                            .font(.plates(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PlateDates.range(design.years)
            + (design.isCurrent ? ", in use today" : "")
            + (isShown ? ", shown above" : ""))
    }

    /// The line down the years, with this design's marker on it. Two half
    /// segments rather than one full-height line so the rail can stop at the
    /// first and last node instead of running off into the padding.
    private var rail: some View {
        VStack(spacing: 0) {
            segment(hidden: isFirst)
            node
            segment(hidden: isLast)
        }
        .frame(width: 18)
    }

    private func segment(hidden: Bool) -> some View {
        Rectangle()
            .fill(hidden ? Color.clear : Theme.line)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var node: some View {
        if design.isCurrent {
            LiveDot(size: 8)
        } else {
            Circle()
                .fill(Theme.ground)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Theme.inkMuted.opacity(0.55), lineWidth: 2))
                .frame(width: 16.8, height: 16.8)
        }
    }
}

// MARK: - Chips

/// Wrapping row of tappable suggestions. SwiftUI has no flow layout before
/// `Layout`, and this needs to work as a plain wrap without measuring text.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.plates(size: 13, weight: .medium))
                        .foregroundStyle(Theme.route)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.route.opacity(0.11)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
