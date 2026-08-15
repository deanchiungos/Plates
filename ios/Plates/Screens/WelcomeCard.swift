import SwiftUI

/// The first thing a new install shows, and the only screen in the app that exists
/// purely to be read.
///
/// One card, not a deck. A paged tour with dots is the house style of apps that have
/// not worked out what they are for — it asks four screens of attention before
/// anything has been earned, and the honest expectation here is that nobody reads
/// past the first sentence anyway. So there is one sentence pair, a picture of the
/// thing the app is about, and a button.
///
/// "Play" and "Skip" go to nearly the same place, which is deliberate. The card is a
/// door, not a gate; Skip exists so that it reads as a choice rather than a toll, and
/// the real difference between them is only whether the app asks your name on the way
/// through.
///
/// What is deliberately not here: feature bullets, page dots, a gradient, an
/// illustration drawn for onboarding, the word "welcome", and any promise about what
/// the app will do for you. A plate and two lines is the whole pitch.
struct WelcomeCard: View {
    let onPlay: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            // Two flexible spacers and nothing else, so the plate, the wordmark and
            // the sentence read as one object centred above the buttons. The first
            // attempt spaced all three apart independently, which left the plate
            // marooned at the top of the screen and a hand's width of cream between
            // it and its own title.
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                plate
                    .padding(.bottom, 30)

                // The More tab's wordmark treatment, at the size it would be if it
                // were ever the subject rather than a footer.
                Text("PLATES")
                    .font(Theme.PlateFont.condensed(44))
                    .tracking(7)
                    .foregroundStyle(Theme.ink)

                Text("Spot license plates on the road. Tap them here, and try to collect all 50 states.")
                    .font(.plates(size: 16))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)

                Spacer(minLength: 12)

                buttons
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
    }

    /// A real tile from the real grid, at a size it is never otherwise drawn.
    ///
    /// Reusing `PlateTile` rather than drawing something prettier for this screen is
    /// the point: the first plate somebody sees is exactly the object they will be
    /// tapping a minute later, in the same shape and the same colors. An onboarding
    /// illustration that does not appear anywhere else in the app teaches nothing and
    /// has to be maintained forever.
    ///
    /// Arizona because it is one of the handsomer pieces of artwork in the catalogue
    /// and reads at a glance as a *place* rather than as a rectangle with letters. The
    /// tilt is the whole of the styling — a plate tossed on a table. No shadow: the
    /// coach balloon is the app's one lifted object, and a second one here would make
    /// both mean less.
    @ViewBuilder
    private var plate: some View {
        if let arizona = Plate.plate(for: "AZ") {
            PlateTile(plate: arizona, isFound: true, rarity: 6)
                .frame(width: 236, height: 236 / Theme.tileAspect)
                .rotationEffect(.degrees(-4))
                .accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button(action: onPlay) {
                Text("Play")
                    .font(.plates(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Theme.route))
            }
            .buttonStyle(.plain)

            Button(action: onSkip) {
                Text("Skip")
                    .font(.plates(size: 15))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }
}
