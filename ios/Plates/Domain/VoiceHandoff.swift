import Observation

/// How Siri gets voice mode open.
///
/// An App Intent runs inside the app's process but nowhere near its views, so it
/// cannot present a sheet. It sets a flag here instead and the Game screen, which is
/// watching, opens voice mode when it next appears. That indirection is also what
/// makes "Hey Siri, open Plates" work: launching the app normally goes through the
/// same door, it just arrives by a different route.
@Observable
@MainActor
final class VoiceHandoff {
    static let shared = VoiceHandoff()
    private init() {}

    /// Whether voice mode should open by itself when the app launches, so that
    /// "Hey Siri, open Plates" is enough to start logging.
    ///
    /// The key lives here rather than on the screen that toggles it because it is
    /// about the handoff, not about Settings: the preference and the flag above are
    /// two routes to the same door, and a screen owning the name of one of them
    /// would leave the other reaching across for it.
    ///
    /// NOTE: nothing reads or writes this. The Settings toggle that used to set it is
    /// gone, and no launch path consults it, so the preference is inert — kept only
    /// so the name is not quietly re-used for something else while old installs still
    /// have a value stored under it. Honouring it would mean giving
    /// `GameScreen.listening` an initial value that checks this default, and that is
    /// deliberately not done: a plain launch is indistinguishable from tapping the
    /// icon, so an auto-start keyed on launch is an auto-start on *every* launch.
    static let autoStartKey = "voiceAutoStart"

    /// Set by `StartVoiceModeIntent`, cleared by the screen that acts on it.
    var wantsVoiceMode = false

    /// A plate the user already named on the way in — "log New Jersey in Plates".
    ///
    /// Every spoken route now ends up in voice mode, but a plate that was said out
    /// loud should not have to be said twice, so the name rides along and is logged
    /// as voice mode opens.
    private var pendingPlate: String?

    func handOff(plate code: String?) {
        wantsVoiceMode = true
        pendingPlate = code
    }

    /// Read once and gone. Voice mode's `task` can run again — a backgrounded phone
    /// coming forward is enough — and a code left sitting here would log the same
    /// plate every time it did.
    func takePendingPlate() -> String? {
        defer { pendingPlate = nil }
        return pendingPlate
    }
}
