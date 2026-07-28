import SwiftUI
import SwiftData

struct PlayersScreen: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Player.joinedAt) private var players: [Player]
    @Query(filter: #Predicate<Trip> { $0.endedAt == nil },
           sort: \Trip.startedAt, order: .reverse)
    private var activeTrips: [Trip]

    @State private var editing: Player?
    @State private var addingPlayer = false
    @State private var pendingDelete: Player?

    private var trip: Trip? { activeTrips.first }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(players) { player in
                            Button { editing = player } label: {
                                PlayerRow(
                                    player: player,
                                    plates: trip.map { platesSpotted(by: player, in: $0) } ?? 0,
                                    score: trip?.score(for: player) ?? 0
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
                                    .font(.system(size: 15, weight: .semibold))
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

                        Text(players.count > 1
                             ? "Tap a plate on the Game screen and you will be asked who spotted it."
                             : "Add someone to play together in the car. With one player, plates are collected without asking.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                    }
                    .padding(Theme.screenPadding)
                }
            }
            .navigationTitle("Players")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $editing) { player in
            PlayerEditor(player: player,
                         usedColors: usedColorIndices(excluding: player),
                         onDelete: { pendingDelete = player; editing = nil })
        }
        .sheet(isPresented: $addingPlayer) {
            PlayerEditor(player: nil,
                         usedColors: usedColorIndices(excluding: nil),
                         onDelete: nil)
        }
        .confirmationDialog(
            pendingDelete.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let p = pendingDelete { remove(p) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Plates they spotted stay collected on the trip. Only their points are removed from the standings.")
        }
    }

    private func platesSpotted(by player: Player, in trip: Trip) -> Int {
        Set(trip.allSightings
            .filter { $0.player?.id == player.id }
            .map(\.plateCode)).count
    }

    private func usedColorIndices(excluding player: Player?) -> Set<Int> {
        Set(players.filter { $0.id != player?.id }.map(\.colorIndex))
    }

    private func remove(_ player: Player) {
        context.delete(player)
        try? context.save()
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(plates) plate\(plates == 1 ? "" : "s") this trip")
                    .font(.system(size: 12.5))
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
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)

                        TextField("Who is playing?", text: $name)
                            .focused($focused)
                            .font(.system(size: 17))
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
                            .font(.system(size: 11, weight: .bold))
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
                                .font(.system(size: 15, weight: .semibold))
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
