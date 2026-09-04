import SwiftData
import SwiftUI

/// What you can do about somebody else.
///
/// One sheet rather than two, because report and block are the same decision made
/// with different force and separating them costs a person a second navigation at
/// the moment they are least patient. It opens from the two places another person's
/// name can appear on this phone: the "Other people" list in Settings, and the party
/// roster.
///
/// The order is deliberate. Report is first and blocking is underneath it, because
/// the case where somebody wants us to know is the case worth making easy; a block
/// helps only the person who made it. Both are available without the other.
struct PersonSheet: View {
    let player: Player

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var reason: Moderation.Reason?
    @State private var note = ""
    @State private var confirmingBlock = false
    @State private var copiedAddress = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        reportCard
                        blockCard
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("About \(player.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.plates(size: 15, weight: .semibold))
                }
            }
            .confirmationDialog("Block \(player.name)?",
                                isPresented: $confirmingBlock,
                                titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    Moderation.block(player, in: context)
                    Haptics.destructive()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Their plates come off your grid, your counts and the standings, and nothing new from them arrives. Nothing is deleted, so unblocking puts it all back.")
            }
        }
    }

    // MARK: - Who

    private var header: some View {
        HStack(spacing: 12) {
            PlayerDot(player, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.plates(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(player.isBlocked
                     ? String(localized: "Blocked")
                     : plateCount)
                    .font(.plates(size: 12.5))
                    .foregroundStyle(player.isBlocked ? .red : Theme.inkMuted)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Their whole contribution, blocked or not, which is the number this screen is
    /// about. Everywhere else in the app this count goes through
    /// `allSightings` and would read zero for somebody already blocked.
    private var plateCount: String {
        let n = player.sightings?.count ?? 0
        return n == 0 ? String(localized: "No plates on this phone")
                      : .inflected("^[\(n) plate](inflect: true) they added")
    }

    // MARK: - Report

    private var reportCard: some View {
        SettingsGroup("Report to TAGS") {
            ForEach(Array(Moderation.Reason.allCases.enumerated()), id: \.element.id) { index, option in
                if index > 0 { SettingsDivider() }
                Button {
                    Haptics.selection()
                    reason = (reason == option) ? nil : option
                } label: {
                    HStack(spacing: 10) {
                        Text(option.title)
                            .font(.plates(size: 14.5))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: reason == option
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(reason == option ? Theme.route
                                                              : Theme.inkMuted.opacity(0.4))
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            SettingsDivider()

            // Optional on purpose. A required field is a wall in front of the one
            // control on this page that has to work when somebody is upset.
            TextField("What happened? (optional)", text: $note, axis: .vertical)
                .font(.plates(size: 14.5))
                .foregroundStyle(Theme.ink)
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
                .padding(14)

            SettingsDivider()

            if Moderation.canSendMail {
                Button {
                    guard let reason, let url = Moderation.mail(about: player,
                                                                reason: reason,
                                                                note: note) else { return }
                    Haptics.selection()
                    openURL(url)
                } label: {
                    Text("Send report")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(reason == nil ? Theme.inkMuted : Theme.route)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(reason == nil)
            } else {
                // No mail client will take a `mailto:`. Offering the address is the
                // only remaining honest move; a button that opens nothing would let
                // somebody believe they had reported something.
                Button {
                    UIPasteboard.general.string = Moderation.mailbox
                    copiedAddress = true
                    Haptics.selection()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(copiedAddress ? "Address copied" : "Copy our address")
                            .font(.plates(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.route)
                        Text("No mail app is set up on this phone. Write to \(Moderation.mailbox) and mention \(player.name).")
                            .font(.plates(size: 12))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Block

    private var blockCard: some View {
        SettingsGroup("Blocking") {
            Text(player.isBlocked
                 ? "Their plates are hidden from your grid, your counts and the standings, and nothing new from them is accepted."
                 : "Blocking hides everything they have added and refuses anything new. Nothing is deleted and you can undo it here.")
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

            SettingsDivider()

            Button {
                if player.isBlocked {
                    Moderation.unblock(player, in: context)
                    Haptics.selection()
                } else {
                    confirmingBlock = true
                }
            } label: {
                Text(player.isBlocked ? "Unblock" : "Block")
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(player.isBlocked ? Theme.route : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
