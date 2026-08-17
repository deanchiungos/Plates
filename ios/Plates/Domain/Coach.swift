import Foundation
import Observation
import SwiftUI

/// What this hand has already been shown.
///
/// The whole of the onboarding state, and deliberately almost nothing: a set of
/// booleans saying which tips have had their turn. There is no tour, no step
/// counter, no "onboarding version" — a tip is either spent or it is not, and every
/// trigger that decides whether to spend one is a fact about the player's actual
/// state, evaluated on the screen it belongs to.
///
/// **Shown means seen.** A mark that appears is marked immediately, whether it was
/// read, tapped, acted on, or scrolled past on the way to something else. That is
/// what keeps this a set of booleans rather than a state machine, and it is also the
/// kinder behaviour: a balloon that returns on every visit until acknowledged is
/// nagging, and the "How to play" page exists precisely so an ignored tip is not
/// lost. See `CoachPresenter.withdraw`.
///
/// `UserDefaults`, not `NSUbiquitousKeyValueStore`. These are about a hand that has
/// been taught, not an account that has — the same reasoning as `DevicePlayer`'s
/// note on the device key. Somebody handed a second phone genuinely has not seen the
/// long-press tip on it.
enum Coach {

    /// One case per thing the app ever explains unprompted.
    ///
    /// Adding a case is cheap; the discipline is in *not* adding one. Anything with
    /// a screen of its own, a label on its own button, or an empty state that speaks
    /// for itself does not get a tip — it would be the app talking over itself.
    enum Tip: String, CaseIterable {
        case welcome        // the card itself was shown (or skipped)
        case fork           // the framed empty state was seen
        case firstTap       // "See one of these on the road? Tap it."
        case swipeTrip      // swipe left to pin / mark done
        case uncheck        // long-press in unlimited
        case doneTrip       // the record + fold, after first finish
        case trailScope     // the Trail shows one drive; the name switches it
        case spotterChip    // the colored corner is who called it
        case listLength     // mark old trips done once the list is long
    }

    private static let ledger = SeenLedger<Tip>(prefix: "coach")

    // MARK: - Sessions

    private static let launchesKey = "coach.launches"

    /// How many times this app has been opened, counting this one.
    ///
    /// The one piece of state here that is not a fact about the player's collection,
    /// and it earns its place for exactly one tip. `swipeTrip` is about *organising*
    /// a list of trips — pinning one, marking another done — and on a first launch
    /// the list is a single trip somebody made ninety seconds ago. There is nothing
    /// to organise, and a balloon offering to help organise it is the app inventing
    /// a problem. Every other trigger stays a fact about state; this one waits for
    /// there to have been a yesterday.
    private(set) static var launchCount = 0

    /// Called once, before any screen asks anything.
    static func beginSession() {
        let next = AppDefaults.store.integer(forKey: launchesKey) + 1
        AppDefaults.store.set(next, forKey: launchesKey)
        launchCount = next
    }

    /// True from the second time the app is opened onward.
    static var isReturningSession: Bool { launchCount > 1 }

    static func seen(_ tip: Tip) -> Bool { ledger.seen(tip) }

    static func markSeen(_ tip: Tip) { ledger.markSeen(tip) }

    /// Spend every tip at once, without showing any of them.
    ///
    /// The other half of "skip all". Somebody who has just held a button down to stop
    /// being taught has not asked to be taught in smaller pieces instead, and the
    /// balloons are the same lesson delivered one control at a time. "Replay the tour"
    /// hands them all back, which is what makes this safe to be so total.
    static func markAllSeen() { ledger.markSeen(Tip.allCases) }

    /// Hand every tip back its turn.
    ///
    /// `includingWelcome` is off by default, and that default is the interesting
    /// half. "Replay the tips" should not re-run the first-launch card over an app
    /// somebody has been using for a year — the tips are about controls, the card is
    /// about arriving, and only one of those can happen twice.
    ///
    /// It is on for exactly one caller: "Replay the tour" in Settings, which exists
    /// so the sequence can be looked at on a real phone by somebody who already has
    /// data. That is a deliberate override of the rule above rather than an
    /// exception to it — see `CoachPresenter.replayTour`.
    static func reset(includingWelcome: Bool = false) {
        ledger.reset(sparing: includingWelcome ? [] : [.welcome])
    }

    #if DEBUG
    /// `-coach uncheck` forces one mark on its screen, ledger ignored — the only way
    /// to photograph a balloon whose trigger needs a state that takes ten taps to
    /// reach. `-coachReset` wipes the ledger at launch, which is how the sequence is
    /// run twice without reinstalling.
    static var forced: Tip? { ledger.forced(by: "-coach") }

    static func applyLaunchArguments() {
        guard LaunchFlags.isSet("-coachReset") else { return }
        // Including the welcome card, and the launch counter that gates it. `reset()`
        // defaults to sparing the welcome — which is right for the in-app control,
        // where somebody asking to see the tips again does not mean the introduction
        // — and left this flag unable to reset the one card it exists to show twice.
        reset(includingWelcome: true)
        AppDefaults.store.removeObject(forKey: launchesKey)
        // Handing the welcome card back is not the same as seeing it: `RootView`
        // also requires an empty roster, so `-coachReset` alongside `-demoData`
        // still shows nothing. `-welcome` is the flag for looking at the card.
    }
    #endif
}

/// Which mark is on screen right now — at most one, app-wide.
///
/// Two balloons at once is a fairground, and the failure is easy to reach without an
/// arbiter: a grid that is both empty and in unlimited mode satisfies two triggers on
/// the same render. So screens do not decide to show a mark, they *ask*, and the
/// first one to ask wins until it is done.
///
/// Injected next to `PopupHost`, which it deliberately does not know about. Standing
/// down under a popup is a drawing decision and belongs to `CoachLayer`; a balloon
/// under a scrim is furniture, but it has not been dismissed and should come back when
/// the popup does not.
@MainActor
@Observable
final class CoachPresenter {

    /// The mark currently on screen.
    private(set) var showing: Coach.Tip?

    /// Asked for, waiting out the settle delay. Kept separate from `showing` so a
    /// second request during the delay loses, rather than racing.
    private var pending: Coach.Tip?

    /// Bumped by "Replay the tour"; watched by `RootView`, which owns the card.
    ///
    /// A counter rather than a flag, so asking twice actually runs it twice — a
    /// boolean would need resetting by whoever consumed it, and the one thing this is
    /// for is looking at the same sequence over and over.
    private(set) var replayRequest = 0

    /// Start the whole sequence again, on a device that has already been through it.
    ///
    /// Touches nothing but the ledger. No player is removed, no trip, no book, no
    /// sighting — the tour on a full app simply has less to show, because the fork
    /// and the first-tap balloon are about states this phone left behind long ago.
    /// That is the honest preview, and it is a great deal better than the
    /// alternative, which is asking somebody to delete their collection to look at
    /// their own onboarding.
    func replayTour() {
        Coach.reset(includingWelcome: true)
        replayRequest += 1
    }

    /// Long enough for a screen to finish arriving, short enough to still read as a
    /// response to what you did. The same 0.5–0.6s every other deferred presentation
    /// in the app waits.
    private let settle: TimeInterval = 0.6

    /// Ask for a tip's turn, given whether its trigger currently holds.
    ///
    /// Silently does nothing if the trigger is false, if the tip has had its turn, if
    /// another mark holds the slot, or if a mark is already on its way up.
    ///
    /// The trigger is passed in rather than checked by the caller so that `-coach`
    /// can override it. A tip whose condition takes ten taps to reach would otherwise
    /// be unphotographable, which in this app means untested.
    ///
    /// Safe to call from `onAppear` and `onChange` repeatedly — the guards make
    /// repeat calls free, which is what lets a trigger be written as a plain fact
    /// about state rather than as an event somebody has to fire exactly once.
    func request(_ tip: Coach.Tip, when trigger: Bool = true) {
        guard showing == nil, pending == nil else { return }
        // A balloon under a tour's scrim is a balloon nobody can read, and it would be
        // spent on the way past — `promote` marks a tip the moment it appears. The tip
        // keeps its turn instead, and gets it on a visit when nothing else is talking.
        guard !TourGuide.isRunning else { return }
        #if DEBUG
        if let forced = Coach.forced {
            guard tip == forced else { return }
            pending = tip
            after(settle) { [self] in promote(tip) }
            return
        }
        #endif
        guard trigger, !Coach.seen(tip) else { return }
        pending = tip
        after(settle) { [self] in promote(tip) }
    }

    /// Tapped, or the described action performed. Both mean done.
    func dismiss(_ tip: Coach.Tip) {
        guard showing == tip || pending == tip else { return }
        pending = nil
        if announced == tip { announced = nil }
        withAnimation(.easeIn(duration: 0.22)) { showing = nil }
    }

    /// The screen went away. Takes the balloon with it.
    ///
    /// A tip still waiting out the settle delay is cancelled rather than spent — it
    /// never appeared, so it has not been ignored, and its trigger gets another
    /// chance next visit.
    func withdraw(_ tip: Coach.Tip) {
        if showing == tip { showing = nil }
        if pending == tip { pending = nil }
        if announced == tip { announced = nil }
    }

    /// Given its turn. Not yet spent — see `didDraw`.
    private func promote(_ tip: Coach.Tip) {
        guard pending == tip, showing == nil else { return }
        // A tour armed during the settle. Cancelled rather than spent, exactly as
        // `withdraw` does it: the balloon never appeared, so it has not been ignored,
        // and its trigger gets another chance on a visit when nothing else is talking.
        guard !TourGuide.isRunning else { return pending = nil }
        pending = nil
        withAnimation(.snappy(duration: 0.24)) { showing = tip }
        // And handed back if the layer declines to draw it.
        //
        // Not spending an undrawn tip is right; holding the slot with it is not.
        // `showing` is what stops a second tip asking, so a tip whose anchor is
        // never registered would sit in the slot for the whole visit, get cleared by
        // `withdraw` on the way out, and take the slot again next visit — every
        // visit, for the life of the install. The screen's other tips would never
        // get a turn. Releasing it costs the undrawn tip nothing: it was not marked,
        // so it is still owed a turn, and it will ask again.
        after(settle) { [self] in
            guard showing == tip, announced != tip else { return }
            showing = nil
        }
    }

    /// The last tip actually put on the page. Guards the announcement below.
    private var announced: Coach.Tip?

    /// The balloon is on screen. Called by the layer, which is the only thing that
    /// knows — and that is the whole reason this exists.
    ///
    /// Spent at the moment it appears, not when it is dismissed. The difference
    /// matters exactly once, and it is the case that would otherwise look like a bug:
    /// kill the app with a balloon on screen — which is what force quitting, or a
    /// crash, or iOS reclaiming memory in a car with the navigation running all do —
    /// and a tip marked on dismissal was never marked at all, so it returns on the
    /// next launch. Marking on appearance is what makes "shows at most once"
    /// literally true rather than true-if-dismissed-politely.
    ///
    /// But `promote` is not appearance, which is where this was written before.
    /// Setting `showing` is a request to the layer, and the layer draws nothing
    /// unless a view registered an anchor for the tip and that view is currently on
    /// the page. Both fail routinely: a screen that requests a tip for a control it
    /// only sometimes shows registers no anchor at all, and a target below the fold
    /// is held back on purpose until it is scrolled to. Every one of those spent the
    /// tip anyway — marked seen, never drawn, gone for good. The tip a first-time
    /// player is least likely to have scrolled to is exactly the one they never get.
    ///
    /// Also the one honest place to speak. VoiceOver is told when the balloon is
    /// really there, and told once: the layer drops the balloon whenever its target
    /// scrolls off and rebuilds it on the way back, so an `onAppear` that announces
    /// unconditionally reads the same sentence out on every pass of a list.
    func didDraw(_ tip: Coach.Tip, saying words: LocalizedStringResource) {
        Coach.markSeen(tip)
        guard announced != tip else { return }
        announced = tip
        // Nothing moved focus, so without this a VoiceOver user is simply not told
        // that the app said something.
        AccessibilityNotification.Announcement(String(localized: words)).post()
    }

    private func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
