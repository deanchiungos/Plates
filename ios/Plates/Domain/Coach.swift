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

    private static func key(_ tip: Tip) -> String { "coach.\(tip.rawValue)" }

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
        let next = UserDefaults.standard.integer(forKey: launchesKey) + 1
        UserDefaults.standard.set(next, forKey: launchesKey)
        launchCount = next
    }

    /// True from the second time the app is opened onward.
    static var isReturningSession: Bool { launchCount > 1 }

    static func seen(_ tip: Tip) -> Bool {
        UserDefaults.standard.bool(forKey: key(tip))
    }

    static func markSeen(_ tip: Tip) {
        UserDefaults.standard.set(true, forKey: key(tip))
    }

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
        for tip in Tip.allCases where includingWelcome || tip != .welcome {
            UserDefaults.standard.removeObject(forKey: key(tip))
        }
    }

    #if DEBUG
    /// `-coach uncheck` forces one mark on its screen, ledger ignored — the only way
    /// to photograph a balloon whose trigger needs a state that takes ten taps to
    /// reach. `-coachReset` wipes the ledger at launch, which is how the sequence is
    /// run twice without reinstalling.
    static var forced: Tip? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-coach"), at + 1 < args.count else { return nil }
        return Tip(rawValue: args[at + 1])
    }

    static func applyLaunchArguments() {
        if ProcessInfo.processInfo.arguments.contains("-coachReset") { reset() }
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
    }

    /// Spent at the moment it appears, not when it is dismissed.
    ///
    /// The difference matters exactly once, and it is the case that would otherwise
    /// look like a bug: kill the app with a balloon on screen — which is what force
    /// quitting, or a crash, or iOS reclaiming memory in a car with the navigation
    /// running all do — and a tip marked on dismissal was never marked at all, so it
    /// returns on the next launch. Writing it here is what makes "shows at most once"
    /// literally true rather than true-if-dismissed-politely.
    private func promote(_ tip: Coach.Tip) {
        guard pending == tip, showing == nil else { return }
        pending = nil
        Coach.markSeen(tip)
        withAnimation(.snappy(duration: 0.24)) { showing = tip }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
