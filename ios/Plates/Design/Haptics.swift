import UIKit
import CoreHaptics

/// Every haptic in the app, in one place, so the vocabulary stays consistent: the
/// same physical sensation should always mean the same thing.
///
/// Everything here is gated on the hardware actually having a Taptic Engine. That
/// is not a Simulator nicety — this app builds for iPad as well as iPhone, and no
/// iPad has one. Without the check, every tap on an iPad asks UIKit to spin up an
/// engine that cannot exist, which fails asynchronously and fills the log with
/// `CoreHaptics` errors and dead `AudioSession` connections.
@MainActor
enum Haptics {

    /// Queried once. `capabilitiesForHardware()` reports the device, not the user's
    /// Settings — someone who has turned System Haptics off still reads as capable,
    /// and UIKit silently does nothing, which is the correct behaviour.
    private static let isSupported: Bool =
        CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// The user's own switch, in Settings. Defaults to on.
    ///
    /// Stored inverted — "off" rather than "on" — because `UserDefaults` returns
    /// false for a key nobody has written, and the sensible default here is on. A key
    /// named `hapticsOn` would silently start life meaning the opposite.
    static let offKey = "hapticsOff"

    static var isOn: Bool {
        get { !AppDefaults.store.bool(forKey: offKey) }
        set { AppDefaults.store.set(!newValue, forKey: offKey) }
    }

    /// Every haptic below is gated on both: the hardware being able, and the user
    /// wanting it.
    private static var allowed: Bool { isSupported && isOn }

    private static let notify = UINotificationFeedbackGenerator()
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft   = UIImpactFeedbackGenerator(style: .soft)
    private static let select = UISelectionFeedbackGenerator()

    /// Call when feedback is about to become likely — entering the grid, say — so
    /// the first tap does not pay the engine's start-up cost.
    ///
    /// Deliberately *not* called after every fire. Re-arming on each hit keeps the
    /// engine alive indefinitely and can re-arm it while the app is being suspended,
    /// which is exactly when the connection to `hapticd` goes away and the failure
    /// gets logged.
    static func warmUp() {
        guard allowed else { return }
        notify.prepare()
        medium.prepare()
        select.prepare()
    }

    /// A plate you had never seen, now found. The one genuinely celebratory haptic
    /// in the app — nothing else gets `.success`, or it stops meaning much.
    static func found() {
        guard allowed else { return }
        notify.notificationOccurred(.success)
    }

    /// Another sighting of a plate already collected. Lighter, because it is a
    /// smaller event than the first one.
    static func repeatSighting() {
        guard allowed else { return }
        light.impactOccurred(intensity: 0.7)
    }

    /// Undoing a find. Deliberately dull — removing something should not feel as
    /// good as adding it.
    static func undo() {
        guard allowed else { return }
        soft.impactOccurred(intensity: 0.6)
    }

    /// All fifty. Two beats, so it is unmistakably not an ordinary find.
    static func milestone() {
        guard allowed else { return }
        notify.notificationOccurred(.success)
        medium.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            // The app can be backgrounded inside that window — firing into a
            // suspended process is what produces "Player was not running".
            guard UIApplication.shared.applicationState == .active else { return }
            medium.impactOccurred(intensity: 1.0)
        }
    }

    /// Moving between discrete choices: colors, scoring modes, trips, map regions.
    static func selection() {
        guard allowed else { return }
        select.selectionChanged()
    }

    /// A popup arriving. Just enough to confirm the tap landed.
    static func popup() {
        guard allowed else { return }
        light.impactOccurred(intensity: 0.5)
    }

    /// A press-and-hold that reached its end and fired.
    ///
    /// Deliberately not `destructive()`: that is a `.warning`, and warning somebody
    /// about skipping a tutorial is absurd. Nor `selection()`, which is the tick of
    /// moving between choices and far too slight to answer a finger that has been held
    /// down for a second. This is the one thing in the app that confirms a *held*
    /// gesture, so it gets the one firm impact — the same feel iOS gives its own
    /// press-and-hold confirmations, which is where the expectation comes from.
    static func holdConfirmed() {
        guard allowed else { return }
        medium.impactOccurred(intensity: 1.0)
    }

    /// Confirming something destructive — a wipe, a deletion.
    static func destructive() {
        guard allowed else { return }
        notify.notificationOccurred(.warning)
    }
}
