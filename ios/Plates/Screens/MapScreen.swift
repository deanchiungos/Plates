import SwiftUI
import SwiftData

struct MapScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]
    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    @Environment(TourGuide.self) private var tour

    @State private var mode: Mode = .progress
    @State private var selected: String?

    /// The region the map draws a glowing ring around.
    ///
    /// Still separate from `selected` even though the two now rise and fall
    /// together, because they are cleared by different things: `selected` by the
    /// sheet's own dismissal, `highlighted` by that *and* by a tap on open water.
    /// Folding them into one property would mean the map could not deselect without
    /// also having to reason about sheet presentation.
    @State private var highlighted: String?


    /// Only set by `-mapZoom`, and only ever read by the United States map. Zoom and
    /// pan otherwise live inside each `RegionMapView`, so the two maps are separate
    /// viewports: pinching Canada must not drag the states with it.
    @State private var debugZoom: CGFloat = 1
    @State private var debugPan: CGSize = .zero

    /// Both readings of the same map. Progress answers "what is left to find";
    /// rarity answers "what is worth finding". Neither alone is the whole picture,
    /// and drawing both at once made a map that read as neither.
    private enum Mode: String, CaseIterable, Identifiable {
        case progress, rarity
        var id: String { rawValue }
        var label: String { self == .progress ? String(localized: "Found")
                                                : String(localized: "Rarity") }
    }

    /// The map reflects whatever the Drive screen is filling — a trip or a book —
    /// so the green states always match the grid you were just tapping.
    private var trip: (any PlateCollection)? {
        PlaySelection.current(kind: targetKind, tripID: currentTripID,
                              bookID: currentBookID, trips: trips, books: books)?.collection
    }

    /// Scored against the trip's route where there is one, and against the national
    /// ranking where there is not — which used to be an empty table, so every lookup
    /// below fell through to `Plate.points` and the map lost its top tier entirely on
    /// any collection without a destination pinned. See `PlateRarity.table(on:)`.
    private var rarities: [String: Int] {
        PlateRarity.table(on: trip?.route)
    }

    var body: some View {
        // Resolved once per redraw and handed down, so that nothing has to be worked
        // out again while a map is being dragged. See `MapPalette`.
        let palette = palette()

        return NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                  ScrollViewReader { scroller in
                    VStack(spacing: 14) {
                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .tourAnchor(.mapMode)
                        .tourStop(.mapMode)

                        // Canada first, which is also where it is: the provinces sit
                        // above the states on any real map of North America. Two maps
                        // rather than one joined projection because Canada's landmass
                        // is larger than the lower 48 — sharing a frame would shrink
                        // every state by about 40% to make room for tundra.
                        mapHeader("Canada",
                                  found: palette.foundCount(among: CanadaMap.codes),
                                  total: CanadaMap.codes.count)
                        canadaMap(palette)

                        mapHeader("United States",
                                  found: palette.foundCount(among: USMap.codes),
                                  total: USMap.codes.count)
                        unitedStatesMap(palette)
                            .tourAnchor(.mapRegion, prefersAbove: true)
                            .tourStop(.mapRegion)

                        // One id, not two. The tour's scroll target and `-mapSection`'s
                        // want the same view, and stacking a second `.id` on it makes
                        // which one a `ScrollViewProxy` resolves a matter of luck.
                        legend
                            .tourAnchor(.mapLegend, prefersAbove: true)
                            .tourStop(.mapLegend)

                    }
                    .tourScrolling(scroller)
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 20)
                    #if DEBUG
                    // `-mapSection legend` opens on the key, which sits two full maps
                    // below the fold and is otherwise only reachable by scrolling.
                    // (It used to aim at "logmap", an anchor that no longer exists —
                    // so the flag had quietly become a no-op.)
                    .onAppear {
                        guard ProcessInfo.processInfo.arguments.contains("-mapSection") else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                scroller.scrollTo(Tour.Stop.mapLegend.scrollID, anchor: .bottom)
                            }
                        }
                    }
                    #endif
                  }
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { tour.offer(.map, stops: Tour.stops(of: .map)) }
            .onDisappear { tour.left(.map) }
            #if DEBUG
            // `-mapMode rarity` and `-mapState VT` open states the tap gesture
            // would otherwise be the only way to reach.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let m = LaunchFlags.value(after: "-mapMode")
                    .flatMap(Mode.init(rawValue:)) { mode = m }
                // `-mapZoom 3` renders as if pinched, so the zoomed drawing can be
                // checked without a pinch gesture.
                if let z = LaunchFlags.value(after: "-mapZoom").flatMap(Double.init) {
                    debugZoom = CGFloat(z)
                    debugPan = CGSize(width: -60 * z, height: -20 * z)
                }
                if let code = LaunchFlags.value(after: "-mapState") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selected = code; highlighted = code
                    }
                }
                // `-mapHighlight ON` rings a region without opening the sheet, which
                // is the only way to actually look at the ring: the sheet covers the
                // map and dims whatever is left of it.
                if let code = LaunchFlags.value(after: "-mapHighlight") {
                    highlighted = code
                }
            }
            #endif
        }
        // Dismissing the sheet clears the ring too.
        //
        // It used to outlive the sheet on the theory that you would want to see
        // where you had just been reading. In practice the opposite is true: the
        // sheet is the selection, so closing it should end the selection, and a ring
        // left glowing on a map you have finished with is just something you now
        // have to dismiss separately.
        .sheet(item: Binding(get: { selected.map(Selection.init) },
                             set: { selected = $0?.code }),
               onDismiss: { withAnimation(.snappy(duration: 0.25)) { highlighted = nil } }) { sel in
            RegionDetail(code: sel.code,
                         trip: trip,
                         rarity: rarity(sel.code))
        }
        // Last in the chain, so the scrim covers the maps and nothing else.
        .tourLayer(.map, [
            .mapMode: "Two ways to read the map. Found shows what you have collected. Rarity colors every state by how hard it is to spot from here.",
            .mapRegion: "Tap any state or province to see its plate, how rare it is from where you are, and a fact or two about it.",
            .mapLegend: "This is the key. Legendary and mythic are the ones worth shouting about when you see them."
        ])
    }

    private struct Selection: Identifiable {
        let code: String
        var id: String { code }
    }

    private func rarity(_ code: String) -> Int {
        rarities[code] ?? Plate.plate(for: code)?.points ?? 5
    }

    // MARK: - Palette

    /// Every per-region color decision, answered once instead of once per ring per
    /// frame.
    ///
    /// `RegionMapView` is handed closures and calls them from inside its `Canvas`,
    /// once for each of the sixty-odd rings the two countries are made of, on every
    /// frame of a pan or a pinch. Those closures used to be methods on this screen,
    /// and each call re-resolved the current trip out of SwiftData and then walked
    /// its sightings to answer "found?" — plus, because `fill` computed the rarity
    /// tier before it looked at the mode, a rarity-table lookup even in Found mode.
    /// That is nothing once and ruinous sixty times a frame, and it is why dragging a
    /// zoomed map felt broken: the canvas could not redraw at anything like gesture
    /// rate, so the map sat still under your finger and then jumped to its final
    /// position when you let go. The jump was never the pan being wrong — it was the
    /// only frame that got drawn.
    ///
    /// Resolving all 65 regions up front turns every one of those calls into a hash
    /// lookup. None of the drawing changed; it just stopped being recomputed.
    private struct MapPalette {
        let fill: [String: Color]
        let stroke: [String: Color]
        let label: [String: Color]
        let found: Set<String>

        func foundCount(among codes: [String]) -> Int {
            codes.filter(found.contains).count
        }
    }

    private func palette() -> MapPalette {
        // One pass over the sightings for the whole map, rather than one per region.
        let found = trip?.seenCodes ?? []
        let table = rarities

        var fill: [String: Color] = [:]
        var stroke: [String: Color] = [:]
        var label: [String: Color] = [:]
        fill.reserveCapacity(Plate.all.count)
        stroke.reserveCapacity(Plate.all.count)
        label.reserveCapacity(Plate.all.count)

        // The outline is a plain dark edge on every region, found or not. It used to
        // be the rarity tier's color at a thickness that varied by tier, which made
        // the map carry two answers at once — how much is left, and what is worth
        // finding — and read as neither. Rarity has its own mode; Found can just be
        // found.
        //
        // Selection is not decided here — it is a separate ring drawn on top by the
        // map itself, because it has to sit on the boundary rather than inside it.
        for plate in Plate.all {
            let code = plate.code
            switch mode {
            case .progress:
                let isFound = found.contains(code)
                // Found used to be one green for everything, with rarity carried by
                // the animated outline alone. That put the whole reward in a border a
                // few points wide — on Rhode Island, essentially nowhere. A collected
                // epic, legendary or mythic region now wears its own color, so the
                // thing you earned is the size of the state rather than the size of
                // its edge. Everything below epic stays green, and *nothing* uncollected
                // changes: an unfound mythic plate is the same sand as an unfound
                // common one, because the map still must not tell you what to chase.
                let tier = RarityTier.forRarity(table[code] ?? plate.points)
                let lit = isFound && tier >= .epic
                fill[code] = lit ? tier.mapFill : (isFound ? Theme.found : Theme.unfound)
                stroke[code] = Theme.ink.opacity(0.45)
                // Green is dark enough to need white on it. The tier fills are not —
                // pale gold and lilac take white badly — so those keep ink.
                label[code] = (isFound && !lit) ? .white : Theme.ink
            case .rarity:
                // Rarity only. Varying this by found-state as well meant two signals
                // fighting over one fill, and the map read as neither — which is what
                // the Found mode is there for.
                let tier = RarityTier.forRarity(table[code] ?? plate.points)
                fill[code] = tier.mapFill
                stroke[code] = Theme.route.opacity(0.30)
                label[code] = Theme.ink
            }
        }
        return MapPalette(fill: fill, stroke: stroke, label: label, found: found)
    }

    /// Thickness of the band, in points, scaled to the drawn size so the map looks
    /// the same on a phone and an iPad.
    ///
    /// Uniform now. It used to vary by rarity tier in Found mode, which meant a
    /// found state had no outline at all while its unfound neighbour had a heavy
    /// colored one — the border between two regions changed weight depending on
    /// which side you had collected, and the map looked ragged rather than
    /// informative.
    ///
    private func bandWidth(_ code: String, _ size: CGSize) -> CGFloat {
        let unit = max(size.width / 340, 0.85)
        return mode == .progress ? 1.0 * unit : 1.5 * unit
    }

    // MARK: - Maps

    /// The Northeast, plus DC — a few points across at phone size and effectively
    /// impossible to see or hit.
    private static let usCallouts = ["VT", "NH", "MA", "RI", "CT", "NJ", "DE", "MD", "DC"]

    /// The Maritimes. P.E.I. is under ten points wide at phone size; New Brunswick
    /// and Nova Scotia clear that but land well under a finger's width, and calling
    /// out two of three while leaving the third on the map read as an oversight.
    /// North to south, so the leader lines never cross.
    private static let canadaCallouts = ["NB", "PE", "NS"]

    private func unitedStatesMap(_ palette: MapPalette) -> some View {
        RegionMapView<USMap>(
            calloutCodes: Self.usCallouts,
            fill: { palette.fill[$0] ?? Theme.unfound },
            stroke: { palette.stroke[$0] ?? Theme.line },
            bandWidth: bandWidth,
            labelColor: { palette.label[$0] ?? Theme.ink },
            onSelect: { code in
                withAnimation(.snappy(duration: 0.25)) { highlighted = code }
                selected = code
            },
            highlighted: highlighted,
            accessibilityTitle: "Map of the United States",
            foundCount: palette.foundCount(among: USMap.codes),
            spotlight: spotlight,
            initialZoom: debugZoom,
            initialPan: debugPan
        )
    }

    private func canadaMap(_ palette: MapPalette) -> some View {
        RegionMapView<CanadaMap>(
            calloutCodes: Self.canadaCallouts,
            fill: { palette.fill[$0] ?? Theme.unfound },
            stroke: { palette.stroke[$0] ?? Theme.line },
            bandWidth: bandWidth,
            labelColor: { palette.label[$0] ?? Theme.ink },
            onSelect: { code in
                withAnimation(.snappy(duration: 0.25)) { highlighted = code }
                selected = code
            },
            highlighted: highlighted,
            accessibilityTitle: "Map of Canada",
            foundCount: palette.foundCount(among: CanadaMap.codes),
            // Rarity mode only.
            //
            // In Rarity mode every province is at least rare from anywhere in the
            // States, so every one asks for the heavy end of the band at once, and on
            // a coastline as jagged as the Arctic's that reads as outline rather than
            // land. Half thickness fixes that.
            //
            // In Found mode there is nothing to fix. The band is a plain hairline
            // there, the same on every region — so halving it only made Canada's
            // borders visibly finer and paler than the identical borders on the map
            // directly below it, which reads as one map being drawn wrong rather than
            // as a deliberate difference. Two maps of the same thing on the same
            // screen have to share a line weight.
            spotlight: spotlight,
            bandScale: mode == .progress ? 1 : 0.5
        )
    }

    /// Which regions the map should light up, and how brightly.
    ///
    /// Two conditions, and the second one is the whole design. **Epic or better**,
    /// because a third of the map is rare from any given spot and a third of the map
    /// glowing is not a highlight, it is weather. And **collected**, because the
    /// animation is a reward rather than a signpost: it says "look what you got", not
    /// "go and get this". An uncollected mythic plate sits as still as Kansas.
    ///
    /// The same rule in both modes on purpose. Found mode used to strip rarity out
    /// entirely — the argument being that a map answering "how much is left" and
    /// "what is worth finding" at once answers neither. Gating on *found* settles
    /// that: nothing here tells you what to chase, so the two answers cannot fight.
    private func spotlight(_ code: String) -> RarityTier? {
        guard let trip, trip.seenCodes.contains(code) else { return nil }
        let tier = RarityTier.forRarity(rarities[code] ?? Plate.plate(for: code)?.points ?? 5)
        return tier >= .epic ? tier : nil
    }

    /// Names each map and carries its own count. With one map the navigation title
    /// said everything; with two, an unlabelled pair of outlines makes you work out
    /// which country you are looking at and which total belongs to it.
    private func mapHeader(_ title: LocalizedStringKey, found: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.plates(size: 16, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(found) / \(total)")
                .font(.plates(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.top, 2)
    }

    // MARK: - Legend

    /// One entry in the key: the color, and the word for what it means.
    private struct Key: Identifiable {
        let id: String
        let color: Color
        let label: String
    }

    /// What the map is currently painted with. Not what it used to be painted with.
    ///
    /// This drifted, and a wrong key is worse than no key. Found mode signalled rarity
    /// with a colored outline once; that outline was removed — every region now takes
    /// a plain dark edge — but the key kept listing all six tiers as thin colored
    /// lines, so it named a channel the map no longer has. Worse, it implied common,
    /// uncommon and rare were three different colors out there when all three are
    /// simply green, and that grey was a tier rather than "not found yet".
    ///
    /// So each mode describes itself, and both read their swatch straight off the
    /// same `mapFill` the regions are drawn with.
    private var keys: [Key] {
        let tiers = [RarityTier.common, .uncommon, .rare, .epic, .legendary, .mythic]
        switch mode {
        case .rarity:
            // Every region is filled by tier, so all six belong.
            return tiers.map { Key(id: $0.label, color: $0.mapFill,
                                   label: $0.label.capitalized) }
        case .progress:
            // Two states plus the three tiers that keep their own color when found.
            // Common, uncommon and rare are all just green here, so listing them
            // separately would invent three distinctions the map does not draw.
            return [Key(id: "unfound", color: Theme.unfound, label: "Not found"),
                    Key(id: "found", color: Theme.found, label: "Found")]
                + tiers.filter { $0 >= .epic }.map {
                    Key(id: $0.label, color: $0.mapFill, label: $0.label.capitalized)
                }
        }
    }

    private var legend: some View {
        // Six across on a phone is tight, so the gap gives way before the labels do.
        HStack(spacing: 6) {
            ForEach(keys) { key in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(key.color)
                        .frame(height: 9)
                    Text(key.label)
                        .font(.plates(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 2)
    }

}

// MARK: - Detail

/// What one region looks like up close: its plate, where it sits on this trip's
/// rarity scale, and the trivia you have unlocked so far.
struct RegionDetail: View {
    @Environment(\.dismiss) private var dismiss

    let code: String
    let trip: (any PlateCollection)?
    let rarity: Int

    private var plate: Plate? { Plate.plate(for: code) }
    private var tier: RarityTier { RarityTier.forRarity(rarity) }
    private var isFound: Bool { plate.map { trip?.hasSeen($0) ?? false } ?? false }

    private var seen: [String] { FactBook.seenFacts(for: code) }
    private var total: Int { FactBook.total(for: code) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        facts
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle(plate?.name ?? code)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let plate {
                PlateTile(plate: plate, isFound: isFound, rarity: rarity)
                    .frame(width: 108)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tier.label)
                    .font(Theme.PlateFont.condensed(24))
                    .foregroundStyle(tier.color)

                Text("Rarity \(rarity) of 10\(trip?.route == nil ? "" : " on this trip")")
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)

                Label(isFound ? "Spotted" : "Not yet spotted",
                      systemImage: isFound ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isFound ? Theme.found : Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var facts: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: "Facts", detail: "\(seen.count) of \(total)")

            if seen.isEmpty {
                // Phrased to be true whether or not the plate is already collected —
                // a plate can be found with nothing unlocked, and "spot this plate"
                // reads as a contradiction next to a green Spotted badge.
                Text("Facts unlock as you spot this plate. Every sighting reveals a new one.")
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surface))
            }

            ForEach(Array(seen.enumerated()), id: \.offset) { _, fact in
                Text(fact)
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surface))
            }

            // Locked slots are shown rather than hidden: knowing three more exist is
            // what makes spotting the same plate again worth doing.
            ForEach(0..<max(0, total - seen.count), id: \.self) { _ in
                HStack(spacing: 9) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                    Text("Locked")
                        .font(.plates(size: 12.5, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}
