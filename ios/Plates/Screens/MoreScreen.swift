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
        .tourLayer(.more, [
            .moreParty: "Everyone in the car keeps their own phone. Start a Party here and your plates pool into one score.",
            .moreTrail: "The Trail is the map of where you actually were when you spotted each plate.",
            .moreHowTo: "That is the whole app. Everything you have just been shown lives in here, any time you want it again."
        ])
    }

    /// The wordmark, and the thing that stops the last card floating in space.
    ///
    /// It used to carry a line explaining how rarity is judged. A menu is not where
    /// anyone reads that, and it made the bottom of the screen look like the end of a
    /// pamphlet rather than the end of a list.
    private var footer: some View {
        Text("PLATES")
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
