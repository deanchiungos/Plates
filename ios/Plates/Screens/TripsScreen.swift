import SwiftUI
import SwiftData

struct TripsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @AppStorage(TripSelection.key) private var currentTripID = ""

    @State private var editing: Trip?
    @State private var creating = false
    @State private var showArchived = false

    /// Set by the editor, acted on once the sheet is gone. A popup lives at the
    /// root and a sheet is presented above it, so a confirmation raised while the
    /// editor is still up would be invisible.
    @State private var pending: Pending?

    private enum Pending {
        case clear(Trip)
        case delete(Trip)
        case archive(Trip)
        case finish(Trip)
    }

    private var current: Trip? { TripSelection.current(from: trips, id: currentTripID) }

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
                        Text("A trip is one journey \u{2014} it has a route, and it ends. "
                             + "For everyday spotting on the way to school or the shops, "
                             + "use a plate book instead: it just keeps going.")
                    } actions: {
                        Button("New trip") { creating = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.route)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.large)
            #if DEBUG
            // `-tripEditor new|edit|archived` opens the sheet for screenshots.
            // `-showArchived` stands the archived section open, which is otherwise a
            // tap away and so unreachable from a launch argument.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-showArchived") { showArchived = true }
                guard let i = args.firstIndex(of: "-tripEditor"), i + 1 < args.count else { return }
                switch args[i + 1] {
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
                onFinish: { pending = .finish(trip); editing = nil }
            )
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(trips.playable.pinnedFirst) { trip in
                    SwipeRow(actions: actions(for: trip)) {
                        TripRow(
                            trip: trip,
                            isCurrent: trip.id == current?.id,
                            onSelect: { select(trip) },
                            onEdit: { editing = trip }
                        )
                    }
                }

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

                Text("Tap a trip to play it, or swipe one left to pin it or mark it done. "
                     + "A trip is one journey; for everyday spotting, fill a book instead.")
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                archivedSection
            }
            .padding(Theme.screenPadding)
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
                Button {
                    withAnimation(.snappy(duration: 0.25)) { showArchived.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Archived")
                            .font(.plates(size: 13, weight: .semibold))
                        Text("\(archived.count)")
                            .font(.plates(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkMuted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showArchived ? 90 : 0))
                        Spacer()
                    }
                    .foregroundStyle(Theme.inkMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                                    onEdit: { editing = trip })
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
    /// Deliberately not archive or delete. Archiving is what "done" already does,
    /// and putting delete one careless swipe from a trip's worth of plates is how
    /// people lose data. Both still live in the editor.
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
                message: "\(trip.platesFound) plate\(trip.platesFound == 1 ? "" : "s") found on \(trip.name) will be un-collected. The trip itself stays."
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
                message: "It is marked finished and filed under Archived, so it stops "
                       + "appearing everywhere you pick a trip. Its \(trip.platesFound) "
                       + "plate\(trip.platesFound == 1 ? "" : "s") stay in your history, "
                       + "and you can reopen it whenever you like."
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
                message: "It stops appearing anywhere you pick a trip. Nothing is deleted \u{2014} its \(trip.platesFound) plate\(trip.platesFound == 1 ? "" : "s") stay in your history, and you can bring it back."
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
                message: "The trip and its \(trip.platesFound) collected plate\(trip.platesFound == 1 ? "" : "s") are removed for good."
            ) {
                PopupButton(title: "Delete trip", kind: .destructive) {
                    remove(trip)
                    popup.dismiss()
                }
                PopupButton(title: "Cancel") { popup.dismiss() }
            }
        }
    }

    /// Wipes the sightings, not the trip — `Sighting` is the only stored fact, so
    /// deleting them is all it takes to put every counter back to zero.
    private func wipe(_ trip: Trip) {
        for sighting in trip.allSightings { context.delete(sighting) }
        try? context.save()
        Haptics.destructive()
    }

    /// Finishing and archiving in one move.
    ///
    /// They were two separate actions and nobody wants two. A trip you are done
    /// with is a trip you are done seeing: leaving it finished but still in every
    /// picker meant the list only ever grew, which is how the switcher ended up
    /// taller than the phone. Reopening from the archive puts both halves back.
    private func finish(_ trip: Trip) {
        let now = Date()
        trip.endedAt = now
        trip.archivedAt = now
        try? context.save()
        if trip.id.uuidString == currentTripID { currentTripID = "" }
        Haptics.milestone()
    }

    private func setArchived(_ trip: Trip, _ archived: Bool) {
        trip.archivedAt = archived ? Date() : nil
        try? context.save()
        // `TripSelection.current` skips archived trips, so simply clearing the saved
        // id lets it fall through to the next playable one rather than leaving the
        // Drive screen pointed at something that is no longer on offer.
        if archived, trip.id.uuidString == currentTripID { currentTripID = "" }
        Haptics.selection()
    }

    private func remove(_ trip: Trip) {
        let wasCurrent = trip.id == current?.id
        context.delete(trip)
        try? context.save()
        // Leave the selection to fall through to the newest remaining trip rather
        // than pointing at something that no longer exists.
        if wasCurrent { currentTripID = "" }
        Haptics.destructive()
    }
}

// MARK: - Row

private struct TripRow: View {
    let trip: Trip
    let isCurrent: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

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

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(trip.name)
                            .font(.plates(size: 16, weight: .semibold))
                            .foregroundStyle(isCurrent ? Theme.route : Theme.ink)
                            .lineLimit(1)

                        if isCurrent {
                            Image(systemName: "car.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.route)
                                .accessibilityLabel("Currently playing")
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

                    Text(dateLabel)
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(trip.statesFound)")
                    .font(Theme.PlateFont.condensed(24))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("of \(Plate.stateTotal)")
                    .font(.plates(size: 10.5))
                    .foregroundStyle(Theme.inkMuted)
            }

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
    @AppStorage(TripSelection.key) private var currentTripID = ""

    let trip: Trip?
    let onClear: (() -> Void)?
    let onDelete: (() -> Void)?
    /// Nil hides the action — a new trip has nothing to archive yet.
    var onArchive: (() -> Void)?
    /// Marking a trip done also archives it, so it needs the same confirm-after-
    /// dismiss dance as the others.
    var onFinish: (() -> Void)?

    @State private var name = ""
    @State private var origin = Place()
    @State private var destination = Place()
    /// Overwritten in `onAppear` — from the trip being edited, or from `Trip`'s own
    /// default for a new one, so the picker and the model cannot disagree about what
    /// "default" means.
    @State private var mode: ScoringMode = .weighted
    @State private var includeTrucks = false
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

    /// Says plainly what pinning a place buys you, because the difference between
    /// typed text and a dropped pin is invisible otherwise.
    /// Nil where there is nothing useful to say. A locked trip with no pinned start
    /// would otherwise be told to go and pick one, which it cannot do.
    private var rarityNote: String? {
        if origin.isPinned {
            return isLocked
                ? "Rarity was scored against this route."
                : "Rarity is scored against this route \u{2014} plates from far away are worth more."
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

                        nameField

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
                        if isLocked {
                            scoringSummary
                        } else {
                            scoringPicker
                        }

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
            includeTrucks = trip?.includesTrucks ?? false
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

    /// What the picker would have said, in one line.
    private var scoringSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SCORING")
                .font(.plates(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            Text(mode.label + (includeTrucks ? " \u{00B7} trucks and SUVs counted"
                                             : " \u{00B7} cars only"))
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

                truckToggle
            }
        }
    }

    /// A square rather than a system Toggle, so it reads as one more option in the
    /// same list as the scoring radios instead of as a separate kind of control.
    private var truckToggle: some View {
        Button {
            includeTrucks.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: includeTrucks ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(includeTrucks ? Theme.route : Theme.inkMuted.opacity(0.5))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Count trucks and SUVs")
                        .font(.plates(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(includeTrucks
                         ? "Closer to what is on the road, but inflates states with cheap registration rules."
                         : "Rarity counts cars only. Pickups, SUVs and vans are ignored.")
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .strokeBorder(includeTrucks ? Theme.route : Theme.line,
                                      lineWidth: includeTrucks ? 1.5 : 1))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 3)
    }

    @ViewBuilder
    private var dangerZone: some View {
        VStack(spacing: 8) {
            if let trip {
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
                    // Not tinted red. Archiving loses nothing, and colouring it like
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

    private func rowLabel(_ title: String, symbol: String, tint: Color) -> some View {
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
            trip.scoringMode = mode
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
        target.includesTrucks = includeTrucks

        try? context.save()
        dismiss()
    }
}
