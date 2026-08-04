import SwiftUI
import SwiftData

struct PlayersScreen: View {
    /// True when pushed from the More tab, which already supplies a navigation
    /// stack and a title. Nesting a second one swallows the back button.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup

    @Query(sort: \Player.joinedAt) private var players: [Player]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    @State private var editing: Player?
    @State private var addingPlayer = false

    /// Acted on after the editor sheet closes — the popup layer is at the root,
    /// which a sheet covers, so confirming from inside the sheet would show
    /// nothing at all.
    @State private var pendingDelete: Player?

    /// Standings are for whatever is being filled, trip or book, so the numbers
    /// here always match the ones on the Drive screen.
    private var target: (any PlateCollection)? {
        PlaySelection.current(kind: targetKind, tripID: currentTripID,
                              bookID: currentBookID, trips: trips, books: books)?.collection
    }

    var body: some View {
        Group {
            if embedded { content } else { NavigationStack { content } }
        }
        .sheet(item: $editing, onDismiss: confirmPendingDelete) { player in
            PlayerEditor(player: player,
                         usedColors: usedColorIndices(excluding: player),
                         onDelete: { pendingDelete = player; editing = nil })
        }
        .sheet(isPresented: $addingPlayer) {
            PlayerEditor(player: nil,
                         usedColors: usedColorIndices(excluding: nil),
                         onDelete: nil)
        }
    }

    private var content: some View {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(players) { player in
                            Button { editing = player } label: {
                                PlayerRow(
                                    player: player,
                                    plates: target.map { platesSpotted(by: player, in: $0) } ?? 0,
                                    score: target?.score(for: player) ?? 0
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            addingPlayer = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Add player")
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

                        Text(footnote)
                            .font(.plates(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(embedded ? .inline : .large)
    }

    private var footnote: String {
        // Past six the palette wraps, so two people end up the same colour. Said
        // once, here, rather than blocking the seventh person from joining.
        if players.count > Theme.playerColors.count {
            return "Tap a plate on the Game screen and you will be asked who spotted it. "
                 + "With this many playing, some colours repeat."
        }
        return players.count > 1
            ? "Tap a plate on the Game screen and you will be asked who spotted it."
            : "Add someone to play together in the car. With one player, plates are collected without asking."
    }

    private func confirmPendingDelete() {
        guard let player = pendingDelete else { return }
        pendingDelete = nil

        popup.present(
            "Remove \(player.name)?",
            message: "Plates they spotted stay collected. Only their points are removed from the standings."
        ) {
            PopupButton(title: "Remove", kind: .destructive) {
                remove(player)
                popup.dismiss()
            }
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    private func platesSpotted(by player: Player, in collection: any PlateCollection) -> Int {
        Set(collection.allSightings
            .filter { $0.player?.id == player.id }
            .map(\.plateCode)).count
    }

    private func usedColorIndices(excluding player: Player?) -> Set<Int> {
        Set(players.filter { $0.id != player?.id }.map(\.colorIndex))
    }

    private func remove(_ player: Player) {
        context.delete(player)
        try? context.save()
        Haptics.destructive()
    }
}

private struct PlayerRow: View {
    let player: Player
    let plates: Int
    let score: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.playerColor(player.colorIndex))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(player.initial)
                        .font(Theme.PlateFont.condensed(17))
                        .foregroundStyle(Theme.ink)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.plates(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(plates) plate\(plates == 1 ? "" : "s") collected")
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer()

            Text("\(score)")
                .font(Theme.PlateFont.condensed(22))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMuted.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
        )
    }
}

/// Add and edit share one sheet — the only difference is whether `player` exists.
/// Not private: the Game screen presents it too, so you can add someone without
/// leaving the grid mid-trip.
struct PlayerEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let player: Player?
    let usedColors: Set<Int>
    let onDelete: (() -> Void)?

    @State private var name = ""
    @State private var colorIndex = 0
    @FocusState private var focused: Bool

    private var isNew: Bool { player == nil }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("NAME")
                            .font(.plates(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)

                        TextField("Who is playing?", text: $name)
                            .focused($focused)
                            .font(.plates(size: 17))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.line, lineWidth: 1))
                            )
                            .submitLabel(.done)
                            .onSubmit(save)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("COLOUR")
                            .font(.plates(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)

                        HStack(spacing: 10) {
                            ForEach(0..<Theme.playerColors.count, id: \.self) { i in
                                let taken = usedColors.contains(i)
                                Button {
                                    colorIndex = i
                                } label: {
                                    Circle()
                                        .fill(Theme.playerColor(i))
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle().strokeBorder(Theme.ink,
                                                                  lineWidth: colorIndex == i ? 2.5 : 0)
                                        )
                                        .overlay(
                                            // already someone else's colour
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Theme.ink.opacity(0.45))
                                                .opacity(taken ? 1 : 0)
                                        )
                                        .opacity(taken && colorIndex != i ? 0.4 : 1)
                                }
                                .accessibilityLabel("Colour \(i + 1)\(taken ? ", already taken" : "")")
                            }
                        }
                    }

                    if let onDelete {
                        Button(role: .destructive) { onDelete() } label: {
                            Text("Remove player")
                                .font(.plates(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                        )
                    }

                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle(isNew ? "Add player" : "Edit player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.height(360)])
        .onAppear {
            name = player?.name ?? ""
            colorIndex = player?.colorIndex ?? firstFreeColor()
            if isNew { focused = true }
        }
    }

    private func firstFreeColor() -> Int {
        (0..<Theme.playerColors.count).first { !usedColors.contains($0) } ?? 0
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let player {
            player.name = trimmed
            player.colorIndex = colorIndex
        } else {
            context.insert(Player(name: trimmed, colorIndex: colorIndex))
        }
        try? context.save()
        dismiss()
    }
}
