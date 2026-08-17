import SwiftData
import SwiftUI

/// The app's preferences, and the two permissions it can ask for.
///
/// Deliberately short. Almost everything that could be a setting here is already a
/// property of a *trip* — scoring mode, whether trucks count, which plates the grid
/// shows — and those belong to the trip because they change what its scores mean. A
/// switch flipped here would silently rewrite games already played.
///
/// **Controls and state, and nothing else.** It used to explain itself as it went:
/// what location tracking does to rarity, what a haptic feels like, where the
/// registration figures come from, what the model does and does not claim. All of it
/// true, none of it anything a person opens Settings to read — they come here to turn
/// something on. Every line now either reports a state or changes one.
struct SettingsScreen: View {
    @Environment(TourGuide.self) private var tour
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup

    private let backup = CloudBackup.shared
    private let location = TripLocation.shared

    @Query(sort: \Player.joinedAt) private var players: [Player]
    @State private var editingMe = false
    @State private var haptics = Haptics.isOn
    @State private var reminders = TripReminders.shared.isEnabled
    /// Permission can be withdrawn in Settings long after it was granted here, so
    /// the row asks the system rather than trusting its own switch.
    @State private var remindersBlocked = false

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
              ScrollViewReader { scroller in
                VStack(spacing: 18) {
                    identityCard
                        .tourAnchor(.settingsIdentity)
                        .tourStop(.settingsIdentity)
                    othersCard
                    backupCard
                        .tourAnchor(.settingsBackup)
                        .tourStop(.settingsBackup)
                    locationCard
                    remindersCard
                        .tourAnchor(.settingsReminders, prefersAbove: true)
                        .tourStop(.settingsReminders)
                    feedbackCard
                    version
                }
                .padding(Theme.screenPadding)
                .tourScrolling(scroller)
              }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tour.offer(.settings, stops: Tour.stops(of: .settings)) }
        .onDisappear { tour.left(.settings) }
        .sheet(isPresented: $editingMe) {
            // The same editor the roster used, which is why it outlived the roster:
            // it only ever edited one player, and one player is all there is now.
            // `onSaved` matters when `me` is nil, which is reachable: a fresh
            // install that skipped the welcome card has an empty roster, so this
            // sheet takes the editor's *insert* branch. Without adopting, the device
            // key is never written and `hasProfile` stays false — the identity
            // prompt returns on the next launch, and `resolve` keeps falling back to
            // earliest-joined, so the first party or shared book to deliver an older
            // player silently makes this phone into them.
            PlayerEditor(player: me,
                         usedColors: Set(players.filter { $0.id != me?.id }.map(\.colorIndex)),
                         onDelete: nil,
                         onSaved: { saved in
                             DevicePlayer.adopt(saved)
                             DevicePlayer.markProfileSet()
                         })
        }
        .tourLayer(.settings, Self.tourCopy)
    }

    /// What this screen's tour stops say. Out of the chain, not out of the
    /// file — see `coachLayer`.
    private static let tourCopy: [Tour.Stop: LocalizedStringResource] = [
        .settingsIdentity: "Who this phone plays as. In a party this is the name and the colored corner everyone else sees on the plates you call.",
        .settingsBackup: "Whether your collection exists anywhere but this phone. A book is years of spotting, so this is the row worth looking at.",
        .settingsReminders: "A quiet nudge if a trip goes untouched, so a drive you meant to finish does not sit open forever."
    ]

    // MARK: - Who this phone is

    /// The one identity this device plays as, and a control that changes it — which
    /// is why it belongs here rather than reading as an explanation.
    ///
    /// It carries a name and a color because both are seen by other people: in a
    /// party this is the chip on every plate you call and the row in everyone's
    /// standings. Setting it is the only preparation a party needs.
    private var identityCard: some View {
        SettingsGroup("Playing as") {
            Button {
                Haptics.selection()
                editingMe = true
            } label: {
                HStack(spacing: 12) {
                    if let me {
                        PlayerDot(me, size: 32)
                    } else {
                        PlayerDot(color: Theme.playerColor(0), text: "?", size: 32)
                    }

                    Text(me?.name ?? "Me")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted.opacity(0.55))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var me: Player? { DevicePlayer.resolve(from: players) }

    // MARK: - Everybody else

    /// Other people whose names have ended up in this phone's collections, and a way
    /// to remove one.
    ///
    /// Adding players by hand is gone and is not coming back — the party puts them
    /// there now. But *removal* had nowhere to live after the roster screen was
    /// retired, and it turns out to be needed: a party you joined once leaves its
    /// people in your store for good, and anything that ever reached your iCloud
    /// account stays until something deletes it. Somebody looking at a name they do
    /// not recognise needs a way to get rid of it.
    ///
    /// Safe by construction. `Player`'s delete rule is `.nullify`, so removing
    /// somebody does not un-collect a single plate — the sightings survive with no
    /// owner and every count stays exactly where it was. Only the standings lose a
    /// row. See `Player.sightings`.
    @ViewBuilder
    private var othersCard: some View {
        let others = players.filter { $0.id != me?.id }
        if !others.isEmpty {
            SettingsGroup("Other people") {
                ForEach(Array(others.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
                        PlayerDot(player, size: 26)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(player.name)
                                .font(.plates(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(plateCount(player))
                                .font(.plates(size: 12))
                                .foregroundStyle(Theme.inkMuted)
                        }

                        Spacer(minLength: 8)

                        Button { confirmRemoval(of: player) } label: {
                            Text("Remove")
                                .font(.plates(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
            }
        }
    }

    /// `String(localized:)` rather than a bare literal. This returns a `String`, so
    /// the compiler would otherwise harvest nothing from it — the same blind spot
    /// the popups had. Anything in this file that computes words for the screen goes
    /// through it.
    private func plateCount(_ player: Player) -> String {
        let n = player.sightings?.count ?? 0
        return n == 0 ? String(localized: "No plates on this phone")
                      : .inflected("^[\(n) plate](inflect: true) they spotted")
    }

    private func confirmRemoval(of player: Player) {
        Haptics.selection()
        popup.present(
            "Remove \(player.name)?",
            message: "Plates they spotted stay collected, and every count is unchanged. Only their line in the standings goes."
        ) {
            PopupButton(title: "Remove", kind: .destructive) {
                context.delete(player)
                try? context.save()
                Haptics.destructive()
                popup.dismiss()
            }
            PopupButton(title: "Cancel") { popup.dismiss() }
        }
    }

    // MARK: - iCloud

    /// Read-only, and it says what is actually true rather than what is configured.
    ///
    /// There is no switch here because there is nothing this app can toggle: iCloud
    /// sync is on when the entitlement, the account and the network all agree, and
    /// none of those are ours to change. Sending people to the Settings app is the
    /// honest affordance.
    private var backupCard: some View {
        SettingsGroup("Your collection") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: backup.state.symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(backup.state.isHealthy ? Theme.found : Theme.paint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(backup.state.title)
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(backup.state.detail)
                        .font(.plates(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            if case .noAccount = backup.state { openSettings("Open iCloud settings") }
        }
    }

    // MARK: - Location

    private var locationCard: some View {
        SettingsGroup("Location") {
            HStack {
                Text("Following the drive")
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 12)
                Text(locationTitle)
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)

            if !location.hasBeenAsked {
                SettingsDivider()
                Button {
                    Haptics.selection()
                    location.requestAccess()
                } label: {
                    rowLabel("Allow while using the app", tint: Theme.route)
                }
                .buttonStyle(.plain)
            } else if !location.isAuthorized {
                openSettings("Turn on in Settings")
            }
        }
    }

    private var locationTitle: LocalizedStringKey {
        if !location.hasBeenAsked { return "Not asked yet" }
        return location.isAuthorized ? "On while the app is open" : "Off"
    }

    // MARK: - Reminders

    /// The only notification the app sends, and it is off until somebody asks for
    /// it. See `TripReminders` for why this is a switch rather than a prompt.
    private var remindersCard: some View {
        SettingsGroup("Reminders") {
            Toggle(isOn: Binding(get: { reminders },
                                 set: { want in setReminders(want) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unfinished trips")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("A nudge if a trip goes a day without a plate.")
                        .font(.plates(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.route)
            .padding(14)

            if remindersBlocked {
                openSettings("Notifications are off in Settings")
            }
        }
        .task {
            // Asked on appear, so a permission revoked elsewhere shows up here
            // rather than leaving a switch that quietly does nothing.
            guard reminders else { return }
            remindersBlocked = await !TripReminders.shared.systemAllows()
        }
    }

    private func setReminders(_ want: Bool) {
        Haptics.selection()
        guard want else {
            TripReminders.shared.disable()
            reminders = false
            remindersBlocked = false
            return
        }
        Task {
            let granted = await TripReminders.shared.enable()
            reminders = granted
            remindersBlocked = !granted
            if granted { TripReminders.shared.refresh(in: context) }
        }
    }

    // NOTE: a "Voice" card used to sit here, carrying the Siri phrases verbatim. It
    // was never a setting — there was nothing on it to turn on or off — and it was
    // here only because a hands-free feature nobody knows the phrase for is a
    // feature nobody uses, and Settings was the only page anyone would look. It is
    // on the "How to play" page now, one row away in the same menu, alongside
    // everything else that explains rather than configures. Do not put it back on
    // the assumption that the phrases went missing.

    // MARK: - Haptics

    private var feedbackCard: some View {
        SettingsGroup("Feedback") {
            Toggle(isOn: $haptics) {
                Text("Haptics")
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.route)
            .padding(14)
            .onChange(of: haptics) { _, on in
                Haptics.isOn = on
                // Fire one on the way *on* so the switch demonstrates itself. Firing
                // on the way off would be the app ignoring what it was just told.
                if on { Haptics.selection() }
            }
        }
    }

    // NOTE: "Replay the tour" used to sit here, and is now the last card on the
    // "How to play" page. It ships in Release on purpose and that has not changed:
    // every other way to see the onboarding — the launch arguments, a wiped
    // simulator — needs a Mac and a debug build, so the one audience who cannot
    // check what a new player sees is anybody holding a real phone with a real
    // collection on it. That includes whoever is deciding whether the copy is any
    // good. See `HowToPlayScreen.replay`.

    // NOTE: a "Where the numbers come from" card used to sit here, carrying the data
    // sources, the limits of the rarity model, and a note that the plate artwork is
    // original. It is gone because Settings is for controls — but one line of it was
    // an obligation rather than commentary, and it now lives in the App Store
    // description instead. See the Sources section of `PlateRarity` for the exact
    // wording the Statistics Canada Open Licence asks for, and do not put it back
    // here on the assumption that it is missing.

    private var version: some View {
        let bundle = Bundle.main.infoDictionary
        let short = bundle?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle?["CFBundleVersion"] as? String ?? "1"
        return Text("Tags \(short) (\(build))")
            .font(.plates(size: 11.5))
            .foregroundStyle(Theme.inkMuted.opacity(0.8))
            .padding(.top, 2)
    }

    // MARK: - Bits

    private func openSettings(_ title: LocalizedStringKey) -> some View {
        Group {
            SettingsDivider()
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                rowLabel(title, tint: Theme.route)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ title: LocalizedStringKey, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.plates(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A titled card, in the shape the rest of the app already uses.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // `.textCase`, not `.uppercased()` — a key has no letters to raise
            // until it is resolved, and the modifier uppercases the *translation*.
            Text(title)
                .textCase(.uppercase)
                .font(Theme.PlateFont.condensed(12))
                .tracking(1.1)
                .foregroundStyle(Theme.inkMuted)
                .padding(.leading, 3)

            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }
}
