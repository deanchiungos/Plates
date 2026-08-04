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
    private let backup = CloudBackup.shared
    private let location = TripLocation.shared

    @State private var haptics = Haptics.isOn

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    backupCard
                    locationCard
                    voiceCard
                    feedbackCard
                    version
                }
                .padding(Theme.screenPadding)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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

    private var locationTitle: String {
        if !location.hasBeenAsked { return "Not asked yet" }
        return location.isAuthorized ? "On while the app is open" : "Off"
    }

    // MARK: - Voice

    /// Not a setting — there is nothing to configure. It is here because a hands-free
    /// feature nobody knows the phrase for is a feature nobody uses, and Settings is
    /// where people go looking. The toggle that used to live here ("start listening
    /// when Plates opens") is gone: a plain launch cannot be told apart from tapping
    /// the icon, so honouring it meant opening the microphone every single time.
    private var voiceCard: some View {
        SettingsGroup("Voice") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hands free")
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Say \u{201C}Hey Siri, log a plate in Plates\u{201D} \u{2014} or name it outright, \u{201C}log New Jersey in Plates\u{201D}. Either one opens voice mode and keeps listening, so the rest of the trip needs no phone at all. Say \u{201C}stop\u{201D} when you are done.")
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

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
        return Text("Plates \(short) (\(build))")
            .font(.plates(size: 11.5))
            .foregroundStyle(Theme.inkMuted.opacity(0.8))
            .padding(.top, 2)
    }

    // MARK: - Bits

    private func openSettings(_ title: String) -> some View {
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

    private func rowLabel(_ title: String, tint: Color) -> some View {
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
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
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
