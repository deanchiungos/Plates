import SwiftData
import SwiftUI

/// Editing one player: a name and a colour.
///
/// This file used to hold a roster too — a list of everyone on the phone, an "add
/// player" button, and a remove flow — and that is what the party replaced. The
/// editor outlived it because it never had anything to do with the roster: it edits
/// a single player, and a single player is now the whole of what a device has.
/// Settings presents it as "Playing as".
///
/// Still handles `player == nil` by inserting a new one. Nothing reaches it that
/// way today, and the branch is two lines that keep it honest as an editor rather
/// than something that only works on one row.
struct PlayerEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let player: Player?
    let usedColors: Set<Int>
    let onDelete: (() -> Void)?
    /// Overrides the title, for the first-run "who's playing?" pass where "Edit
    /// player" would be describing a screen nobody has seen yet.
    var title: String? = nil
    var saveLabel: String? = nil
    var onSaved: (() -> Void)? = nil

    @State private var name = ""
    @State private var colorIndex = 0
    @State private var avatar: String?
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
                        Text("FACE")
                            .font(.plates(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)

                        // Scrolls rather than wrapping. A grid of twenty emoji is a
                        // wall to choose from and pushes the colour row off the
                        // sheet; one row you flick through reads as a choice.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                faceOption(nil)
                                ForEach(Self.faces.filter(Glyphs.canDraw), id: \.self) { faceOption($0) }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("COLOR")
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
                                .accessibilityLabel("Color \(i + 1)\(taken ? ", already taken" : "")")
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
            .navigationTitle(title ?? (isNew ? "Add player" : "Edit player"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel ?? (isNew ? "Add" : "Save"), action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.height(360)])
        .onAppear {
            name = player?.name ?? ""
            colorIndex = player?.colorIndex ?? firstFreeColor()
            avatar = player?.avatar
            if isNew { focused = true }
        }
    }

    /// Deliberately a short, curated list rather than the system emoji keyboard.
    ///
    /// The keyboard offers several thousand, most of which are illegible at twelve
    /// points on a plate tile and a good number of which you would not want a
    /// nine-year-old picking as their name in a shared book. These are chosen for
    /// being distinguishable from each other as *silhouettes* — the size they are
    /// usually seen at is too small to read detail.
    private static let faces = ["🦊", "🐻", "🐸", "🦉", "🐙", "🦄", "🐢", "🐝",
                                "🚗", "🚙", "🚐", "🛻", "🚀", "⭐️", "⚡️", "🌵",
                                "🌊", "🍕", "🎸", "⚽️"]

    private func faceOption(_ face: String?) -> some View {
        let picked = avatar == face
        return Button {
            avatar = face
            Haptics.selection()
        } label: {
            Circle()
                .fill(Theme.playerColor(colorIndex))
                .frame(width: 40, height: 40)
                .overlay(
                    Group {
                        if let face {
                            Text(face).font(.system(size: 20))
                        } else {
                            // The initials option previews itself, using whatever has
                            // been typed so far.
                            Text(initialsPreview)
                                .font(Theme.PlateFont.glyph(15))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                )
                .overlay(
                    Circle().strokeBorder(Theme.ink, lineWidth: picked ? 2.5 : 0)
                )
                .opacity(picked ? 1 : 0.55)
        }
        .accessibilityLabel(face ?? "Initials")
        .accessibilityAddTraits(picked ? [.isSelected] : [])
    }

    private var initialsPreview: String {
        let words = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 { return (words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return trimmed.isEmpty ? "AB" : String(trimmed.prefix(2)).uppercased()
    }

    private func firstFreeColor() -> Int {
        (0..<Theme.playerColors.count).first { !usedColors.contains($0) } ?? 0
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let player {
            player.name = trimmed
            player.colorIndex = colorIndex
            player.avatar = avatar
        } else {
            let fresh = Player(name: trimmed, colorIndex: colorIndex)
            fresh.avatar = avatar
            context.insert(fresh)
        }
        try? context.save()
        onSaved?()
        dismiss()
    }
}
