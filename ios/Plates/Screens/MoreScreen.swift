import SwiftUI

/// The fifth tab.
///
/// Players used to sit here directly, which worked only for as long as it was the
/// one thing that had nowhere else to go. A tab bar has five slots and the app has
/// more than five destinations, so this is the overflow: a plain list of the places
/// that do not earn a slot of their own.
struct MoreScreen: View {
    @Environment(Router.self) private var router
    @Environment(TourGuide.self) private var tour
    @State private var showTrail = false
    @State private var showSettings = false
    @State private var showParty = false
    @State private var showHowToPlay = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                  ScrollViewReader { scroller in
                    VStack(spacing: 20) {
                        // Grouped rather than one undifferentiated list. Three rows on
                        // an empty screen read as an oversight; two named groups read
                        // as the whole of what is here, which is the truth.
                        MoreSection(String(localized: "While you play")) {
                            MoreRow(title: "Party") { PartyScreen() }
                                .tourAnchor(.moreParty)

                            MoreDivider()

                            MoreRow(title: "Plate lookup") { PlateLookupScreen() }
                        }
                        .tourStop(.moreParty)

                        MoreSection(String(localized: "Looking back")) {
                            MoreRow(title: "Trail") { TrailScreen() }
                                .tourAnchor(.moreTrail)

                            MoreDivider()

                            MoreRow(title: "Historical plates") { HistoricalPlatesScreen() }
                        }
                        .tourStop(.moreTrail)

                        MoreSection(String(localized: "App")) {
                            // Above Settings, because it is the row somebody with a
                            // question wants and Settings is the row somebody with
                            // an intention wants. Questions come first.
                            MoreRow(title: "How to play") { HowToPlayScreen() }
                                .tourAnchor(.moreHowTo, prefersAbove: true)

                            MoreDivider()

                            MoreRow(title: "Settings") { SettingsScreen() }
                        }
                        .tourStop(.moreHowTo)

                        // Their own group rather than two more rows under App.
                        // Apple requires both to be reachable, and a reader
                        // scanning for them is scanning for the word every other
                        // app puts them under; buried under "App" between Settings
                        // and the wordmark they read as two more features.
                        MoreSection(String(localized: "Legal")) {
                            MoreRow(title: "Privacy Policy") { PrivacyPolicyScreen() }

                            MoreDivider()

                            MoreRow(title: "Terms and Conditions") { TermsScreen() }
                        }

                        // The agreement, on the record. The date is for the person;
                        // the version and fingerprint are for anybody who later needs
                        // to know which exact words were agreed to.
                        if let at = Consent.acceptedAt {
                            Text("Agreed \(at.formatted(date: .long, time: .shortened)). Version \(Legal.version), fingerprint \(Legal.shortFingerprint).")
                                .font(.plates(size: 11.5))
                                .foregroundStyle(Theme.inkMuted.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 3)
                                .padding(.top, -10)
                        }

                        footer
                    }
                    .padding(Theme.screenPadding)
                    .padding(.bottom, 8)
                    .tourScrolling(scroller)
                  }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showTrail) { TrailScreen() }
            .navigationDestination(isPresented: $showSettings) { SettingsScreen() }
            .navigationDestination(isPresented: $showParty) { PartyScreen() }
            .navigationDestination(isPresented: $showHowToPlay) { HowToPlayScreen() }
            // The receiving end of `Router.showTrail`: something elsewhere in the
            // app asked for the Trail, so push it. The Trail itself reads which
            // scope to open on. `onAppear` covers the jump that switched to this
            // tab; `onChange` covers a jump made while already standing on it.
            .onAppear {
                if router.pendingTrail != nil { showTrail = true }
                // Every stop here is a permanent row, so this tour is the one that
                // never has to ask what is on screen.
                tour.offer(.more, stops: Tour.stops(of: .more))
            }
            .onDisappear { tour.left(.more) }
            .onChange(of: router.pendingTrail) { _, pending in
                if pending != nil { showTrail = true }
            }
            #if DEBUG
            // `-tab more -openTrail` / `-openSettings` / `-openParty` /
            // `-howToPlay` push straight through, which is the only way to reach
            // any of them without a tap.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if args.contains("-openTrail") { showTrail = true }
                    if args.contains("-openSettings") { showSettings = true }
                    if args.contains("-openParty") { showParty = true }
                    if args.contains("-howToPlay") { showHowToPlay = true }
                }
            }
            #endif
        }
        // Last in the chain, so the scrim covers this screen and nothing else.
        .tourLayer(.more, Self.tourCopy)
    }

    /// What this screen's tour stops say. Out of the chain, not out of the
    /// file — see `coachLayer`.
    private static let tourCopy: [Tour.Stop: TourWords] = [
        .moreParty: TourWords("Party is here too",
                              "You can also start a Party here whenever you want to play with others. Everyone keeps their own phone, and what you all spot pools into one game."),
        .moreTrail: TourWords("Explore your Trail",
                              "See where you were when you collected each plate and look back on where the game has taken you."),
        .moreHowTo: TourWords("Need a refresher?",
                              "How to play is always here anytime you need a quick reminder.")
    ]

    /// The wordmark, and the thing that stops the last card floating in space.
    ///
    /// It used to carry a line explaining how rarity is judged. A menu is not where
    /// anyone reads that, and it made the bottom of the screen look like the end of a
    /// pamphlet rather than the end of a list.
    private var footer: some View {
        Text("TAGS")
            .font(Theme.PlateFont.condensed(15))
            .tracking(3)
            .foregroundStyle(Theme.inkMuted.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }
}

/// A titled group of rows.
struct MoreSection<Content: View>: View {
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

            MoreGroup { content }
        }
    }
}

/// A rounded group of rows, in the shape iOS settings-style lists have trained
/// everyone to read.
struct MoreGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MoreDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            // Inset to where the titles start, so the rows read as a list rather
            // than as three separate cards.
            .frame(height: 1)
            .padding(.leading, 15)
    }
}

/// Just the name and a chevron.
///
/// Each row used to carry a line of explanation under it — "Who is in the car",
/// "Describe one you saw". Five of those stacked up read as a form of hedging: a
/// menu that does not trust its own labels. "Players" and "Settings" need no gloss,
/// and the group headings above them already say which part of the app you are in.
struct MoreRow<Destination: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
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
            // A single line needs more air above and below it than two did, or the
            // rows sit tighter than the thumb aiming at them.
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
