import SwiftData
import SwiftUI

/// Settling who this phone is, once.
///
/// There are two ways a device arrives here with nobody claimed, and they need
/// different questions.
///
/// A genuinely new install has an empty store, so there is nothing to ask about: it
/// goes straight to the editor and types a name. That is the common case and it is
/// unchanged from when this was a bare `PlayerEditor`.
///
/// A *restored* install is the case this exists for. Nothing is seeded any more, so
/// the store fills from iCloud instead — and by the time there is a trip on screen to
/// prompt against, the people are usually there too. Those people include the person
/// this phone has always been. Offering them beats both of the alternatives: typing a
/// name again would fork the collection in two, and adopting one automatically would
/// mean guessing, which is how the old code handed somebody their party host's
/// identity. One tap on a face you recognise is the whole interaction.
///
/// "Someone else" is always available, because a shared book can put people in your
/// store who are not you and never were.
struct IdentityPrompt: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.joinedAt) private var players: [Player]

    /// What the confirm button says. The Game screen is starting a game; the party is
    /// on its way somewhere and says so.
    var saveLabel: LocalizedStringKey = "Start"
    var onDone: () -> Void = {}

    @State private var typingName = false

    var body: some View {
        if players.isEmpty || typingName {
            PlayerEditor(player: nil,
                         usedColors: Set(players.map(\.colorIndex)),
                         onDelete: nil,
                         title: "Who's playing?",
                         saveLabel: saveLabel,
                         // No `dismiss` here — the editor closes itself once it has
                         // saved, and asking the same sheet to go away twice is how
                         // you dismiss the screen behind it as well.
                         onSaved: adopt)
        } else {
            chooser
        }
    }

    // MARK: - Picking a face

    private var chooser: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        Text(players.count == 1
                             ? "This phone found somebody in your iCloud. Tap them to play as them."
                             : "These people are already in your iCloud. Tap whichever one is you.")
                            .font(.plates(size: 14))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)

                        ForEach(players) { player in
                            Button {
                                Haptics.selection()
                                claim(player)
                            } label: {
                                row(player)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Haptics.selection()
                            typingName = true
                        } label: {
                            Text("Someone else")
                                .font(.plates(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.route)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Who's playing?")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Sized to the roster rather than fixed. At the editor's 360 the "Someone
        // else" row sat half off the bottom edge, which reads as a sheet that failed
        // to load rather than one with a list in it. Capped, and the second detent
        // lets a long roster fill the screen — a family that has been in six parties
        // has more people in here than a phone is tall.
        .presentationDetents([.height(min(560, 200 + 72 * CGFloat(players.count))), .large])
    }

    private func row(_ player: Player) -> some View {
        HStack(spacing: 12) {
            PlayerDot(player, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.name)
                    .font(.plates(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                // The deciding detail. Two people called Sam are told apart by which
                // one has the four hundred plates.
                Text(plateCount(player))
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMuted.opacity(0.55))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
        )
        .contentShape(Rectangle())
    }

    private func plateCount(_ player: Player) -> String {
        let n = player.sightings?.count ?? 0
        return n == 0 ? String(localized: "No plates yet")
                      : .inflected("^[\(n) plate](inflect: true)")
    }

    /// The one write this whole flow exists to make.
    private func adopt(_ player: Player) {
        DevicePlayer.adopt(player)
        DevicePlayer.markProfileSet()
        onDone()
    }

    private func claim(_ player: Player) {
        adopt(player)
        dismiss()
    }
}

/// Editing one player: a name and a color.
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
    var title: LocalizedStringKey?
    var saveLabel: LocalizedStringKey?
    /// Handed the player that was saved, which for the first-run pass is the one it
    /// just inserted — `IdentityPrompt` has no other way to learn which row to pin
    /// this device to.
    var onSaved: ((Player) -> Void)? = nil

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
                        // wall to choose from and pushes the color row off the
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
                                            // already someone else's color
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
            // Through `PlayerDot`, like the other seven. This one is the avatar
            // *picker*, so drawing it by hand was the disagreement you could see
            // without leaving the screen: it used 20pt for an emoji and 15pt for an
            // initial where the component derives 22 and 24.8 at this diameter, so
            // the face you chose came out bigger than the face you were shown.
            // The initials option previews itself, using whatever has been typed so
            // far.
            PlayerDot(color: Theme.playerColor(colorIndex),
                      text: face ?? initialsPreview,
                      isEmoji: face != nil,
                      size: 40)
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
        let saved: Player
        if let player {
            player.name = trimmed
            player.colorIndex = colorIndex
            player.avatar = avatar
            saved = player
        } else {
            let fresh = Player(name: trimmed, colorIndex: colorIndex)
            fresh.avatar = avatar
            context.insert(fresh)
            saved = fresh
        }
        try? context.save()
        // Everyone in the car, right away. A rename used to sit on this phone until
        // the next connection handshake, which in a running party is never — so the
        // scoreboard beside you kept calling you by a name you had just changed.
        PartySession.shared?.announceMe(saved)
        onSaved?(saved)
        dismiss()
    }
}
