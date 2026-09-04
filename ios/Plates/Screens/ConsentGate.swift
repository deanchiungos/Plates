import SwiftUI

/// The documents, a button that says agree, and nothing to swipe past.
///
/// This is the one screen in the app whose job is to be *unavoidable*, which is the
/// opposite of everything the welcome card was designed to be, and it runs first so
/// that the welcome card can go on being a door. The things a court looks for are
/// all here on purpose: both documents one tap away and readable in full before
/// agreeing, the arbitration clause called out by name because it is the term most
/// often struck for being buried, the assent sentence directly above the button it
/// describes, and a button that says what pressing it does rather than "Continue".
///
/// The driving line is here as well as in the Terms. A warning inside a document
/// nobody opens is a warning on paper; one on the screen everybody has to pass is a
/// warning given.
struct ConsentGate: View {
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            wordmark
                            heading
                            documents
                            notices
                        }
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 28)
                        .padding(.bottom, 16)
                    }

                    footer
                }
            }
            .navigationBarHidden(true)
        }
        // A cover that can be pulled down is a gate with no latch.
        .interactiveDismissDisabled()
    }

    private var wordmark: some View {
        Text("TAGS")
            .font(Theme.PlateFont.condensed(22))
            .tracking(4)
            .foregroundStyle(Theme.inkMuted.opacity(0.75))
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Consent.isUpdate ? "Our terms have changed" : "Before you play")
                .font(.plates(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(Consent.isUpdate
                 ? "We have updated the Terms and Conditions and the Privacy Policy. Please read them and agree again to keep playing."
                 : "Two documents govern your use of TAGS. Read them here now, or any time later under More, then Legal.")
                .font(.plates(size: 15))
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var documents: some View {
        MoreGroup {
            NavigationLink { TermsScreen() } label: { row("Terms and Conditions") }
                .buttonStyle(.plain)
            MoreDivider()
            NavigationLink { PrivacyPolicyScreen() } label: { row("Privacy Policy") }
                .buttonStyle(.plain)
        }
    }

    private func row(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 13) {
            Text(title)
                .font(.plates(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMuted.opacity(0.55))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    /// The two things somebody should know even if they read nothing else.
    private var notices: some View {
        VStack(alignment: .leading, spacing: 12) {
            notice(symbol: "car.fill",
                   "Never use TAGS while driving. A passenger plays, or the driver waits until parked. Voice mode is for passengers too.")
            notice(symbol: "scale.3d",
                   "The Terms include an agreement to resolve disputes by individual arbitration and a waiver of class actions, in Section 19. You can opt out within 30 days of agreeing.")
            Text("Effective \(Legal.effectiveDate). Version \(Legal.version).")
                .font(.plates(size: 12))
                .foregroundStyle(Theme.inkMuted.opacity(0.8))
                .padding(.top, 2)
        }
    }

    private func notice(symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.route)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.plates(size: 13.5))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // Immediately above the button, and naming the button. Assent language a
            // screen away from the control it describes is the classic reason a
            // clickwrap fails.
            Text("By tapping Agree and continue, you agree to the Terms and Conditions and acknowledge the Privacy Policy. If you do not agree, do not use TAGS.")
                .font(.plates(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Consent.record()
                Haptics.selection()
                onAgree()
            } label: {
                Text("Agree and continue")
                    .font(.plates(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Theme.route))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.ground)
    }
}
