import SwiftUI

/// Every plate a jurisdiction has ever issued that anybody photographed.
///
/// The rest of the app is about the plate going past the window right now. This is
/// the other half of the same interest — the one where a kid asks why that one is
/// yellow when the others are blue, and the answer is that Delaware has been issuing
/// gold on navy since 1969.
///
/// Newest first, deliberately. A history read from the top should open on the design
/// you might actually see today and work backwards, rather than starting in 1903 and
/// making you scroll a century to reach anything you could still spot.
struct HistoricalPlatesScreen: View {
    /// Remembered, because looking up one state usually means looking up several and
    /// nobody wants to re-pick from a menu of 65 each time.
    @AppStorage("historyCode") private var code = "NY"

    @State private var designs: [PlateHistoryBook.Design] = []
    @State private var loading = true
    @State private var opened: PlateHistoryBook.Design?
    @State private var choosing = false

    private var plate: Plate? { Plate.plate(for: code) }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                picker

                if loading {
                    Spacer()
                    ProgressView().tint(Theme.inkMuted)
                    Spacer()
                } else if designs.isEmpty {
                    Spacer()
                    empty
                    Spacer()
                } else {
                    list
                }
            }
        }
        .navigationTitle("Historical plates")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: code) { await reload() }
        .sheet(item: $opened) { design in
            DesignSheet(design: design, jurisdiction: plate?.name ?? code)
        }
        .sheet(isPresented: $choosing) {
            JurisdictionPicker(code: $code)
        }
    }

    /// A megabyte of JSON is a visible stutter if it is parsed while the navigation
    /// push is animating, so the first read happens off the main thread.
    private func reload() async {
        loading = true
        let wanted = code
        let found = await Task.detached { PlateHistoryBook.designs(for: wanted) }.value
        guard wanted == code else { return }
        designs = found
        loading = false
    }

    // MARK: - Choosing a jurisdiction

    /// A button, not a menu. This was a `Menu` wrapping a `Picker` and sixty-five
    /// jurisdictions in one scrolling popover is not a control anybody can use — the
    /// list is taller than the phone, the section headers scroll away with it, and
    /// there is no way to say "Saskatchewan" other than to find it by eye. Anything
    /// past about a dozen entries wants typing, so this opens a sheet with a field
    /// in it and the same matcher the game grid uses.
    private var picker: some View {
        Button {
            choosing = true
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .bold))
                Text(plate?.name ?? code)
                    .font(.plates(size: 16, weight: .bold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.route.opacity(0.6))
            }
            .foregroundStyle(Theme.route)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jurisdiction: \(plate?.name ?? code). Change")
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - The designs

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Text(span)
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 3)

                ForEach(designs) { design in
                    Button { opened = design } label: { DesignCard(design: design) }
                        .buttonStyle(.plain)
                }

                credit
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 24)
        }
    }

    /// "84 designs, 1903–2026" — the shape of the history in one line.
    private var span: String {
        let years = designs.map(\.year).filter { $0 > 0 }
        let count = "\(designs.count) design\(designs.count == 1 ? "" : "s")"
        guard let first = years.min(), let last = years.max(), first != last else {
            return count
        }
        return "\(count), \(first)\u{2013}\(last)"
    }

    private var credit: some View {
        // The old second sentence — "Designs without a photograph are not listed" —
        // was a note about the dataset's gaps, which is a thing to tell whoever
        // builds the dataset, not somebody browsing old plates.
        Text("Photographs from Wikimedia Commons and the jurisdictions' own sites, each credited on its card.")
            .font(.plates(size: 11))
            .foregroundStyle(Theme.inkMuted.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
            Text("No photographs yet")
                .font(.plates(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Nobody has photographed a \(plate?.name ?? code) plate for Wikimedia Commons.")
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
    }
}

/// Picking one of sixty-five jurisdictions, by typing.
///
/// Only the ones that have a photograph of something. A name in this list that opens
/// onto an empty screen is a dead end you had to spell out to reach, and the count
/// beside each name is the honest version of that — it says up front how much history
/// there is to look at before you commit to the tap.
///
/// Matching is `PlateSearch`, the same thing the game grid uses, so "york" finds New
/// York without the "New", "sk" finds Saskatchewan, and past three characters the
/// appearance terms come in too — "cactus" lands on Arizona.
private struct JurisdictionPicker: View {
    @Binding var code: String
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var groups: [(String, [Plate])] {
        let all = PlateHistoryBook.jurisdictions.filter { PlateSearch.matches($0, query: query) }
        return [
            (String(localized: "States"), all.filter { $0.region == .state }),
            (String(localized: "Canada"), all.filter { $0.region == .province }),
            (String(localized: "Other"), all.filter { $0.region == .federal || $0.region == .territory }),
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { title, plates in
                    Section {
                        ForEach(plates) { plate in
                            row(plate)
                        }
                    } header: {
                        Text(title)
                            .font(.plates(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .listRowBackground(Theme.surface)
                }

                if groups.isEmpty {
                    Text("Nothing matches \u{201C}\(query)\u{201D}.")
                        .font(.plates(size: 14))
                        .foregroundStyle(Theme.inkMuted)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Jurisdiction")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "State, province, or code")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ plate: Plate) -> some View {
        Button {
            code = plate.code
            Haptics.selection()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(plate.code)
                    .font(Theme.PlateFont.condensed(15))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 30, alignment: .leading)

                Text(plate.name)
                    .font(.plates(size: 15, weight: plate.code == code ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 8)

                Text("\(PlateHistoryBook.designs(for: plate.code).count)")
                    .font(.plates(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkMuted.opacity(0.8))

                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.route)
                    .opacity(plate.code == code ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One design: the photograph, when it was issued, and what it looks like.
private struct DesignCard: View {
    let design: PlateHistoryBook.Design

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            photo
                .frame(width: 132, height: 132 / Theme.tileAspect)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // The start year and nothing else. What Wikipedia actually wrote
                    // is on the card you get by tapping this one.
                    Text(PlateDates.start(design.dates))
                        .font(Theme.PlateFont.condensed(18))
                        .foregroundStyle(Theme.ink)
                    if design.isCurrent {
                        Text("IN ISSUE")
                            .font(Theme.PlateFont.condensed(10))
                            .tracking(0.6)
                            .foregroundStyle(Theme.found)
                    }
                }

                // Clamped so the writing never outruns the plate beside it. A row
                // whose text ran to eight lines left the photograph — the thing the
                // screen is for — stranded at the top of a wall of prose.
                if !design.note.isEmpty {
                    Text(design.note)
                        .font(.plates(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkMuted.opacity(0.5))
                .padding(.top, 3)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    /// Plates are wider than they are tall and so is the frame, but a few of these
    /// are photographs of a plate on a car rather than a scan — `.fit` keeps those
    /// whole instead of cropping the plate out of its own picture.
    private var photo: some View { DesignPhoto(design: design, glyph: 15) }
}

/// The picture for one design, from whichever of the two sources it has.
///
/// Shared by the card and the full sheet so the bundled-versus-fetched split is
/// decided in one place — the alternative was the same `if let asset` in two views
/// that are easy to update singly and then quietly disagree.
struct DesignPhoto: View {
    let design: PlateHistoryBook.Design
    var glyph: CGFloat = 15

    var body: some View {
        if let asset = design.asset, let image = Self.bundled(asset) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            AsyncImage(url: design.url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    missing
                default:
                    Theme.ground
                }
            }
        }
    }

    private var missing: some View {
        ZStack {
            Theme.ground
            Image(systemName: "photo")
                .font(.system(size: glyph))
                .foregroundStyle(Theme.inkMuted.opacity(0.6))
        }
    }

    /// What has already been loaded, so scrolling does not re-read the disk.
    ///
    /// `body` runs on every layout pass, and every one of those was doing two bundle
    /// lookups and a fresh `UIImage` off a file. In a list of two hundred designs
    /// scrolled at speed that is a file read per row per frame, and the reads are the
    /// visible part — the images also stack up as separate objects the decoder has to
    /// treat as unrelated, so the same plate is decoded again each time it is built.
    ///
    /// `NSCache` rather than a dictionary because these are photographs: it hands the
    /// memory back when the system asks, which is the behaviour you want for something
    /// that can be rebuilt from a file in the app's own bundle. Misses are cached too,
    /// as a sentinel — a design naming an asset that did not ship would otherwise be
    /// the one row that keeps hitting the disk forever.
    @MainActor private static let cache = NSCache<NSString, UIImage>()
    @MainActor private static var absent: Set<String> = []

    /// Same lookup the lookup screen's photographs use: a loose file in a bundle
    /// subdirectory, with a flat fallback in case the folder reference is ever
    /// flattened by the build.
    @MainActor
    static func bundled(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard !absent.contains(name) else { return nil }
        let url = Bundle.main.url(forResource: name, withExtension: "png",
                                  subdirectory: "CurrentPlates")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let image = UIImage(contentsOfFile: url.path) else {
            absent.insert(name)
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// One design, in full: the photograph big enough to look at, everything Wikipedia
/// wrote about it, and who took the picture.
///
/// The list has to clamp its descriptions to keep the plates readable, so this is
/// where the clamped text goes rather than nowhere. It is also the only place the
/// original date range survives — "March 2022 -August 2024" is ugly on a card and
/// still worth keeping, because somebody bothered to record the month.
struct DesignSheet: View {
    @Environment(\.dismiss) private var dismiss
    let design: PlateHistoryBook.Design
    let jurisdiction: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        photo

                        if !design.note.isEmpty {
                            Text(design.note)
                                .font(.plates(size: 14))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 0) {
                            row("Issued", design.dates)
                            if design.isCurrent {
                                divider
                                row("Status", String(localized: "Still in issue"))
                            }
                            if design.isShared {
                                divider
                                row("Photograph", String(localized: "Wikipedia gives this era the design above it, so this is that plate"))
                            }
                            if !design.credit.isEmpty {
                                divider
                                row("Photographer", design.credit)
                            }
                            if !design.licence.isEmpty {
                                divider
                                row("Licence", design.licence)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .fill(Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1)
                        )
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("\(jurisdiction) \(PlateDates.start(design.dates))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var photo: some View {
        DesignPhoto(design: design, glyph: 22)
            // Restored with the shared `DesignPhoto`. Both of its placeholders used
            // to carry this; folding them into one view dropped it, and a bare
            // `Color` with only a width proposal collapses to about 10pt — so a
            // remote design on a slow connection showed a sliver, then jumped, and
            // a failed one stayed a sliver with its glyph clipped out. `DesignCard`
            // was unaffected because it sets its own frame, which is exactly why
            // this was invisible in the list.
            .aspectRatio(Theme.tileAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.plates(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
