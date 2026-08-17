import SwiftUI
import SwiftData

struct TripsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup
    @Environment(CoachPresenter.self) private var coach

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]
    @AppStorage(TripSelection.key) private var currentTripID = ""

    @Environment(TourGuide.self) private var tour

    @State private var editing: Trip?
    @State private var creating = false
    @State private var showArchived = false
    /// Open by default: a finished trip is recent news, an archived one is not.
    @State private var showFinished = true

    /// Set by the editor, acted on once the sheet is gone. A popup lives at the
    /// root and a sheet is presented above it, so a confirmation raised while the
    /// editor is still up would be invisible.
    @State private var pending: Pending?

    private enum Pending {
        case clear(Trip)
        case delete(Trip)
        case archive(Trip)
        case finish(Trip)
        case fold(Trip)
        case unfold(Trip)
    }

    private var current: Trip? { TripSelection.current(from: trips, id: currentTripID) }

    /// Who played this trip, or nothing if it was never a party.
    ///
    /// Gated on the ledger rather than on "more than one person has a sighting",
    /// because that is also true of every trip from the shared-device era — and a
    /// badge that says "party" on a trip four people took turns tapping into one
    /// phone would be telling a small lie about what happened.
    private func partyFaces(for trip: Trip) -> [Player] {
        guard PartyLedger.shared.wasParty(trip.id) else { return [] }
        return trip.participants(from: players)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "suitcase")
                    } description: {
                        // Says what a trip is *for*, which is the thing that stops
                        // one being made for every drive to the shops. A trip has a
                        // start, an end and a route it scores rarity against; used
                        // for everyday spotting it becomes a list nobody can face.
                        // The book is the answer for that, and this is the first
                        // place anyone would otherwise not find out.
                        Text("A trip is one journey: it has a route, and it ends. For everyday spotting on the way to school or the shops, use a plate book instead: it just keeps going.")
                    } actions: {
                        Button("New trip") { creating = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.route)
                            .tourAnchor(.tripsNew)
                            .tourStop(.tripsNew)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: offerTripTips)
            .onAppear { tour.offer(.trips, stops: tourStops) }
            .onDisappear { tour.left(.trips) }
            // A trip finished from the record sheet lands back here with the
            // Finished section newly populated, which is the exact moment
            // `doneTrip` is worth saying.
            .onChange(of: trips.count) { _, _ in offerTripTips() }
            .onChange(of: trips.finished.count) { _, _ in offerTripTips() }
            // Leaving counts as shown. See `CoachPresenter.withdraw`.
            .onDisappear {
                coach.withdraw(.swipeTrip)
                coach.withdraw(.doneTrip)
                coach.withdraw(.listLength)
            }
            #if DEBUG
            // `-tripEditor new|edit|archived` opens the sheet for screenshots.
            // `-showArchived` stands the archived section open, which is otherwise a
            // tap away and so unreachable from a launch argument. `-foldPopup` opens
            // the add-to-book flow for the first archived trip — it normally starts
            // from a button inside the record sheet, which no argument can press.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-showArchived") { showArchived = true }
                if args.contains("-foldPopup"), let done = trips.archived.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        pending = .fold(done)
                        runPending()
                    }
                }
                // The other five confirmations, on the current trip. Same reason as
                // `-foldPopup`: they all start from a button inside the record
                // sheet, so nothing a launch argument can reach opens them, and
                // their messages are the longest sentences in the app.
                if let kind = LaunchFlags.value(after: "-tripPopup"),
                   let trip = current ?? trips.playable.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        switch kind {
                        case "clear":   pending = .clear(trip)
                        case "delete":  pending = .delete(trip)
                        case "archive": pending = .archive(trip)
                        case "finish":  pending = .finish(trip)
                        case "unfold":  pending = .unfold(trip)
                        default:        return
                        }
                        runPending()
                    }
                }
                guard let which = LaunchFlags.value(after: "-tripEditor") else { return }
                switch which {
                case "new": creating = true
                case "archived": editing = trips.archived.first
                default: editing = current
                }
            }
            #endif
            .toolbar {
                if !trips.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { creating = true } label: {
                            Image(systemName: "plus")
                        }
                        .tint(Theme.route)
                    }
                }
            }
        }
        .sheet(isPresented: $creating) {
            TripEditor(trip: nil, onClear: nil, onDelete: nil)
        }
        .sheet(item: $editing, onDismiss: runPending) { trip in
            TripEditor(
                trip: trip,
                onClear: { pending = .clear(trip); editing = nil },
                onDelete: { pending = .delete(trip); editing = nil },
                onArchive: { pending = .archive(trip); editing = nil },
                onFinish: { pending = .finish(trip); editing = nil },
                // Nil when there is no book to fold into — the editor hides the
                // button rather than opening a picker with nothing in it.
                onFold: books.isEmpty ? nil : { pending = .fold(trip); editing = nil },
                onUnfold: { pending = .unfold(trip); editing = nil }
            )
        }
        // Last in the chain, so the balloon draws over the list and under the tab
        // bar. Copy lives here rather than in a table elsewhere: whoever changes
        // what a tip says is the person looking at the screen it appears on.
        .coachLayer(Self.coachCopy)
        .tourLayer(.trips, Self.tourCopy)
    }

    /// What this screen's tips say. Out of the chain, not out of the
    /// file — see `coachLayer`.
    private static let coachCopy: [Coach.Tip: LocalizedStringResource] = [
        .swipeTrip: "Swipe a trip left to pin it, or to mark it done.",
        .doneTrip: "Finished trips file themselves here. Open one for its story, or to add its plates to a book.",
        .listLength: "That's a lot of trips going at once. Mark the old ones done and they file themselves away."
    ]

    /// What this screen's tour stops say. Out of the chain, not out of the
    /// file — see `coachLayer`.
    private static let tourCopy: [Tour.Stop: LocalizedStringResource] = [
        .tripsRow: "Every drive you have going. Tap one to play it, or swipe it left to pin it or mark it done.",
        .tripsNew: "A trip is one journey: it has a route, and it ends. The route is what decides how rare each plate is, so a Florida plate is worth more in Oregon.",
        .tripsFinished: "Finished trips file themselves down here. Open one for its story, or to add everything it collected into a book."
    ]

    /// Which stops this screen can actually host right now.
    ///
    /// In screen order rather than declaration order, because the tour scrolls between
    /// them: the running list is at the top, the button to add to it sits under the
    /// list, and Finished is below both. A route that reads top to bottom is a route
    /// that never scrolls backwards, and a tour that scrolls backwards looks broken
    /// even when it is pointing at exactly the right thing.
    private var tourStops: [Tour.Stop] {
        guard !trips.isEmpty else { return [.tripsNew] }
        var route: [Tour.Stop] = []
        if !trips.running.isEmpty { route.append(.tripsRow) }
        route.append(.tripsNew)
        if !trips.finished.isEmpty { route.append(.tripsFinished) }
        return route
    }

    private var list: some View {
        ScrollView {
          ScrollViewReader { scroller in
            VStack(spacing: 10) {
                let rows = trips.running.pinnedFirst
                ForEach(rows) { trip in
                    SwipeRow(actions: actions(for: trip),
                             onOpen: { coach.dismiss(.swipeTrip) }) {
                        TripRow(
                            trip: trip,
                            isCurrent: trip.id == current?.id,
                            onSelect: { select(trip) },
                            onEdit: { editing = trip },
                            party: partyFaces(for: trip)
                        )
                    }
                    .coachAnchor(.swipeTrip,
                                 active: trip.id == rows.first?.id,
                                 prefersAbove: true)
                    // The top of the list, and deliberately not the oldest trip or
                    // the Finished header. Both of those are the better *subject* —
                    // the tip is about old trips and where they file to — and both
                    // are wrong as a target: the oldest row of a list this long is
                    // below the fold, and somebody with nine running trips and
                    // nothing finished has no Finished header at all. That is
                    // precisely the person the tip is for.
                    //
                    // The balloon is the only mark here that is about the list
                    // rather than about a row, so it hangs off the head of the list
                    // and the copy names the list in its first clause.
                    .coachAnchor(.listLength, active: trip.id == rows.first?.id)
                    .tourAnchor(.tripsRow,
                                active: trip.id == rows.first?.id,
                                prefersAbove: true)
                }
                .tourStop(.tripsRow)

                Button { creating = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("New trip")
                            .font(.plates(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.route)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.route.opacity(0.35),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                }
                .padding(.top, 2)
                .tourAnchor(.tripsNew, prefersAbove: true)
                .tourStop(.tripsNew)

                // One gesture now, not two. The sentence that used to follow
                // explained what a trip is *for*, which belongs on the empty screen
                // you see before you have one — repeating it under a list of trips
                // you already made reads as the app justifying itself.
                //
                // The swipe half went the same way for the same reason. The
                // `swipeTrip` mark points at the actual row and arrives at the one
                // moment there is more than one trip to organise; a permanent line
                // three inches below it saying the same words is the app talking
                // over itself, which is the one thing the coach marks were not
                // allowed to cause. The durable copy for the gesture lives on the
                // "How to play" page, where somebody who missed the balloon can go
                // looking for it.
                Text("Tap a trip to play it.")
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                finishedSection

                archivedSection

                // Moved here from the Book tab, where it was a "History" page that
                // listed trips and no books whatsoever. Trips belong with trips.
                TripComparison(summaries: trips.map(TripSummary.init),
                               currentTripID: current?.id)
            }
            .padding(Theme.screenPadding)
            .tourScrolling(scroller)
          }
        }
    }

    /// Trips that have ended but not been put away.
    ///
    /// Separate from the running list because they take no more plates, and separate
    /// from the archive because "done" and "filed" are different intentions — the
    /// drive you finished this afternoon should not need digging out of the same
    /// place as one from two years ago. Expanded by default for that reason.
    @ViewBuilder
    private var finishedSection: some View {
        let done = trips.finished
        if !done.isEmpty {
            VStack(spacing: 10) {
                DisclosureBar(symbol: "flag.checkered",
                              title: "Finished",
                              count: done.count,
                              isOpen: showFinished) { showFinished.toggle() }
                    .coachAnchor(.doneTrip, prefersAbove: true)
                    .tourAnchor(.tripsFinished, prefersAbove: true)

                if showFinished {
                    ForEach(done) { trip in
                        SwipeRow(actions: [
                            SwipeAction(title: "Reopen",
                                        symbol: "arrow.uturn.backward",
                                        tint: Theme.route) { reopen(trip) },
                            SwipeAction(title: "Archive",
                                        symbol: "archivebox",
                                        tint: Theme.inkMuted) { setArchived(trip, true) }
                        ]) {
                            TripRow(trip: trip,
                                    isCurrent: false,
                                    onSelect: { openRecord(trip) },
                                    onEdit: { openRecord(trip) },
                                    party: partyFaces(for: trip))
                        }
                    }
                }
            }
            .padding(.top, 18)
            .tourStop(.tripsFinished)
        }
    }

    /// Archived trips, behind a disclosure.
    ///
    /// They have to be reachable from somewhere or archiving would be a one-way door
    /// — but not in the main list, since the entire point was to stop seeing them.
    /// Collapsed by default, and the section does not exist at all until something is
    /// in it.
    @ViewBuilder
    private var archivedSection: some View {
        let archived = trips.archived
        if !archived.isEmpty {
            VStack(spacing: 10) {
                DisclosureBar(symbol: "archivebox",
                              title: "Archived",
                              count: archived.count,
                              isOpen: showArchived) { showArchived.toggle() }

                if showArchived {
                    ForEach(archived) { trip in
                        SwipeRow(actions: [
                            SwipeAction(title: "Reopen",
                                            symbol: "arrow.uturn.backward",
                                            tint: Theme.route) { reopen(trip) }
                        ]) {
                            TripRow(trip: trip,
                                    isCurrent: false,
                                    onSelect: { editing = trip },
                                    onEdit: { editing = trip },
                                    party: partyFaces(for: trip))
                        }
                        // Dimming the whole row, not the card inside it. Applied to
                        // the card alone it made the card translucent *over its own
                        // swipe actions*, and archived is a statement about the row
                        // rather than about its contents anyway.
                        .opacity(0.65)
                    }
                }
            }
            .padding(.top, 18)
        }
    }

    // MARK: - Actions

    /// The two things worth a swipe: get it out of the list, or keep it at the top.
    ///
    /// Deliberately not archive or delete. Putting either one careless swipe from a
    /// trip's worth of plates is how people lose data, and both still live in the
    /// editor. This said archiving was "what done already does" back when finishing
    /// archived as well; it has not since `TripClosing.finish` split the two.
    private func actions(for trip: Trip) -> [SwipeAction] {
        let pinned = trip.pinnedAt != nil
        return [
            SwipeAction(title: pinned ? "Unpin" : "Pin",
                            symbol: pinned ? "pin.slash" : "pin",
                            tint: Theme.paint) { togglePin(trip) },
            SwipeAction(title: trip.isActive ? "Done" : "Reopen",
                            symbol: trip.isActive ? "flag.checkered" : "arrow.uturn.backward",
                            tint: trip.isActive ? Theme.found : Theme.route) {
                if trip.isActive {
                    // Straight through, no confirmation. A swipe is already a
                    // deliberate two-part gesture, nothing is destroyed, and it is
                    // undone by the same swipe on the row in the archive.
                    finish(trip)
                } else {
                    reopen(trip)
                }
            }
        ]
    }

    private func togglePin(_ trip: Trip) {
        trip.pinnedAt = trip.pinnedAt == nil ? Date() : nil
        try? context.save()
        Haptics.selection()
    }

    private func reopen(_ trip: Trip) {
        trip.endedAt = nil
        trip.archivedAt = nil
        try? context.save()
        // Reopening changes what `TripSelection.current` resolves to — it falls
        // through to the newest collectable trip — so the two mirrors `TripClosing`
        // rebuilds when a trip *closes* have to be rebuilt when one opens again.
        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
        Haptics.selection()
    }

    /// Also flips the target kind: tapping a trip here means "play this", which has
    /// to win over a book the Drive screen happened to be filling.
    private func select(_ trip: Trip) {
        PlaySelection.select(.trip(trip))
        Haptics.selection()
    }

    private func runPending() {
        guard let pending else { return }
        self.pending = nil

        switch pending {
        case .clear(let trip):
            popup.present(
                "Clear every plate?",
                // `^[…](inflect: true)` in place of the `n == 1 ? "" : "s"` this
                // used to splice in. The old form produced a catalog key reading
                // "%lld plate%@ found on %@" — two arguments where there is one
                // idea, and no way for a translator to give a language its own
                // plural rules. Automatic grammar agreement puts the whole phrase
                // in one entry and picks the form from the number beside it.
                message: "^[\(trip.platesFound) plate](inflect: true) found on \(trip.name) will be un-collected. The trip itself stays."
            ) {
                PopupButton(title: "Clear plates", kind: .destructive) {
                    wipe(trip)
                    popup.dismiss()
                }
                PopupButton(title: "Keep them") { popup.dismiss() }
            }

        case .finish(let trip):
            popup.present(
                "Done with \(trip.name)?",
                message: partyWarning(for: trip, finishing: true)
                    // Said "filed under Archived" until finishing and archiving
                    // became two moves — see `TripClosing.finish`. Finished trips
                    // now stay on this screen under their own heading, and only
                    // `collectable` hides them from the pickers.
                    ?? "It stops collecting and files itself under Finished, so it is out of every trip picker but still here to open. Its ^[\(trip.platesFound) plate](inflect: true) stay in your history, and you can reopen it whenever you like."
            ) {
                PopupButton(title: "Mark as done", kind: .primary) {
                    finish(trip)
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }

        case .archive(let trip):
            guard !trip.isArchived else { setArchived(trip, false); return }
            popup.present(
                "Archive \(trip.name)?",
                message: "It stops appearing anywhere you pick a trip. Nothing is deleted. Its ^[\(trip.platesFound) plate](inflect: true) stay in your history, and you can bring it back."
            ) {
                PopupButton(title: "Archive", kind: .primary) {
                    setArchived(trip, true)
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }

        case .delete(let trip):
            popup.present(
                "Delete \(trip.name)?",
                message: partyWarning(for: trip, finishing: false)
                    ?? "The trip and its ^[\(trip.platesFound) collected plate](inflect: true) are removed for good."
            ) {
                PopupButton(title: "Delete trip", kind: .destructive) {
                    remove(trip)
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }

        case .fold(let trip):
            // Straight to the how-question when there is only one book — the
            // common case should be two taps, not three.
            if books.count == 1, let only = books.first {
                askFoldMode(trip, into: only)
            } else {
                popup.present("Add \(trip.name) to which book?") {
                    PopupPicker(groups: [PopupPicker.Group(entries: books.map { book in
                        PopupPicker.Entry(id: book.id,
                                          title: book.name,
                                          subtitle: book.sinceLabel,
                                          action: { askFoldMode(trip, into: book) })
                    })])
                    PopupButton(title: "Cancel") { popup.dismiss() }
                }
            }

        case .unfold(let trip):
            let folded = trip.allSightings.filter { $0.book != nil }
            guard let book = folded.first?.book else { return }
            popup.present(
                "Remove from \(book.name)?",
                message: "The ^[\(folded.count) sighting](inflect: true) this trip added leave the book. Plates the book collected on its own stay, and the trip itself is untouched."
            ) {
                PopupButton(title: "Remove", kind: .destructive) {
                    unfold(trip)
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }
        }
    }

    /// Stack or fill — the one decision a fold needs, asked with the counts that
    /// make it decidable.
    private func askFoldMode(_ trip: Trip, into book: Book) {
        let total = trip.allSightings.filter { $0.book == nil }.count
        let missing = Set(trip.allSightings.map(\.plateCode))
            .subtracting(book.allSightings.map(\.plateCode)).count
        popup.present(
            "Add \(trip.name) to \(book.name)?",
            message: "The trip keeps its plates either way. The book just shows them too, and you can take them back out whenever you like."
        ) {
            PopupChoice(title: "Stack everything",
                        subtitle: "All ^[\(total) sighting](inflect: true) carry over. Plates the book already has count again.") {
                fold(trip, into: book, gapsOnly: false)
            }
            PopupChoice(title: "Fill the gaps",
                        subtitle: missing == 0
                            ? "Nothing to add. The book has every plate on this trip."
                            : "Just the ^[\(missing) plate](inflect: true) the book is missing.") {
                fold(trip, into: book, gapsOnly: true)
            }
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    /// Said before deleting or finishing a trip that a party is currently on.
    ///
    /// Not a block. Every other device keeps its own full copy — that is the whole
    /// shape of the design — so the only thing at stake is this phone's copy and the
    /// party ending mid-drive, which is a decision, not a mistake. It just should not
    /// be a surprise.
    /// Two whole sentences rather than one with the verb interpolated in. The verb
    /// used to be a parameter — `"\(what) ends the party…"` — which reads as a saving
    /// right up until the sentence has to exist in another language, where the word
    /// order it assumes may not survive. A catalog entry a translator can actually
    /// move around is worth the duplicated clause.
    private func partyWarning(for trip: Trip, finishing: Bool) -> LocalizedStringKey? {
        guard PartySession.isPartying(trip) else { return nil }
        return finishing
            ? "Finishing it ends the party on this phone. Everyone else keeps their own copy of the trip and the plates they spotted."
            : "Deleting it ends the party on this phone. Everyone else keeps their own copy of the trip and the plates they spotted."
    }

    /// Folding: the trip's sightings are *shelved in* the book, not copied to it.
    ///
    /// One sighting, two containers. A copy would double-count every folded plate
    /// in the all-time record and grow twin pins on the Trail; a reference keeps
    /// `Sighting` the single fact it has always been. The book's counters need no
    /// new code because they already count whatever `book.sightings` holds.
    ///
    /// Only sightings not already shelved somewhere are taken, which makes folding
    /// idempotent — reopen the trip, find three more plates, fold again, and only
    /// the three move.
    private func fold(_ trip: Trip, into book: Book, gapsOnly: Bool) {
        let loose = trip.allSightings.filter { $0.book == nil }

        let chosen: [Sighting]
        if gapsOnly {
            // One sighting per plate the book lacks — the earliest, which is the
            // find. Filling a gap with a plate's third repeat would put a ×1 in
            // the book that was really a ×3 somewhere else.
            let have = Set(book.allSightings.map(\.plateCode))
            chosen = Dictionary(grouping: loose, by: \.plateCode)
                .filter { !have.contains($0.key) }
                .compactMap { $0.value.min { SightingOrder($0) < SightingOrder($1) } }
        } else {
            chosen = loose
        }

        for sighting in chosen { sighting.book = book }
        try? context.save()

        // A shared book's other members hear about these the same way they hear
        // about a tap: one record per sighting, over the same wire.
        for sighting in chosen { SharedBookSync.shared.push(sighting, in: book) }
        popup.dismiss()
        Haptics.found()
    }

    /// The exact reverse: every sighting of this trip leaves whichever book holds
    /// it. Nothing is deleted — the sightings still belong to the trip.
    private func unfold(_ trip: Trip) {
        // Grouped by book, like `pushSharedRemovals` ten lines down. Taking the
        // first sighting's book and using it for all of them was right only while a
        // trip could be folded into exactly one book: with two, everyone sharing the
        // second book kept their copies, and the first book was sent tombstones for
        // rows that were never in it.
        let folded = trip.allSightings.filter { $0.book != nil }
        guard !folded.isEmpty else { return }
        let byBook = Dictionary(grouping: folded, by: { $0.book!.id })
        for sighting in folded { sighting.book = nil }
        try? context.save()
        for (_, group) in byBook {
            guard let book = group.first?.book else { continue }
            SharedBookSync.shared.remove(group.map(\.id), in: book)
        }
        Haptics.undo()
    }

    // A `pushSharedRemovals` sat here, and both of its callers were wrong to want
    // it. Emptying a trip goes through `PlateLogger.withdraw` now, which does this
    // itself for the books a row is genuinely leaving; deleting a trip unshelves
    // instead, so there is nothing to tell anybody about. Pushing a CloudKit
    // deletion for a plate that is still sitting in somebody's book is not a
    // tombstone, it is reaching across the wire to take it.

    /// Wipes the sightings, not the trip — `Sighting` is the only stored fact, so
    /// emptying them is all it takes to put every counter back to zero.
    ///
    /// Through `PlateLogger.withdraw`, which is the whole point of that function
    /// existing. This was the fourth copy of "delete some sightings" and the one the
    /// consolidation missed, so it alone skipped all four of the things a removal
    /// owes: the party broadcast, the tombstones that broadcast writes, the reminder
    /// measured from a plate that is now gone, and the widget still showing the
    /// count. Without the tombstones the wipe did not even hold — the next snapshot
    /// from any peer put every plate back, because nothing on this phone could say
    /// they had been taken away on purpose.
    private func wipe(_ trip: Trip) {
        PlateLogger.withdraw(trip.allSightings, from: trip, context: context)
        Haptics.destructive()
    }

    /// Opening a finished trip's record — which is exactly what the `doneTrip` mark
    /// was pointing people towards, so doing it retires the mark.
    private func openRecord(_ trip: Trip) {
        coach.dismiss(.doneTrip)
        editing = trip
    }

    /// Whether either of this screen's marks has anything to say, asked on arrival
    /// and whenever the list changes underneath it.
    ///
    /// Order matters only in the sense that the arbiter takes the first asker, and
    /// `doneTrip` goes first deliberately: it is a follow-through on something that
    /// just happened, while `swipeTrip` is standing housekeeping advice that will
    /// still be true tomorrow.
    private func offerTripTips() {
        coach.request(.doneTrip,
                      when: TripClosing.finishedSomethingThisSession
                            && !trips.finished.isEmpty)
        // Eight open trips is the point where the list stops being scannable and
        // starts being scrolled, which is when there is a problem worth naming.
        // Above `swipeTrip` in this order because somebody with eight trips has the
        // more urgent version of the same advice.
        coach.request(.listLength, when: trips.running.count >= Self.tooManyTrips)
        // Not on day one. See `Coach.launchCount`: a list of one trip made ninety
        // seconds ago has nothing in it to pin or file away.
        coach.request(.swipeTrip,
                      when: Coach.isReturningSession && !trips.running.isEmpty)
    }

    /// Where a list of drives stops being a list you read and starts being one you
    /// search. Eight is roughly a phone screen of rows.
    private static let tooManyTrips = 8

    /// See `TripClosing.finish`, which the party screen shares — a party ending is a
    /// drive ending, and both places have to mean the same thing by it.
    private func finish(_ trip: Trip) {
        // Doing the thing the tip asked for. Both of the ways to shorten the list
        // count, which is why this is not hung on `swipeTrip`'s row callback.
        coach.dismiss(.listLength)
        TripClosing.finish(trip, in: context)
        Haptics.milestone()
    }

    private func setArchived(_ trip: Trip, _ archived: Bool) {
        if archived { coach.dismiss(.listLength) }
        trip.archivedAt = archived ? Date() : nil
        try? context.save()
        // `TripSelection.current` skips archived trips, so simply clearing the saved
        // id lets it fall through to the next playable one rather than leaving the
        // Drive screen pointed at something that is no longer on offer.
        if archived, trip.id.uuidString == currentTripID { currentTripID = "" }
        // Archived trips are invisible to `TripSelection.current`, so this moves the
        // widget's subject without going through `PlaySelection.select`.
        WidgetData.write(from: context)
        Haptics.selection()
    }

    private func remove(_ trip: Trip) {
        let wasCurrent = trip.id == current?.id
        let id = trip.id
        if PartySession.isPartying(trip) { PartySession.shared?.leave() }
        // Unshelve before the cascade, exactly as `TripClosing.discard` does — the
        // two are the same operation reached from different screens and had opposite
        // answers to the same question. `Trip.sightings` cascades where
        // `Book.sightings` nullifies, so deleting the trip reaches through folded
        // rows and takes plates out of a book somebody deliberately filed them in.
        // This screen went further and *pushed those deletions to CloudKit*, so
        // deleting your own trip deleted plates out of a friend's copy of a shared
        // book — and the confirmation said nothing about any book at all.
        for sighting in trip.allSightings where sighting.book != nil { sighting.trip = nil }
        context.delete(trip)
        try? context.save()
        // Nothing left to protect from resurrection, and keeping the ids would leak a
        // little more every time somebody clears out an old drive.
        PartyTombstones.shared.forget(trip: id)
        // Leave the selection to fall through to the newest remaining trip rather
        // than pointing at something that no longer exists.
        if wasCurrent { currentTripID = "" }
        // And tell the home screen, which was still advertising the trip — and
        // deep-linking to a Game tab that had fallen through to something else.
        TripReminders.shared.refresh(in: context)
        WidgetData.write(from: context)
        Haptics.destructive()
    }
}

// MARK: - Row

struct TripRow: View {
    let trip: Trip
    let isCurrent: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    /// Everyone who played this trip, for the party badge. Empty when it was not
    /// one, which is what hides the badge.
    var party: [Player] = []

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 10) {
            // The trip being played is marked by the card itself — a full-height
            // route-blue spine and a blue title — rather than by a badge sitting
            // next to the name. A pill labelled PLAYING competed with the name for
            // the same line and read as a second, louder heading.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isCurrent ? Theme.route : .clear)
                .frame(width: 4)
                .padding(.vertical, -12)
                .padding(.leading, -14)
                .padding(.trailing, 2)

            // One line of four columns, until there is not room for four columns.
            //
            // The row holds a name, a party, a score and a button, and three of those
            // are fixed width while only the name can yield — so as the text grows the
            // name is the only thing that pays, and it pays all of it. At
            // accessibility sizes on a narrow phone it was rendering as a bare "…":
            // a list of trips where no trip has a name. Nothing overlapped, which is
            // what made it easy to miss.
            //
            // Above that threshold the same four pieces stack instead. The name gets
            // the full width of the card, and the party, score and button take a line
            // of their own underneath. See `LayoutStress`, which is what found this.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    details
                    HStack(spacing: 10) {
                        avatars
                        Spacer(minLength: 0)
                        score
                        editButton
                    }
                }
            } else {
                details
                avatars
                score
                editButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        // Inside the clip, so the fold follows the card's rounded corner instead of
        // hanging off it.
        .overlay(alignment: .topTrailing) {
            if !trip.isActive {
                DogEar()
                    .fill(Theme.found)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
        }
        // Clipped before the border is drawn, so the spine's square corners follow
        // the card's rounded ones instead of poking out past them.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isCurrent ? Theme.route : Theme.line,
                              lineWidth: isCurrent ? 1.5 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(trip.isActive ? trip.name : "\(trip.name), finished")
    }

    // MARK: - The pieces

    private var details: some View {
            // A tap gesture and not a `Button`, which is what this was until a swipe
            // on a finished trip was found to open its record as well as the row's
            // actions — and to open it again on the way back. A button this wide
            // never sees the finger leave it, so it never cancels its own press and
            // fires on touch-up at the end of the swipe. A `TapGesture` cancels the
            // moment the touch travels. See `SwipeRow`.
            //
            // The traits are restored by hand below, because what VoiceOver should
            // hear has not changed: one element, named, that behaves like a button.
            Group {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        // Wins the line against the badges beside it. Without the
                        // priority the three icons are fixed-size and the name is the
                        // only thing that can yield, so at accessibility text sizes a
                        // trip with all three badges rendered its name as a bare "…".
                        // The badges are worth less than knowing which trip this is,
                        // and they truncate to nothing gracefully because they are
                        // never the only copy of what they say.
                        Text(trip.name)
                            .font(.plates(size: 16, weight: .semibold))
                            .foregroundStyle(isCurrent ? Theme.route : Theme.ink)
                            .lineLimit(1)
                            .layoutPriority(1)

                        if isCurrent {
                            Image(systemName: "car.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.route)
                                .accessibilityLabel("Currently playing")
                        }

                        if !party.isEmpty {
                            // Its own color rather than the route blue or the pin's
                            // paint, both of which already mean something here.
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.found)
                                .accessibilityLabel("Played as a party")
                        }

                        if trip.pinnedAt != nil {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.paint)
                                .accessibilityLabel("Pinned")
                        }
                    }

                    if let route = trip.routeLabel {
                        Text(route)
                            .font(.plates(size: 12.5))
                            .foregroundStyle(Theme.route.opacity(0.85))
                            .lineLimit(1)
                    }

                    // One line, like the two above it. It was the only label in the
                    // row without a limit, so at large text sizes "Aug 15 · day 1"
                    // wrapped and made the card half again as tall as its neighbours
                    // for no information at all.
                    Text(dateLabel)
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onSelect)
    }

    /// Who was in the car. Capped at three circles however many people played, so
    /// this is a fixed width and cannot be what squeezes the name.
    @ViewBuilder
    private var avatars: some View {
        if !party.isEmpty {
            AvatarStack(players: party, limit: 3, size: 21)
        }
    }

    private var score: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(trip.statesFound)")
                .font(Theme.PlateFont.condensed(24))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text("of \(Plate.stateTotal)")
                .font(.plates(size: 10.5))
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.ground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(trip.name)")
    }

    /// The date the trip ran. It used to end in "· finished", which the green fold
    /// now says without spending a line on it.
    private var dateLabel: String {
        let start = trip.startedAt.formatted(.dateTime.month(.abbreviated).day())
        if let ended = trip.endedAt {
            return "\(start) \u{2013} \(ended.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "\(start) \u{00B7} day \(trip.dayNumber)"
    }
}

/// A folded corner, for a trip that is finished.
///
/// Deliberately not a badge and not a word. Archived trips are a list you scan
/// rather than read, and every one of them is archived — a label saying so on each
/// row is noise. What the eye is actually looking for is "which of these did I
/// finish, and which did I just put away", and that is a shape question, not a text
/// one. A green corner turned down is how people have marked a page as dealt with
/// for as long as there have been pages.
private struct DogEar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Editor

/// Create and edit share a sheet, as with players. Not private — the Game screen
/// offers "New trip" from the trip switcher without sending you to another tab.
struct TripEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @AppStorage(TripSelection.key) private var currentTripID = ""
    /// For naming the host of a joined trip — the ledger stores an id, and turning
    /// one into a person needs the roster.
    @Query(sort: \Player.joinedAt) private var players: [Player]

    let trip: Trip?
    let onClear: (() -> Void)?
    let onDelete: (() -> Void)?
    /// Nil hides the action — a new trip has nothing to archive yet.
    var onArchive: (() -> Void)?
    /// Marking a trip done also archives it, so it needs the same confirm-after-
    /// dismiss dance as the others.
    var onFinish: (() -> Void)?
    /// Folding this trip into a book, and undoing that. Nil when there is no book
    /// to fold into, which hides the button rather than offering a dead end.
    var onFold: (() -> Void)?
    var onUnfold: (() -> Void)?

    @State private var name = ""
    @State private var origin = Place()
    @State private var destination = Place()
    /// Overwritten in `onAppear` — from the trip being edited, or from `Trip`'s own
    /// default for a new one, so the picker and the model cannot disagree about what
    /// "default" means.
    @State private var mode: ScoringMode = .weighted
    @FocusState private var focused: Field?

    private enum Field { case name }

    private var isNew: Bool { trip == nil }

    /// A trip that is put away is a record, not a form.
    ///
    /// It already refuses new plates, so leaving its settings editable meant you
    /// could change the scoring of a trip that can never score again, or retype the
    /// route of a drive that is over. Everything that describes the trip goes
    /// read-only until it is brought back — which is one tap, in the same sheet.
    ///
    /// Keyed on the same condition as `collectable` rather than on `isArchived`
    /// alone, so that the two ways of putting a trip away lock it identically.
    private var isLocked: Bool {
        guard let trip else { return false }
        return trip.isArchived || !trip.isActive
    }

    /// The trip's sightings in the order they happened — the story of the drive.
    private var log: [Sighting] {
        (trip?.allSightings ?? []).sorted { SightingOrder($0) < SightingOrder($1) }
    }

    /// The book this trip has been folded into, if any. Derived from the sightings
    /// rather than stored anywhere, so it can never disagree with them.
    private var foldedBook: Book? {
        trip?.allSightings.compactMap(\.book).first
    }

    /// Spotter chips only mean something when there was more than one spotter.
    ///
    /// Takes the already-sorted rows rather than re-reading `log`, which sorts.
    private func showSpotters(in entries: [Sighting]) -> Bool {
        Set(entries.compactMap { $0.player?.id }).count > 1
    }

    /// Whether any sighting knows where it happened — without one the Trail would
    /// open on an empty map, so the jump is not offered.
    private var hasTrail: Bool {
        trip?.allSightings.contains { $0.spottedLat != nil } == true
    }

    /// The host owns the scoring rules while a party is running.
    ///
    /// `scoringMode` and `includesTrucks` decide what every point in the trip is
    /// worth, so one passenger flipping either of them mid-drive would silently
    /// rewrite everybody's game — including plates already banked on four other
    /// phones. The host's copy is the one that counts; everyone else reads.
    ///
    /// Only while actually connected. A party that has ended leaves the trip fully
    /// editable again, because at that point it is just a trip you have a copy of.
    private var scoringIsHostOwned: Bool {
        guard let trip, let party = PartySession.shared else { return false }
        // Keyed on the party still running, not on this moment's connection — the
        // same rule and the same reason as `PartySession.rules(for:)`, which spells
        // it out: a phone that drops out for a minute must not briefly get
        // permission to change the game. The host's phone locking reopened the
        // scoring picker mid-sheet, and Save then rewrote `scoringMode` on the
        // guest's copy, where `broadcastTrip` refuses to send it — so every plate on
        // that phone was quietly worth something different from everyone else's.
        return party.role == .guest && !party.hasEnded && party.tripID == trip.id
    }

    /// Says plainly what pinning a place buys you, because the difference between
    /// typed text and a dropped pin is invisible otherwise.
    /// Nil where there is nothing useful to say. A locked trip with no pinned start
    /// would otherwise be told to go and pick one, which it cannot do.
    private var rarityNote: LocalizedStringKey? {
        if origin.isPinned {
            return isLocked
                ? "Rarity was scored against this route."
                : "Rarity is scored against this route. Plates from far away are worth more."
        }
        return isLocked
            ? nil
            : "Pick a place from the list to score rarity by where you are driving."
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if isLocked { lockedNotice }
                        if let host = hostedBy { hostedNotice(host) }

                        nameField

                        // The record of the trip: what it came to, in numbers.
                        // Meaningless on a live trip, whose numbers are on the Game
                        // screen — this sheet only reports once it is over.
                        if isLocked { statsStrip }

                        // An archived trip that never had a route has nothing to show
                        // here, and two greyed-out empty boxes are worse than no
                        // section at all.
                        if !isLocked || origin.hasName || destination.hasName {
                            routeSection
                        }

                        // The scoring boxes go, rather than grey out. They are
                        // controls and only controls — there is no reading of a
                        // radio button that is not "press me" — and the one line
                        // below says what the trip was scored on just as well.
                        if isLocked || scoringIsHostOwned {
                            scoringSummary
                            if scoringIsHostOwned {
                                Text("The host sets the scoring while you are in a party.")
                                    .font(.plates(size: 12.5))
                                    .foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            scoringPicker
                        }

                        if isLocked, !log.isEmpty { plateLog }

                        if !isNew { dangerZone }

                        Spacer(minLength: 8)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle(isLocked ? (trip?.isActive == false ? "Finished trip" : "Archived trip")
                                      : (isNew ? "New trip" : "Edit trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // One button when locked. Cancel and Save are a pair that only makes
                // sense against pending edits, and offering Save on a sheet that
                // cannot be edited invites the question of what it would save.
                if !isLocked {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                // Any trip can be shared, running or finished — showing somebody
                // where you have got to is as true halfway down the country as it is
                // at the end. In the toolbar because that is where sharing lives;
                // it spent one commit buried at the bottom of the sheet.
                if let trip, !isNew {
                    ToolbarItem(placement: .topBarTrailing) {
                        PosterShareButton(label: "Share this trip") {
                            await ShareablePoster.poster(for: trip, players: players)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLocked {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } else {
                        Button(isNew ? "Start" : "Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .onAppear {
            name = trip?.name ?? ""
            origin = Place(name: trip?.origin ?? "",
                           latitude: trip?.originLat, longitude: trip?.originLon)
            destination = Place(name: trip?.destination ?? "",
                                latitude: trip?.destinationLat, longitude: trip?.destinationLon)
            mode = trip?.scoringMode ?? Trip.defaultScoringMode
            if isNew { focused = .name }
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(isLocked ? "ROUTE" : "ROUTE \u{00B7} OPTIONAL")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            PlaceField(placeholder: "Starting from",
                       symbol: "smallcircle.filled.circle",
                       place: $origin,
                       isLocked: isLocked)
            PlaceField(placeholder: "Heading to",
                       symbol: "mappin.and.ellipse",
                       place: $destination,
                       isLocked: isLocked)

            if let a = origin.coordinate, let b = destination.coordinate {
                RouteMap(start: a, end: b)
                    .padding(.top, 3)
                    // Opacity only. A scale transition resizes the map every frame
                    // it is animating, which is what the zero-size drawable
                    // warnings came from.
                    .transition(.opacity)
            }

            if let rarityNote {
                Text(rarityNote)
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 1)
            }
        }
        .animation(.snappy(duration: 0.28), value: origin.isPinned)
        .animation(.snappy(duration: 0.28), value: destination.isPinned)
    }

    /// Whose drive this was, when it was not this phone's.
    ///
    /// Answered from `hostPlayerID` where the ledger has it — the id the host sent in
    /// every snapshot, which until now nothing read. A name can be changed or shared
    /// by two people in one car; the id is the only thing that cannot.
    private var hostedBy: String? {
        guard let trip else { return nil }
        return PartyLedger.shared.hostLabel(for: trip.id, among: players)
    }

    /// Whose trip this is, said where somebody looking at the record would ask.
    /// Complements the party screen's refusal to let a guest host it.
    private func hostedNotice(_ host: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1.5)
            Text("\(host)'s trip, from their party. This is your copy of it.")
                .font(.plates(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.unfound.opacity(0.55))
        )
    }

    /// Why the sheet is inert, said once at the top rather than left for the reader
    /// to work out from four greyed-out fields.
    private var lockedNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 1.5)
            Text(trip?.isActive == false
                 ? "This trip is done and filed away. Reopen it below to make changes or collect more plates."
                 : "This trip is archived. Unarchive it below to make changes or collect more plates.")
                .font(.plates(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inkMuted)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.unfound.opacity(0.55))
        )
    }

    /// What the trip came to. Three numbers, which is all a headline should be —
    /// the plate-by-plate account is the log below.
    private var statsStrip: some View {
        HStack(spacing: 0) {
            recordStat("\(trip?.score ?? 0)", "points")
            statDivider
            recordStat("\(trip?.platesFound ?? 0)",
                       trip?.platesFound == 1 ? "plate" : "plates")
            statDivider
            recordStat("\(trip?.dayNumber ?? 1)",
                       trip?.dayNumber == 1 ? "day" : "days")
            // Left as ternaries rather than folded into `^[…](inflect:)`: the number
            // is in the *other* half of this pair, so there is nothing beside the
            // word for the agreement engine to agree with. Four short keys instead.
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
        )
    }

    private func recordStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.PlateFont.condensed(24))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.plates(size: 10.5))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 26)
    }

    /// Every plate, in the order it was called — the story of the drive. In
    /// unlimited scoring the same plate appears once per sighting, because each
    /// one scored.
    private var plateLog: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("PLATES \u{00B7} IN ORDER FOUND")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            // Sorted once. `log` is a computed property that sorts every sighting
            // the trip has, and it was being read again inside its own `ForEach` for
            // the divider test and a third time per row through `showSpotters` — so
            // a 300-plate drive did roughly 600 full sorts per render of this sheet,
            // on the main thread, and the sheet visibly stalled on opening.
            let entries = log
            let lastID = entries.last?.id
            let spotters = showSpotters(in: entries)
            LazyVStack(spacing: 0) {
                ForEach(entries) { sighting in
                    logRow(sighting, showingSpotter: spotters)
                    if sighting.id != lastID {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1))
            )
        }
    }

    private func logRow(_ sighting: Sighting, showingSpotter: Bool) -> some View {
        let banked = sighting.rarityWhenSpotted
            ?? trip.map { $0.rarity(of: sighting.plateCode) } ?? 1
        return HStack(spacing: 10) {
            // The tier it was claimed at. The grid hides rarity until a plate is
            // found; here everything is found, so the record can say what each
            // one was worth.
            Circle()
                .fill(RarityTier.forRarity(banked).color)
                .frame(width: 7, height: 7)

            Text(sighting.plateCode)
                .font(Theme.PlateFont.condensed(15))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, alignment: .leading)

            Text(sighting.plate?.name ?? sighting.plateCode)
                .font(.plates(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if showingSpotter, let player = sighting.player {
                PlayerDot(player, showing: .initial, size: 17)
            }

            Text(logTime(sighting.spottedAt))
                .font(.plates(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        // Two whole labels rather than one with a clause `+`-ed on. The concatenation
        // made this a `String`, so VoiceOver's only line about a logged plate was the
        // last piece of copy in the app the String Catalog could not see.
        .accessibilityLabel(sighting.player.map {
            LocalizedStringKey("\(sighting.plate?.name ?? sighting.plateCode), \(logTime(sighting.spottedAt)), spotted by \($0.name)")
        } ?? "\(sighting.plate?.name ?? sighting.plateCode), \(logTime(sighting.spottedAt))")
    }

    /// "Day 2 · 3:41 PM" on a trip that spanned days; just the time on one that
    /// did not.
    private func logTime(_ date: Date) -> String {
        let clock = date.formatted(.dateTime.hour().minute())
        guard let trip, trip.dayNumber > 1 else { return clock }
        // From midnight to midnight, not start-time to start-time. Counting raw
        // 24-hour spans meant a trip that began at 22:00 called 08:00 the next
        // morning "Day 1" and 23:00 that same evening "Day 2" — two sightings on one
        // calendar day, labelled differently, with the whole column drifting from
        // the wall calendar by however late the drive started.
        let calendar = Calendar.current
        let day = (calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: trip.startedAt),
                                           to: calendar.startOfDay(for: date)).day ?? 0) + 1
        return "Day \(max(1, day)) \u{00B7} \(clock)"
    }

    /// What the picker would have said, in one line.
    private var scoringSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SCORING")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            Text(mode.label)
                .font(.plates(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private var scoringPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SCORING")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            VStack(spacing: 7) {
                ForEach(ScoringMode.allCases) { option in
                    Button {
                        mode = option
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(mode == option ? Theme.route : Theme.inkMuted.opacity(0.5))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(.plates(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(option.blurb)
                                    .font(.plates(size: 11.5))
                                    .foregroundStyle(Theme.inkMuted)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(mode == option ? Theme.route : Theme.line,
                                                  lineWidth: mode == option ? 1.5 : 1))
                        )
                    }
                    .buttonStyle(.plain)
                }

            }
        }
    }

    @ViewBuilder
    private var dangerZone: some View {
        VStack(spacing: 8) {
            if let trip {
                // The two things worth doing with a record: see it on the map, and
                // shelve it in the collection. Only once the trip is over — a live
                // trip's map is the Trail's default already, and folding a trip
                // still gathering plates would leave the book forever behind it.
                if isLocked, hasTrail {
                    Button {
                        router.showTrail(.trip(trip.id))
                        dismiss()
                    } label: {
                        rowLabel("View trail", symbol: "map", tint: Theme.route)
                    }
                }

                if isLocked, let foldedBook, let onUnfold {
                    Button(action: onUnfold) {
                        rowLabel("Remove from \(foldedBook.name)",
                                 symbol: "books.vertical", tint: Theme.paint)
                    }
                } else if isLocked, foldedBook == nil, let onFold {
                    Button(action: onFold) {
                        rowLabel("Add to book\u{2026}",
                                 symbol: "books.vertical", tint: Theme.paint)
                    }
                }

                // Also on a swipe, but it has to exist here too: the swipe buttons
                // are hidden from VoiceOver, so this is the accessible route to it.
                // Not offered on a trip that is put away — pinning sorts the main
                // list, which is the one list this trip is not in.
                if !isLocked {
                    Button {
                        trip.pinnedAt = trip.pinnedAt == nil ? Date() : nil
                        try? context.save()
                        Haptics.selection()
                    } label: {
                        rowLabel(trip.pinnedAt == nil ? "Pin to top" : "Unpin",
                                 symbol: trip.pinnedAt == nil ? "pin" : "pin.slash",
                                 tint: Theme.paint)
                    }
                }

                if trip.isActive, let onFinish {
                    // "Mark as done" rather than "Finish", because it does both:
                    // ends the trip and files it. See `finish(_:)`.
                    Button(action: onFinish) {
                        rowLabel("Mark as done", symbol: "flag.checkered", tint: Theme.found)
                    }
                } else if !trip.isActive {
                    Button {
                        // Reopening undoes the whole of "done", archive included.
                        // Ending up with a live trip still filed under Archived is
                        // the confusing half-state this avoids.
                        trip.endedAt = nil
                        trip.archivedAt = nil
                        try? context.save()
                        Haptics.selection()
                    } label: {
                        rowLabel("Reopen this trip",
                                 symbol: "arrow.uturn.backward", tint: Theme.route)
                    }
                }
            }

            // Hidden on a finished trip, where Reopen above is the only sensible way
            // back. Unarchiving one on its own would leave it out of the archive and
            // still unable to take a plate, which is a state with no name.
            if let onArchive, trip?.isActive != false {
                Button(action: onArchive) {
                    // Not tinted red. Archiving loses nothing, and coloring it like
                    // the two below would imply it does. Separate from "done"
                    // because they are different intentions: this one is "out of my
                    // way for now", with no claim that the trip is over.
                    rowLabel(trip?.isArchived == true ? "Unarchive trip" : "Archive trip",
                             symbol: trip?.isArchived == true ? "tray.and.arrow.up" : "archivebox",
                             tint: Theme.route)
                }
            }

            // Clearing is an edit like any other, so it waits for the trip to come
            // back. Delete stays: discarding an old trip is the whole reason to open
            // one from the archive, and it is not a change to the record.
            if let onClear, !isLocked {
                Button(action: onClear) {
                    rowLabel("Clear all plates", symbol: "eraser", tint: .red)
                }
            }

            if let onDelete {
                Button(action: onDelete) {
                    rowLabel("Delete trip", symbol: "trash", tint: .red)
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TRIP NAME")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            TextField("Summer roadtrip", text: $name)
                .focused($focused, equals: .name)
                .font(.plates(size: 17))
                .submitLabel(.done)
                .disabled(isLocked)
                .foregroundStyle(isLocked ? Theme.inkMuted : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isLocked ? Theme.unfound.opacity(0.55) : Theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1))
                )
        }
    }

    private func save() {
        // The toolbar does not offer this while locked; the guard is so that a future
        // caller cannot write through the read-only sheet by accident.
        guard !trimmedName.isEmpty, !isLocked else { return }

        let target: Trip
        if let trip {
            target = trip
            trip.name = trimmedName
            // Guests do not get to change what the party is scored on. The controls
            // are already hidden for them; this is the same guard as `isLocked` above,
            // for the same reason.
            if !scoringIsHostOwned { trip.scoringMode = mode }
        } else {
            target = Trip(name: trimmedName, scoringMode: mode)
            context.insert(target)
            // A trip you just created is a trip you want to play.
            PlaySelection.select(.trip(target))
        }

        target.origin = origin.name.nilIfBlank
        target.originLat = origin.latitude
        target.originLon = origin.longitude
        target.destination = destination.name.nilIfBlank
        target.destinationLat = destination.latitude
        target.destinationLon = destination.longitude

        try? context.save()

        // Tell the party, so the rules and the route reach every phone rather than
        // only the one they were typed on. No-op unless this trip is the party's.
        PartySession.shared?.broadcastTrip(target)
        dismiss()
    }
}
