import CloudKit
import SwiftUI
import SwiftData

/// The coin book — read-only on purpose.
///
/// This screen is the shelf, not the counter. Checking a plate off happens on the
/// Drive screen, where the book you are filling is the same one-tap grid a trip
/// uses; here you look at what you have got. Two reasons for the split: an album
/// you can edit from the display case is a spreadsheet, and more practically, a
/// stray tap on a 65-tile grid should never be able to fabricate a find in the
/// permanent record.
///
/// Empty slots are drawn recessed rather than blank, because an album's empty
/// pressings are what make you want to fill them — a grid of white rectangles reads
/// as "not loaded yet", a debossed slot reads as "missing".
struct CollectionScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup
    @Environment(Router.self) private var router

    @Query private var sightings: [Sighting]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]
    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    /// The all-time lens. A view, not a container — you cannot collect into it, and
    /// switching to it deliberately does *not* change what the Drive screen fills.
    @Environment(TourGuide.self) private var tour

    @State private var allTime = false
    /// The one-pager, rendered on tap — see `ShareSheet`.
    @State private var poster: PosterToShare?
    @State private var preparingPoster = false
    @State private var selected: String?
    @State private var creatingBook = false
    @State private var editingBook: Book?

    /// Acted on after the editor sheet closes: the popup layer lives at the root and
    /// a sheet is presented above it, so confirming from inside the sheet shows
    /// nothing at all.
    @State private var pending: Pending?

    private enum Pending {
        case clear(Book)
        case delete(Book)
    }

    // MARK: - Scope

    /// Whichever book is yours. Read straight from `currentBookID` rather than
    /// through `PlaySelection`, because the Book tab shows a book even while the
    /// Drive screen is busy with a trip.
    private var currentBook: Book? {
        books.first { $0.id.uuidString == currentBookID } ?? books.first
    }

    /// With no books at all there is nothing to scope to, so the lens is forced on.
    private var showingAllTime: Bool { allTime || books.isEmpty }

    private var scopeName: String { showingAllTime ? "All time" : (currentBook?.name ?? "") }

    /// The share this book is part of, if any. Read from the local ledger, so the
    /// header draws correctly before any network call has finished — or ever.
    private var sharedEntry: SharedBookLedger.Entry? {
        guard let book = currentBook else { return nil }
        return SharedBookLedger.shared.entry(for: book.id)
    }

    /// Everyone with a plate in this book. Reuses the same scoping the standings
    /// strip uses, so a shared book counts people the same way a party trip does.
    private var contributors: [Player] {
        guard let book = currentBook else { return [] }
        return book.participants(from: players, me: DevicePlayer.resolve(from: players))
    }

    private var scoped: PlateBook {
        PlateBook(sightings: showingAllTime ? sightings : (currentBook?.allSightings ?? []))
    }

    /// Every sighting ever, whatever book or trip it came from. This is the promise
    /// that makes starting a new book safe, so it is computed from the store rather
    /// than accumulated anywhere.
    private var lifetime: PlateBook { PlateBook(sightings: sightings) }

    /// Is the Drive screen currently filling the book on display?
    private var isFillingThisBook: Bool {
        !showingAllTime && targetKind == "book" && currentBook != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                  ScrollViewReader { scroller in
                    VStack(spacing: 14) {
                        bookPage
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 24)
                    .tourScrolling(scroller)
                  }
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.large)
            // Signed out of iCloud is the one cause of a silent no-sync that the user
            // can fix, so it is worth one round trip to distinguish it from "waiting".
            .task { await CloudBackup.shared.checkAccount() }
            .onAppear { tour.offer(.books, stops: Tour.stops(of: .books)) }
            .onDisappear { tour.left(.books) }
            .toolbar {
                // Sharing what is on screen, rather than making people open the
                // editor to reach it. This tab *is* the collection; the album you are
                // looking at is the thing you would want to send somebody.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        preparingPoster = true
                        Task {
                            poster = await renderPoster()
                            preparingPoster = false
                        }
                    } label: {
                        if preparingPoster {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .tint(Theme.route)
                    .disabled(preparingPoster)
                    .accessibilityLabel(showingAllTime
                                        ? "Share your all-time collection"
                                        : "Share this book")
                    .tourAnchor(.booksShare)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creatingBook = true } label: { Image(systemName: "plus") }
                        .tint(Theme.route)
                        .accessibilityLabel("Start a new book")
                }
            }
            #if DEBUG
            //   -bookScope alltime       open on the all-time lens
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-bookScope"), i + 1 < args.count {
                    allTime = args[i + 1] == "alltime"
                }
            }
            #endif
        }
        .sheet(item: Binding(get: { selected.map(Pick.init) },
                             set: { selected = $0?.code })) { pick in
            BookEntryDetail(code: pick.code,
                            entry: scoped.entry(for: pick.code),
                            elsewhere: lifetime.entry(for: pick.code),
                            scopeName: scopeName)
        }
        .sheet(item: $poster) { ready in
            ShareSheet(items: ready.activityItems)
        }
        .sheet(isPresented: $creatingBook) {
            BookEditor(book: nil, onClear: nil, onDelete: nil)
        }
        .sheet(item: $editingBook, onDismiss: runPending) { book in
            BookEditor(
                book: book,
                onClear: { pending = .clear(book); editingBook = nil },
                onDelete: { pending = .delete(book); editingBook = nil }
            )
        }
        .tourLayer(.books, [
            .booksScope: "A book never ends. This says which one you are looking at, and Switch moves between your books and every plate you have ever logged.",
            .booksShare: "Turns whatever is on screen into a poster you can send to anyone.",
            .booksAlbum: "The album itself. Every slot you have filled keeps the date you filled it, so tapping one tells you where you were."
        ])
    }

    private struct Pick: Identifiable {
        let code: String
        var id: String { code }
    }

    /// Whatever the screen is currently showing — the book, or the all-time lens.
    /// The button shares what you are looking at, which is the only behaviour that
    /// needs no explaining.
    private func renderPoster() async -> PosterToShare? {
        if showingAllTime { return ShareablePoster.poster(allTime: lifetime) }
        guard let book = currentBook else { return nil }
        return await ShareablePoster.poster(for: book, players: players)
    }

    // MARK: - Book

    @ViewBuilder
    private var bookPage: some View {
        let b = scoped

        scopeCard
            .tourAnchor(.booksScope)
            .tourStop(.booksScope)

        summary(b)

        backupRow

        if books.isEmpty {
            Button { creatingBook = true } label: {
                dashedRow("Start a book", symbol: "plus")
            }
        } else if !showingAllTime, !isFillingThisBook {
            // The link back to the counter. Without it, "start a new book" leaves
            // you looking at empty slots with no visible way to begin filling them.
            Button {
                guard let book = currentBook else { return }
                PlaySelection.select(.book(book))
                Haptics.selection()
                // And actually go there. Selecting the book without moving tabs left
                // you on the same page of empty slots, which reads as the button
                // having done nothing — the whole promise is on the Game tab.
                router.showGame()
            } label: {
                dashedRow("Add plates to this Book", symbol: "car.fill")
            }
        }

        section("States", Plate.states, b)
            .tourAnchor(.booksAlbum)
            .tourStop(.booksAlbum)
        section("Bonus", Plate.bonus, b)
        section("Canada", Plate.provinces, b)
    }

    /// Whether the collection above this row exists anywhere but this phone.
    ///
    /// Sat directly under the totals on purpose. A lifetime book is the one thing in
    /// the app that cannot be re-earned — a trip you lose is a drive you already took,
    /// but a book is years — so "27 of 50 states" and "is that safe?" belong to each
    /// other. It stays quiet when the answer is yes and gets loud when it is no, which
    /// is the only weighting that does not train people to ignore it.
    private var backupRow: some View {
        let state = CloudBackup.shared.state
        let good = state.isHealthy

        return HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .font(.system(size: 17))
                .foregroundStyle(good ? Theme.found : Theme.paint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.plates(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(state.detail)
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(good ? Theme.surface : Theme.paint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(good ? Theme.line : Theme.paint.opacity(0.45),
                                      lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    /// Which book you are looking at, and the way to change it. Same tap-to-switch
    /// affordance as the Drive screen's header, so the gesture transfers.
    private var scopeCard: some View {
        ScopeCard(
            kind: showingAllTime ? "EVERY PLATE EVER"
                                 : (sharedEntry == nil ? "BOOK" : "SHARED BOOK"),
            isShared: sharedEntry != nil,
            name: scopeName,
            subtitle: scopeSubtitle,
            // Everyone who has put a plate in this book. Drawn from the local rows
            // rather than from `CKShare.participants`, so it is right offline and
            // needs no round trip to render a header — a contributor exists locally
            // the moment one of their sightings has arrived, which is exactly when
            // they are worth showing.
            contributors: (!showingAllTime && sharedEntry != nil && contributors.count > 1)
                ? contributors : [],
            isFilling: isFillingThisBook,
            onSwitch: showScopeSwitcher,
            onEdit: (!showingAllTime && currentBook != nil)
                ? { editingBook = currentBook } : nil)
    }

    private var scopeSubtitle: String {
        if showingAllTime {
            return "Across every book and trip"
        }
        guard let book = currentBook else { return "" }
        return isFillingThisBook
            ? "\(book.sinceLabel) \u{00B7} filling now"
            : book.sinceLabel
    }

    private func dashedRow(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.plates(size: 14.5, weight: .semibold))
        }
        .foregroundStyle(Theme.route)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.route.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }

    private func summary(_ b: PlateBook) -> some View {
        HStack(spacing: 0) {
            stat("\(b.statesFound)", "of \(Plate.stateTotal) states")
            divider
            stat("\(b.totalFound)", "of \(Plate.all.count) total")
            divider
            stat("\(b.totalSightings)", "plates logged")
        }
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 2)
        )
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.PlateFont.condensed(26))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.plates(size: 10.5))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 26)
    }

    /// One page of the album.
    ///
    /// The grid sits on a page rather than straight on the screen, which is the whole
    /// difference between this tab and the Game tab. Two testers said the same thing
    /// in different words — "it feels like you can play from that tab" and "make the
    /// Book tab look more unique" — and both are about the same cause: an identical
    /// grid of identical tiles on an identical background, where one collects on tap
    /// and one does not.
    ///
    /// Deleting the grid was the suggested fix and is the wrong one. The filled album
    /// is the reward for collecting; what needed changing is that it looked like the
    /// counter. So: a leaf of paper, and every plate mounted on it with corners.
    private func section(_ title: LocalizedStringKey, _ plates: [Plate], _ b: PlateBook) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: title, detail: "\(b.found(in: plates)) / \(plates.count)")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.tileMinWidth,
                                             maximum: Theme.tileMaxWidth),
                                   spacing: Theme.gridGap)],
                spacing: Theme.gridGap
            ) {
                ForEach(plates) { plate in
                    let entry = b.entry(for: plate.code)
                    Button {
                        selected = plate.code
                    } label: {
                        BookSlot(plate: plate, entry: entry)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.line.opacity(0.9), lineWidth: 1)
                    )
            )
        }
        .padding(.top, 4)
    }

    // MARK: - Switching

    private func showScopeSwitcher() {
        let entries = books.map { candidate in
            PopupPicker.Entry(
                id: candidate.id,
                title: candidate.name,
                subtitle: candidate.sinceLabel,
                count: candidate.statesFound,
                isSelected: !showingAllTime && candidate.id == currentBook?.id,
                action: {
                    // Only the book pointer moves. Switching what you are reading
                    // must not yank the Drive screen off a trip that is still
                    // running.
                    PlaySelection.selectBookOnly(candidate)
                    allTime = false
                    Haptics.selection()
                    popup.dismiss()
                }
            )
        }

        popup.present("Which book?",
                      message: "This changes the book you are looking at, and the one you collect into.") {
            PopupPicker(groups: [PopupPicker.Group(entries: entries)])

            PopupChoice(title: "All time",
                        subtitle: "Every plate ever, across all books and trips",
                        isSelected: showingAllTime) {
                allTime = true
                Haptics.selection()
                popup.dismiss()
            }

            PopupButton(title: "New book", kind: .primary) {
                popup.dismiss()
                creatingBook = true
            }
        }
    }

    // MARK: - Destructive actions

    private func runPending() {
        guard let pending else { return }
        self.pending = nil

        switch pending {
        case .clear(let book):
            let count = book.platesFound
            let hasFolded = book.allSightings.contains { $0.trip != nil }
            popup.present(
                "Empty \(book.name)?",
                // Two whole messages rather than one with a clause appended. A
                // key built by `+` is not a literal, so the compiler cannot see
                // it and the catalog never learns it exists.
                message: hasFolded
                    ? "^[\(count) plate](inflect: true) will be removed from this book and from your all-time count. The book itself stays. Plates folded in from trips go back to their trips and stay in your history."
                    : "^[\(count) plate](inflect: true) will be removed from this book and from your all-time count. The book itself stays."
            ) {
                PopupButton(title: "Empty book", kind: .destructive) {
                    PlateLogger.withdraw(book.allSightings, from: book, context: context)
                    Haptics.destructive()
                    popup.dismiss()
                }
                PopupButton(title: "Keep them") { popup.dismiss() }
            }

        case .delete(let book):
            let count = book.platesFound
            popup.present(
                "Delete \(book.name)?",
                message: count == 0
                    ? "The book is removed. Nothing else changes."
                    : "The book is removed, but its ^[\(count) plate](inflect: true) stay in your all-time count. You did see them. Empty it first if you want them gone."
            ) {
                PopupButton(title: "Delete book", kind: .destructive) {
                    let wasCurrent = book.id.uuidString == currentBookID
                    context.delete(book)
                    try? context.save()
                    // Fall through to whichever book remains rather than pointing at
                    // one that no longer exists.
                    if wasCurrent { currentBookID = "" }
                    Haptics.destructive()
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }
        }
    }
}

// MARK: - Scope card

/// The header of the Book tab: what you are looking at, who has contributed to it,
/// and the two ways to change it.
///
/// Its own view rather than a slice of `CollectionScreen` for one reason beyond
/// tidiness — it is the widest four-column row in the app (name, subtitle, four
/// faces, an edit circle), and a row that cannot be handed values cannot be drawn
/// at a width and a text size that break it. See `LayoutStress`, which does exactly
/// that and is what put the accessibility reflow below here.
struct ScopeCard: View {
    /// The small caps line: BOOK, SHARED BOOK, EVERY PLATE EVER.
    let kind: String
    let isShared: Bool
    let name: String
    let subtitle: String
    /// Empty when there is nobody to show; the stack is only worth its width when
    /// more than one person has filled the book.
    var contributors: [Player] = []
    let isFilling: Bool
    let onSwitch: () -> Void
    /// Nil on All time, which is not a book and has nothing to edit.
    var onEdit: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Two trailing controls, one trailing edge. Previously SWITCH was pinned to
        // the trailing edge of the *inner* button, which stops short of the card
        // wherever the edit circle sits — so it floated in from the edge and lined up
        // with nothing. Hoisting it to its own full-width row puts both controls flush
        // right, in a clean stack: label above, circle below.
        VStack(alignment: .leading, spacing: 3) {
            kindRow

            // At accessibility sizes the name is set in a font roughly twice this
            // one, and the faces and the edit circle grow with it: three columns
            // that all still want the same line leave the name a few letters. The
            // controls drop to their own row instead, which costs height — the one
            // thing a reader at that size has plenty of, since the screen is
            // already scrolling.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    title
                    HStack(spacing: 10) {
                        avatars
                        Spacer(minLength: 0)
                        editButton
                    }
                }
            } else {
                HStack(spacing: 10) {
                    title
                    avatars
                    editButton
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(isFilling ? Theme.route : Theme.line,
                                  lineWidth: isFilling ? 1.5 : 1))
        )
    }

    private var kindRow: some View {
        Button(action: onSwitch) {
            HStack(spacing: 5) {
                Text(kind)
                    .font(.plates(size: 10, weight: .bold))
                    .tracking(1.2)
                    // SHARED BOOK at an accessibility size is wide enough on its
                    // own to push SWITCH off the card, and a switch control you
                    // cannot see is a book you cannot leave. It wrapped mid-word
                    // — "SHARE / D BOOK" — before this, on the 320pt phone.
                    //
                    // 0.6 rather than a smaller floor because 0.6 of an
                    // accessibility size is still larger than the 10pt this is set
                    // at by default: the label shrinks relative to the reader's
                    // choice without ever going below what everyone else sees.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if isShared {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.found)
                        .accessibilityLabel("Shared")
                }
                Spacer(minLength: 8)
                Text("SWITCH")
                    .font(.plates(size: 9.5, weight: .bold))
                    .tracking(0.9)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(Theme.route)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: some View {
        Button(action: onSwitch) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.plates(size: 18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatars: some View {
        if !contributors.isEmpty {
            AvatarStack(players: contributors, limit: 4, size: 22,
                        background: Theme.surface)
        }
    }

    /// Centred on the name and date rather than on the whole card, so it sits under
    /// SWITCH instead of drifting up against it.
    @ViewBuilder
    private var editButton: some View {
        if let onEdit {
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.ground))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(name)")
        }
    }
}

// MARK: - Slot

/// The paper triangles a plate is held onto the page by.
///
/// The one detail that makes the difference between a grid and an album, and it has
/// to be *only* on this screen — a mounted plate reads as something already put
/// away, which is exactly what the Game grid must not look like.
///
/// Both along the top edge, not on a diagonal. The diagonal is the prettier mount
/// and it put a triangle exactly where the repeat count and the claimant faces go —
/// the badge won, being the more important thing, and the corner became a smudge
/// behind it. Four corners is a scrapbook and eats the state name at 60pt across.
private struct PhotoCorners: View {
    var size: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            ZStack {
                corner
                    .position(x: size / 2, y: size / 2)
                corner
                    .rotationEffect(.degrees(90))
                    .position(x: geo.size.width - size / 2, y: size / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private var corner: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: size, y: 0))
            path.addLine(to: CGPoint(x: 0, y: size))
            path.closeSubpath()
        }
        .fill(Theme.ink.opacity(0.22))
        .frame(width: size, height: size)
    }
}

/// One page of the album. Filled shows the plate; empty shows the pressing it goes
/// into — recessed, with the code ghosted so you know what is missing.
private struct BookSlot: View {
    let plate: Plate
    let entry: PlateBook.Entry?

    var body: some View {
        ZStack {
            if entry != nil {
                PlateTile(plate: plate, isFound: true)
                    .overlay(PhotoCorners())
            } else {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(
                        Theme.slot.shadow(
                            .inner(color: .black.opacity(0.28), radius: 4, x: 0, y: 2))
                    )
                    .aspectRatio(Theme.tileAspect, contentMode: .fit)
                    .overlay(
                        Text(plate.code)
                            .font(Theme.PlateFont.condensed(17))
                            .foregroundStyle(Theme.ink.opacity(0.22))
                    )
            }

            // The corner mark. Who beats how many: a plate several people claimed is
            // a story about the car, and a ×4 told that story as though one person
            // had driven past the same state four times.
            if let entry, entry.spotters.count > 1 {
                corner { AvatarStack(players: entry.spotters, limit: 3, size: 15) }
            } else if let entry, entry.count > 1 {
                corner {
                    Text("\u{00D7}\(entry.count)")
                        .font(.plates(size: 8.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.ink.opacity(0.55)))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.name)
        .accessibilityValue(spokenState)
    }

    /// Bottom-right of the tile, whatever is going there.
    private func corner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                content()
            }
        }
        .padding(4)
    }

    private var spokenState: String {
        guard let entry else { return "Not collected" }
        if entry.spotters.count > 1 {
            return "Collected by \(entry.spotters.map(\.name).formatted(.list(type: .and)))"
        }
        return "Collected, seen \(entry.count) time\(entry.count == 1 ? "" : "s")"
    }
}

// MARK: - Detail

/// A plate up close: when it arrived, how often since, and the trivia unlocked so
/// far. Read-only, like the page it opens from.
private struct BookEntryDetail: View {
    @Environment(\.dismiss) private var dismiss

    let code: String
    /// This plate within the book being viewed.
    let entry: PlateBook.Entry?
    /// The same plate across everything ever logged — what tells an empty slot apart
    /// from a plate you have genuinely never seen.
    let elsewhere: PlateBook.Entry?
    let scopeName: String

    private var plate: Plate? { Plate.plate(for: code) }
    private var seen: [String] { FactBook.seenFacts(for: code) }
    private var total: Int { FactBook.total(for: code) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            if let plate {
                                PlateTile(plate: plate, isFound: entry != nil)
                                    .frame(width: 112)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                if let entry {
                                    label("First spotted",
                                          entry.firstSeen.formatted(.dateTime.month(.abbreviated)
                                              .day().year()))
                                    if let t = entry.firstIn { label("On", t) }
                                    label("Seen", "\(entry.count) time\(entry.count == 1 ? "" : "s")")
                                } else if let elsewhere {
                                    label("Not in \(scopeName)", "collected before")
                                    label("First spotted",
                                          elsewhere.firstSeen.formatted(.dateTime.month(.abbreviated)
                                              .day().year()))
                                } else {
                                    label("Status", "not collected")
                                }
                            }
                            Spacer(minLength: 0)
                        }

                        if entry == nil {
                            Text("Tap a plate on the Game tab to collect it.")
                                .font(.plates(size: 12.5))
                                .foregroundStyle(Theme.inkMuted)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            SectionHeader(title: "Facts", detail: "\(seen.count) of \(total)")
                            // Said plainly, because there was no way to work it out.
                            // A tester could not tell how facts were unlocked, and
                            // the app had never once mentioned that spotting the
                            // plate again is the whole of the mechanism.
                            if seen.count < total {
                                Text(seen.isEmpty
                                     ? "Spot this plate to read one."
                                     : "Spot it again for the next one.")
                                    .font(.plates(size: 12))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            ForEach(Array(seen.enumerated()), id: \.offset) { _, fact in
                                Text(fact)
                                    .font(.plates(size: 13.5))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(13)
                                    .background(RoundedRectangle(cornerRadius: 12,
                                                                 style: .continuous)
                                        .fill(Theme.surface))
                            }
                            ForEach(0..<max(0, total - seen.count), id: \.self) { _ in
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill").font(.system(size: 10.5))
                                    Text("Locked").font(.system(size: 12.5, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(Theme.inkMuted.opacity(0.7))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.line,
                                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            }
                        }
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

    private func label(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(key.uppercased())
                .font(.plates(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(.plates(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Editor

/// Create and rename share a sheet, as trips and players do. Not private — the
/// Drive screen offers "New book" from its switcher.
///
/// Short by design: a book has a name and nothing else to configure. No route,
/// because it is not a journey; no scoring mode, because scoring a lifetime
/// collection against a route it never had would be inventing a number.
struct BookEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let book: Book?
    let onClear: (() -> Void)?
    let onDelete: (() -> Void)?

    @Query(sort: \Player.joinedAt) private var players: [Player]

    @State private var name = ""
    @FocusState private var focused: Bool
    /// The one-pager, rendered on tap rather than in `body` — see `ShareSheet`.
    /// Distinct from `sharing`, which is the CloudKit invitation: one hands somebody
    /// a picture, the other hands them write access.
    @State private var poster: PosterToShare?
    @State private var preparingPoster = false
    @State private var sharing: SharePayload?
    @State private var shareTrouble: String?
    @State private var preparingShare = false

    private var isNew: Bool { book == nil }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("BOOK NAME")
                                .font(.plates(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.inkMuted)

                            TextField("My Plate Book", text: $name)
                                .focused($focused)
                                .font(.plates(size: 17))
                                .submitLabel(.done)
                                .onSubmit(save)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 12,
                                                                  style: .continuous)
                                            .strokeBorder(Theme.line, lineWidth: 1))
                                )
                        }

                        Text(isNew
                             ? "A book keeps going. There is no route and no finish line; you just add plates to it, on a road trip or on the way to work. Starting one never touches the books you already have."
                             : "Collect into this book from the Game tab.")
                            .font(.plates(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        if let book, !isNew { stats(book) }
                        if let book, !isNew { sharingSection(book) }
                        if !isNew { dangerZone }

                        Spacer(minLength: 8)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .sheet(item: $poster) { ready in
                ShareSheet(items: ready.activityItems)
            }
            .sheet(item: $sharing) { payload in
                CloudShareSheet(share: payload.share,
                                container: payload.container) { sharing = nil }
            }
            .navigationTitle(isNew ? "New book" : "Edit book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Sharing lives where iOS puts sharing. It spent one commit at the
                // bottom of the sheet next to Empty and Delete, which is both the
                // wrong neighbourhood for a harmless action and far enough down that
                // the person who asked for the feature could not find it.
                if let book, !isNew {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            preparingPoster = true
                            Task {
                                poster = await ShareablePoster.poster(for: book, players: players)
                                preparingPoster = false
                            }
                        } label: {
                            if preparingPoster {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .tint(Theme.route)
                        .disabled(preparingPoster)
                        .accessibilityLabel("Share this book")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Start" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            name = book?.name ?? ""
            if isNew { focused = true }
        }
    }

    private func stats(_ book: Book) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(book.statesFound) of \(Plate.stateTotal) states")
                    .font(.plates(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(book.sinceLabel)
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }

    @ViewBuilder
    private var dangerZone: some View {
        VStack(spacing: 8) {
            if let onClear {
                Button(action: onClear) {
                    rowLabel("Empty this book", symbol: "eraser", tint: .red)
                }
            }
            if let onDelete {
                Button(action: onDelete) {
                    rowLabel("Delete book", symbol: "trash", tint: .red)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.plates(size: 15, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
    }

    private func save() {
        guard !trimmed.isEmpty else { return }

        if let book {
            book.name = trimmed
        } else {
            let fresh = Book(name: trimmed)
            context.insert(fresh)
            // A book you just started is a book you want to fill, so it becomes what
            // the Drive screen is collecting into.
            PlaySelection.select(.book(fresh))
        }

        try? context.save()
        dismiss()
    }
}

// MARK: - Sharing a book

extension BookEditor {

    /// Inviting somebody to fill this book with you.
    ///
    /// Deliberately here rather than on the party screen. A party is the car you are
    /// in; this is a standing arrangement with somebody who might be three states
    /// away, and the two have almost nothing in common beyond both involving another
    /// person. Putting them together would suggest they work the same way.
    @ViewBuilder
    func sharingSection(_ book: Book) -> some View {
        let entry = SharedBookLedger.shared.entry(for: book.id)

        VStack(alignment: .leading, spacing: 9) {
            Text(entry == nil ? "SHARE" : "SHARED")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            if let entry {
                Text(entry.isOwner
                     ? "You are sharing this book. Anything they add appears here, and anything you add appears for them."
                     : "You are filling this book with its owner. It lives in their iCloud. If they stop sharing it, your copy of the plates stays on this phone.")
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(entry.isOwner ? "Stop sharing" : "Leave this book") {
                    Task {
                        shareTrouble = nil
                        SharedBookSync.shared.clearTrouble()
                        await SharedBookSync.shared.stopSharing(book)
                        // Only if it worked. A revoke that failed leaves the book
                        // shared and says so below; confirming it with the haptic
                        // for a destructive action would be the app telling you it
                        // did something it did not do.
                        if SharedBookSync.shared.trouble == nil { Haptics.destructive() }
                    }
                }
                .font(.plates(size: 15, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.10)))
            } else {
                Text("Invite somebody to fill this book with you. You both add plates to the same book, from wherever you are.")
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    prepareShare(for: book)
                } label: {
                    HStack(spacing: 7) {
                        if preparingShare {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(preparingShare ? "Preparing\u{2026}" : "Share this book")
                            .font(.plates(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.route)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.route.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .disabled(preparingShare)
            }

            // The sync's own last complaint, not only this sheet's. Everything that
            // fills a shared book is fire-and-forget — a push, a withdrawal, a pull
            // on foreground — and `trouble` was the only record any of them left.
            // Nothing read it outside the one catch below, so "sign in to iCloud"
            // sat in a property while the book quietly stopped syncing.
            if let trouble = shareTrouble ?? SharedBookSync.shared.trouble {
                Text(trouble)
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.paint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prepareShare(for book: Book) {
        preparingShare = true
        shareTrouble = nil
        SharedBookSync.shared.clearTrouble()
        Task {
            do {
                let (share, container) = try await SharedBookSync.shared.makeShare(for: book)
                sharing = SharePayload(share: share, container: container)
            } catch {
                shareTrouble = SharedBookSync.shared.trouble ?? error.localizedDescription
            }
            preparingShare = false
        }
    }
}


/// `.sheet(item:)` needs something `Identifiable`, and a `CKShare` is not. Carrying
/// the container alongside it is convenient anyway — the share sheet needs both.
struct SharePayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}
