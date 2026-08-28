import Foundation
import Observation
import SwiftUI

/// The guided walk through one tab, run the first time that tab is opened.
///
/// This is deliberately the opposite of `Coach`, and the two are meant to be read
/// together. A coach mark is an *aside*: it interrupts nothing, points at one control,
/// and is happily ignored. A tour is a *sequence*: it dims the page, takes the
/// scrolling away from you, and does not finish until you have been shown every part
/// of the screen you are standing on. `Coach`'s own note says there is no tour, no step
/// counter, no ordering — that stays true of `Coach`. This is the other thing, kept in
/// its own file so neither has to grow conditionals about the other.
///
/// **Why per tab rather than one long tour.** A single walkthrough at first launch has
/// to explain five screens to somebody who has not yet seen one of them, and it spends
/// its best moment — the only moment anybody is actually paying attention — on the tab
/// they have not opened. Splitting it means each part arrives when it is about the
/// thing in front of you, and somebody who never opens the Map is never taught the Map.
///
/// **What "seen" means here.** A whole screen's tour, not a step. Abandoning halfway
/// still spends it: a tour that resumes from step 3 a week later is a worse experience
/// than one that does not come back, and "Replay the tour" exists for the person who
/// genuinely wants it again. See `TourGuide.stop(restoring:)`.
///
/// `UserDefaults` rather than the ubiquitous store, for the same reason as `Coach`:
/// this is about a hand that has been walked through the app, not an account.
enum Tour {

    /// One per screen that walks you round itself. The raw values are ledger keys, so
    /// they are not renamed casually.
    enum Screen: String, CaseIterable {
        /// The five with a slot in the tab bar.
        case game, map, books, trips, more
        /// The four that are pushed from More. Same machinery, one behavioural
        /// difference: they take no part in the finale. See `isComplete`.
        case party, trail, settings, lookup

        static let tabs: [Screen] = [.game, .map, .books, .trips, .more]

        var isTab: Bool { Screen.tabs.contains(self) }

        /// Where this screen sits in the tab bar, for the hand-off at the end of a
        /// tour. Nil for the four that are pushed rather than tabbed.
        var tabIndex: Int? {
            Screen.tabs.firstIndex(of: self)
        }

        /// What the tab bar calls it, for "Go to Map" on the last stop.
        var tabName: String {
            switch self {
            case .game: String(localized: "Game")
            case .map: String(localized: "Map")
            case .books: String(localized: "Books")
            case .trips: String(localized: "Trips")
            case .more: String(localized: "More")
            default: ""
            }
        }
    }

    /// One per thing a tour stops to point at.
    ///
    /// The ordering inside a screen is the ordering on screen, top to bottom, because
    /// the tour scrolls between them and a sequence that jumps back up the page reads
    /// as a fault rather than as a tour.
    enum Stop: String, CaseIterable {
        // Game
        case gameTarget         // the trip/book card: what you are filling
        case gameVoice          // the waveform button
        case gameFilter         // the filter chip
        case gameGrid           // the first unfound tile: the whole game
        case gameParty          // the party link, or the standings strip

        // Map
        case mapMode            // found / rarity
        case mapRegion          // a region is tappable
        case mapLegend          // what the colors mean

        // Books
        case booksScope         // which book, or all time
        case booksShare         // the poster button
        case booksAlbum         // the album itself

        // Trips
        case tripsIntro         // what a Trip is, before any of the controls
        case tripsNew           // start one
        case tripsRow           // swipe for pin and done
        case tripsFinished      // where they file themselves

        // More
        case moreParty
        case moreTrail
        case moreHowTo          // the last stop of the last tab tour

        // Party
        case partyWhat          // what a party actually is
        case partyHost          // start one for this trip
        case partyJoin          // or get into somebody else's

        // Trail
        case trailScopeBar      // which drive the map is showing
        case trailMap           // the pins
        case trailSummary       // the numbers under it

        // Settings
        case settingsIdentity   // who this phone is
        case settingsBackup     // whether any of it is safe
        case settingsReminders  // the nudge

        // Plate lookup
        case lookupField        // describe what went past
        case lookupHints        // what is worth describing

        var screen: Screen {
            switch self {
            case .gameTarget, .gameVoice, .gameFilter, .gameGrid, .gameParty: .game
            case .mapMode, .mapRegion, .mapLegend: .map
            case .booksScope, .booksShare, .booksAlbum: .books
            case .tripsIntro, .tripsNew, .tripsRow, .tripsFinished: .trips
            case .moreParty, .moreTrail, .moreHowTo: .more
            case .partyWhat, .partyHost, .partyJoin: .party
            case .trailScopeBar, .trailMap, .trailSummary: .trail
            case .settingsIdentity, .settingsBackup, .settingsReminders: .settings
            case .lookupField, .lookupHints: .lookup
            }
        }

        /// The `.id` a screen puts on the container holding this stop, so the tour can
        /// scroll it into view before pointing at it.
        ///
        /// Derived rather than declared so the two ends cannot drift apart: a screen
        /// writes `.tourStop(.gameGrid)` and the guide scrolls to `.gameGrid`, and
        /// there is no third place holding a string that has to match both.
        var scrollID: String { "tour.\(rawValue)" }

        /// Where the stop comes to rest in the viewport.
        ///
        /// Centre for anything card-sized, which is most of them: it leaves the
        /// placement arithmetic room on both sides to put the bubble. Top for the
        /// three stops whose container is a whole section — an album, a grid of fifty
        /// tiles — because centring something four screens tall scrolls its first row
        /// off the top, and the first row is the part being pointed at.
        var scrollAnchor: UnitPoint {
            switch self {
            case .gameGrid, .booksAlbum, .tripsFinished: .top
            default: .center
            }
        }
    }

    /// The stops of one screen, in order.
    static func stops(of screen: Screen) -> [Stop] {
        Stop.allCases.filter { $0.screen == screen }
    }

    // MARK: - Ledger

    private static let ledger = SeenLedger<Screen>(prefix: "tour")

    static func seen(_ screen: Screen) -> Bool { ledger.seen(screen) }

    static func markSeen(_ screen: Screen) { ledger.markSeen(screen) }

    /// True once every *tab* has been walked through.
    ///
    /// What the last tour checks to know it is the last one. The final stop of the
    /// final screen is the only place the app says "that is everything", and saying it
    /// after the Map tour because the Map happened to be opened last would be a lie.
    ///
    /// The four pushed screens are deliberately excluded. Somebody may never open
    /// Settings, and a finale that waits on them would simply never arrive; and a tour
    /// that ends three levels deep in a navigation stack has no business throwing the
    /// reader back to the first tab, which is what the finale does. Those tours put
    /// their own screen back and stop there.
    static var isComplete: Bool { Screen.tabs.allSatisfy(seen) }

    /// Every screen, tabs and pushed alike.
    static func markAllSeen() { ledger.markSeen(Screen.allCases) }

    static func reset() { ledger.reset() }

    #if DEBUG
    /// `-tour map` forces one screen's tour to run whatever the ledger says, which is
    /// the only way to photograph a sequence that by definition happens once.
    /// `-tourReset` wipes the ledger at launch, for running the whole thing again
    /// without reinstalling.
    static var forced: Screen? { ledger.forced(by: "-tour") }

    /// `-tourStep 3` opens a tour already advanced, so a stop in the middle of a
    /// sequence can be looked at without tapping Next to reach it.
    static var forcedStep: Int {
        max(0, LaunchFlags.value(after: "-tourStep").flatMap(Int.init) ?? 0)
    }

    static func applyLaunchArguments() {
        if LaunchFlags.isSet("-tourReset") { reset() }
    }
    #endif
}

/// Which tour is running, and how far through it is.
///
/// One at a time, app-wide, for the same reason `CoachPresenter` allows one balloon:
/// two sequences both scrolling the same page is not a tour, it is a fight. Switching
/// tabs mid-tour ends the running one rather than pausing it — see `left(_:)`.
@MainActor
@Observable
final class TourGuide {

    /// The screen being walked through, or nil.
    private(set) var screen: Tour.Screen?

    /// How far through `route` we are.
    private(set) var index = 0

    /// The stops this run will actually visit.
    ///
    /// Handed in by the screen rather than taken from `Tour.stops(of:)`, because half
    /// of them are about things that may not be on screen: there is no trip row to
    /// swipe in an empty Trips tab, and no Finished section until something has
    /// finished. A tour that points at furniture which is not there is worse than a
    /// tour with two stops.
    private(set) var route: [Tour.Stop] = []

    /// The stop being pointed at right now.
    var stop: Tour.Stop? {
        guard screen != nil, route.indices.contains(index) else { return nil }
        return route[index]
    }

    var isFirst: Bool { index == 0 }
    var isLast: Bool { index >= route.count - 1 }

    /// One-based, for the "2 of 5" the bubble draws.
    var step: Int { index + 1 }
    var total: Int { route.count }

    /// Whether a tour is up anywhere in the app.
    ///
    /// Static because the one thing that needs to ask is `CoachPresenter`, which is a
    /// sibling rather than a parent and has no reference to this. The alternative was
    /// passing the guide into the presenter, which couples the small honest thing to
    /// the large interrupting one to answer a question that is really about the app as
    /// a whole: is something already talking?
    private(set) static var isRunning = false

    /// Bumped when a tour finishes, so screens can put themselves back.
    ///
    /// The "clean slate" half of the feature, and it is a counter rather than a flag
    /// for the same reason `replayRequest` is: a screen consumes it by reacting, not
    /// by resetting it, and two tours in one session must both land.
    private(set) var restoreRequest = 0

    /// The tab to hand off to when this tour reaches its end.
    ///
    /// What turns nine separate tours into one walk through the app. Somebody who has
    /// just been shown the Game tab has no particular reason to guess that the Map is
    /// also worth a look, and the tab bar is five identical little icons until you have
    /// opened them. So the last stop stops saying "Done" and starts saying "Go to Map",
    /// which both finishes this tour and starts the next one.
    ///
    /// Nil once every tab has been walked, which is what lets the last one say "Done"
    /// and mean it. Nil for the pushed screens too: they are reached from a row on the
    /// More tab, and throwing somebody out to a tab bar from three levels deep is not a
    /// hand-off, it is losing their place.
    var nextTab: Tour.Screen? {
        guard let screen, screen.isTab else { return nil }
        return Tour.Screen.tabs.first { $0 != screen && !Tour.seen($0) }
    }

    /// Which screen the last `restoreRequest` was for. Read by the scroll drivers,
    /// which all hear every request and need to know whether it was theirs.
    private(set) var restoredScreen: Tour.Screen?

    /// Set while the final tour is ending, so the root can go back to the first tab.
    private(set) var finishedEverything = false

    /// Nothing starts while this is true. Raised by the root while the welcome card is
    /// up: the card is already an interruption, and a tour that begins underneath it
    /// dims a screen nobody has been shown yet.
    var isSuspended = false {
        didSet {
            guard oldValue, !isSuspended, let (screen, stops) = deferred else { return }
            deferred = nil
            offer(screen, stops: stops)
        }
    }

    /// A tour that was offered while the welcome card was up, kept so it can be run the
    /// moment the card goes.
    ///
    /// The alternative was gating on `Coach.seen(.welcome)`, which reads as the same
    /// rule and is not. That card is deliberately not shown to a *restored* install —
    /// a new phone on an old iCloud account, whose players arrive by sync — so the tip
    /// is never marked, and gating on it would mean the one person who has never seen
    /// this app on this device is the one person the tour never runs for. Suspension is
    /// about what is on screen right now, which is the thing actually being avoided.
    private var deferred: (Tour.Screen, [Tour.Stop])?

    /// Long enough for a tab to finish arriving and its list to lay out. Deliberately
    /// longer than `CoachPresenter.settle`: a balloon appearing beside a control is
    /// forgiving about arriving early, and a scrim that drops over a screen still
    /// sliding in is not.
    private let settle: TimeInterval = 0.75

    private var pending: Tour.Screen?

    // MARK: - Running

    /// A tab appeared and is offering to walk through itself.
    ///
    /// Safe to call from `onAppear` every time: the guards make repeat calls free,
    /// which is what lets a screen state this as a plain fact about itself rather than
    /// as an event it has to fire exactly once.
    func offer(_ screen: Tour.Screen, stops: [Tour.Stop]) {
        guard self.screen == nil, pending == nil else { return }
        guard !isSuspended else {
            if !Tour.seen(screen), !stops.isEmpty { deferred = (screen, stops) }
            return
        }
        #if DEBUG
        if let forced = Tour.forced {
            guard screen == forced else { return }
            return arm(screen, stops: stops)
        }
        #endif
        // The welcome card comes first and says what the app is; the tour says where
        // things are. Running the second before the first has been dismissed puts them
        // on screen together.
        // One stop is still a tour. An empty Trips tab has exactly one thing worth
        // saying and no rows to point at, and refusing to say it would also leave that
        // screen unspent forever — which the finale waits on. See `Tour.isComplete`.
        guard !Tour.seen(screen), !stops.isEmpty else { return }
        arm(screen, stops: stops)
    }

    private func arm(_ screen: Tour.Screen, stops: [Tour.Stop]) {
        // Belt and braces, and it earns its place: `-tour party` skips the checks in
        // `offer` on purpose, and the Party screen reports no stops at all while a
        // party is actually running. Arming on that would raise `isRunning` with no
        // stop to draw, which means no bubble, no scrim, and so no way to press Next.
        guard !stops.isEmpty else { return }
        pending = screen
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self, pending == screen, self.screen == nil else { return }
            pending = nil
            // The welcome card went up during the settle. Whether it does so before or
            // after a tab's `onAppear` is not something view order guarantees, so this
            // is checked at both ends rather than only at the offer.
            guard !isSuspended else { return deferred = (screen, stops) }
            route = stops
            #if DEBUG
            index = min(Tour.forcedStep, max(0, stops.count - 1))
            #else
            index = 0
            #endif
            // Spent when it starts, not when it ends. Force quitting mid-tour is the
            // case this covers, and it is the same argument `CoachPresenter.promote`
            // makes: "runs once" has to mean once, not once-if-completed-politely.
            Tour.markSeen(screen)
            TourGuide.isRunning = true
            withAnimation(.snappy(duration: 0.3)) { self.screen = screen }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-tourAuto") { autoAdvance() }
            #endif
        }
    }

    #if DEBUG
    /// `-tourAuto` walks the tour by itself, one stop every two seconds.
    ///
    /// The scrim's tap and the Next button are the only ways forward, and neither is
    /// reachable from a launch argument — so without this the *sequence*, as opposed to
    /// any single stop of it, is unphotographable, and the two things that only happen
    /// at the end of one (the scroll back to the top, and the walk back to the first
    /// tab) cannot be verified at all.
    private func autoAdvance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, screen != nil else { return }
            advance()
            if screen != nil { autoAdvance() }
        }
    }
    #endif

    /// Next stop, or the end.
    func advance() {
        guard screen != nil else { return }
        guard !isLast else { return stop(restoring: true) }
        withAnimation(.snappy(duration: 0.3)) { index += 1 }
    }

    func back() {
        guard screen != nil, index > 0 else { return }
        withAnimation(.snappy(duration: 0.3)) { index -= 1 }
    }

    /// Skipped, finished, or walked away from. All three end it.
    ///
    /// `restoring` is the difference between the three, and it is the whole of the
    /// "back to a clean slate" behaviour. A tour that ends because it ran out of stops
    /// or because Skip was tapped has left the page scrolled somewhere the reader did
    /// not put it, halfway down an album they have not earned yet, and it owes them the
    /// top of the screen back. A tour that ends because the tab changed owes nothing:
    /// that screen is already gone, and scrolling it on the way out is a jump the
    /// reader sees the next time they visit.
    /// Done with all of it, from the hold-to-skip control.
    ///
    /// Marks every tour and every coach mark spent, so nothing else in the app starts
    /// explaining itself later. The current screen still gets put back the way it was
    /// found — skipping is not a reason to leave somebody halfway down a page they did
    /// not scroll to.
    func skipAll() {
        Tour.markAllSeen()
        Coach.markAllSeen()
        skipping = true
        stop(restoring: true)
        skipping = false
    }

    /// True only for the duration of `skipAll`, to keep the finale out of it.
    ///
    /// Without this the finale fires on every skip: `skipAll` marks all five tabs seen,
    /// which is exactly the condition `stop` reads as "the whole thing is finished, walk
    /// them back to the first tab". Being thrown to another tab is the opposite of what
    /// somebody who just held a button down to make the onboarding stop has asked for.
    private var skipping = false

    func stop(restoring: Bool) {
        guard let finished = screen else { return }
        let wasLast = restoring && !skipping && finished.isTab && Tour.isComplete
        TourGuide.isRunning = false
        withAnimation(.easeIn(duration: 0.25)) {
            screen = nil
            index = 0
            route = []
        }
        guard restoring else { return }
        // Named, not inferred. `screen` is nil by now, and the scroll driver reading it
        // through an `?? .game` fallback meant only the Game tab ever actually scrolled
        // back — every other screen quietly asked to scroll to an id that is not on it.
        restoredScreen = finished
        restoreRequest += 1
        // Only the very last tour of the very last tab claims to have finished the
        // whole thing. Anything else is one screen out of nine.
        if wasLast { finishedEverything = true }
    }

    /// The tab went away.
    func left(_ screen: Tour.Screen) {
        if pending == screen { pending = nil }
        guard self.screen == screen else { return }
        stop(restoring: false)
    }

    /// Consumed by the root once it has gone back to the first tab.
    func clearFinishedFlag() { finishedEverything = false }

    /// Start the whole thing over, from "Replay the tour" in Settings.
    func replay() {
        Tour.reset()
        stop(restoring: false)
    }
}
