import AVFoundation
import Observation
import UIKit

/// The app's own voice.
///
/// Voice mode without this is only half hands-free: you can talk to it, but you have
/// to look at the screen to find out whether it heard you. In a car that is the same
/// problem as tapping. So it asks out loud and it answers out loud, and the screen
/// becomes something you never need to look at.
///
/// KEPT SHORT ON PURPOSE. A confirmation is the plate's name and, if it is worth
/// something, one word for the tier. The fun fact that the find card shows is the
/// right length to read and the wrong length to hear — it would still be talking when
/// the next plate goes past.
@Observable
@MainActor
final class VoiceSpeaker: NSObject {

    private let synth = AVSpeechSynthesizer()

    /// True from the moment speech is queued until it finishes. The recogniser reads
    /// this and stops listening, because otherwise the app hears itself: saying "New
    /// Jersey logged" out loud puts "new jersey" straight back into the transcript.
    private(set) var isSpeaking = false

    /// Called when the last queued utterance finishes, so a prompt can be followed by
    /// listening rather than by a guess at how long it took to say.
    var onFinished: (() -> Void)?

    /// Called as speech begins. Paired with `onFinished` to duck the car's music for
    /// exactly as long as the app is talking — see `VoiceLogger.duckOthers`.
    var onStarted: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
        Self.noteWhenVoicesChange
    }

    /// One observation per process, set up by the first speaker.
    ///
    /// Two triggers, both cheap and both needed. The voices-changed notification is
    /// the precise one, posted when a download lands while the app is running. The
    /// foregrounding one is the belt to that suspender: the common sequence is
    /// "background the app, download the voice in Settings, come back", and on
    /// devices where the first notification is missed or predates iOS 17, returning
    /// to the app is the moment the inventory is worth another look.
    private static let noteWhenVoicesChange: Void = {
        let refresh: (Notification) -> Void = { _ in
            Task { @MainActor in VoiceSpeaker.refreshVoice() }
        }
        if #available(iOS 17.0, *) {
            NotificationCenter.default.addObserver(
                forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil, queue: .main, using: refresh)
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main, using: refresh)
    }()

    /// Normalised forms of everything said in the last few seconds, for the recogniser
    /// to subtract from what it hears. See `VoiceLogger.ingest`.
    private(set) var recentlySaid: [(text: String, at: Date)] = []

    func say(_ text: String) {
        guard !text.isEmpty else { return }
        let now = Date()
        recentlySaid.append((PlateSpeech.normalise(text), now))
        recentlySaid.removeAll { now.timeIntervalSince($0.at) > 12 }
        if !isSpeaking { onStarted?() }
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        // The ceiling. Stated rather than left to the default, because it is the first
        // thing anyone reaches for when the voice is hard to hear, and finding it
        // already at maximum is the answer to that question.
        utterance.volume = 1.0
        utterance.voice = Self.voice
        // Default rate, or a shade under it. The old 1.06 was tuned against the
        // compact voice, which is clipped enough that hurrying it costs nothing; the
        // enhanced voices carry real prosody and pushing them flattens it into the
        // announcement they are trying not to be.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (Self.voiceIsCompact ? 1.06 : 0.98)
        utterance.pitchMultiplier = 1.0
        // A beat before speaking. Confirmations arrive on top of whatever is being
        // said in the car, and starting mid-word is most of what makes a synthesised
        // voice sound like a machine interrupting rather than a person answering.
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    // MARK: - Which voice

    /// The most natural voice this device actually has, chosen once.
    ///
    /// `AVSpeechSynthesisVoice(language:)` returns the *compact* voice — a few
    /// megabytes of clipped diphones, and the reason synthesised speech has sounded
    /// the same since 2011. Every device also ships, or can download, enhanced and
    /// premium versions of the same voices, which are neural and sound close to a
    /// person. They are never the default and must be asked for by identifier.
    ///
    /// Enumerating and picking is also the only thing that still works. iOS 26 broke
    /// `AVSpeechSynthesisVoice(language:)`: it now ignores the voice the user chose
    /// in Accessibility and hands back the system default regardless (FB20271264).
    /// Choosing by identifier is the documented way round it, and is what this does.
    ///
    /// Memoised, because `speechVoices()` enumerates every installed voice and this
    /// is read on every confirmation — but *not* a `let`. It was, and that was a
    /// user-visible bug: the screen says "download a natural voice in Settings", the
    /// user does exactly that, comes back, and the app keeps the compact voice until
    /// the process actually dies — which iOS may not do for days. The advice looked
    /// broken. `noteWhenVoicesChange` empties the memo the moment the system says
    /// the inventory moved, so the next sentence is spoken by the new voice.
    static var voice: AVSpeechSynthesisVoice? {
        if !resolved { cached = bestVoice(); resolved = true }
        return cached
    }
    private static var cached: AVSpeechSynthesisVoice?
    private static var resolved = false

    /// Re-pick on the next utterance. Cheap: nothing is enumerated until then.
    static func refreshVoice() { resolved = false }

    /// True when the device has nothing better than compact installed — which is the
    /// out-of-the-box state, and worth telling the user about, since the fix is a
    /// download they have to make themselves.
    static var voiceIsCompact: Bool { (voice?.quality ?? .default) == .default }

    /// Where the download lives, which is not the same place on every supported OS.
    ///
    /// iOS 26 renamed Accessibility ▸ Spoken Content to **Read & Speak**. This app
    /// runs on iOS 18 too, where the old name is still correct, so directions that
    /// name one of them are wrong for half the installed base. There is no URL that
    /// opens either pane — `openSettingsURLString` only reaches the app's own
    /// settings and the `prefs:` scheme is private — so the words are all there is,
    /// and they have to be the right words.
    static var voiceSettingsPath: String {
        if #available(iOS 26.0, *) {
            return "Settings \u{203A} Accessibility \u{203A} Read & Speak \u{203A} Voices \u{203A} English"
        }
        return "Settings \u{203A} Accessibility \u{203A} Spoken Content \u{203A} Voices \u{203A} English"
    }

    /// Voices that are technically English and emphatically not people. Eloquence is
    /// the 1980s DECtalk lineage, kept for screen-reader users who read at 700 words
    /// a minute and want the clarity; the `speech.synthesis.voice` bundle is the old
    /// macOS novelty set — Albert, Bad News, Zarvox.
    private static let novelty = ["eloquence", "speech.synthesis.voice"]

    /// Names worth preferring at equal quality, in order. Apple's own default for a
    /// language is not always its best-liked voice, and at premium quality the
    /// difference between these and the rest of the set is audible.
    private static let favoured = ["ava", "zoe", "evan", "nathan", "samantha",
                                   "allison", "susan", "tom"]

    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let region = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { v in
            v.language.hasPrefix("en") &&
            !novelty.contains { v.identifier.lowercased().contains($0) }
        }
        let pick = candidates.max { a, b in score(a, region) < score(b, region) }
        #if DEBUG
        // The inventory, because "the voice sounds robotic" is undiagnosable without
        // it: whether a downloaded voice reaches this process at all is exactly what
        // keeps going wrong (see voiceSettingsPath), and only the device can say.
        let q = ["?", "compact", "enhanced", "premium"]
        print("VOICES: \(AVSpeechSynthesisVoice.speechVoices().count) installed, "
              + "\(candidates.count) candidates for \(region)")
        for v in candidates.sorted(by: { score($0, region) > score($1, region) }) {
            print("VOICES: \(score(v, region))  \(v.name)  \(v.language)  "
                  + "\(q[v.quality.rawValue])  \(v.identifier)")
        }
        print("VOICES: picked \(pick?.name ?? "none") (\(q[pick?.quality.rawValue ?? 0]))")
        #endif
        return pick
    }

    /// Quality dominates: a premium voice in the wrong English still sounds more like
    /// a person than a compact one in the right English. Locale breaks ties, so a
    /// device set to en-GB is answered in the accent it expects.
    private static func score(_ v: AVSpeechSynthesisVoice, _ region: String) -> Int {
        var n = v.quality.rawValue * 100
        if v.language.caseInsensitiveCompare(region) == .orderedSame { n += 30 }
        else if v.language.hasPrefix("en-US") { n += 20 }
        if let rank = favoured.firstIndex(where: {
            v.name.lowercased().hasPrefix($0)
        }) { n += 10 - rank }
        return n
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// What to say when a plate lands. Name first, because it is the word that
    /// confirms the app heard the right thing and it should arrive before anything
    /// else competes for attention.
    ///
    /// A repeat gets a whole sentence rather than a clipped fragment. "Already had
    /// it" was two unstressed syllables tacked onto a name and came out as mush at
    /// road speed; a full clause gives the synthesiser something to put a rhythm on.
    /// Said when a plate is called out that the collection already holds and will not
    /// count twice. Shared with `confirmation` so the two cannot drift into telling
    /// somebody two different things about the same situation.
    static func alreadySeen(_ plate: Plate) -> String {
        "\(plate.name) has already been seen."
    }

    static func confirmation(for plate: Plate, outcome: PlateLogger.Outcome) -> String {
        guard outcome.isFirstFind else {
            return alreadySeen(plate)
        }
        return outcome.tier >= .rare
            ? "\(plate.name). \(outcome.tier.label.capitalized)."
            : "\(plate.name)."
    }
}

extension VoiceSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !synthesizer.isSpeaking else { return }
            isSpeaking = false
            onFinished?()
        }
    }

    /// Cancellation runs the same recovery as finishing. Whatever was set up for the
    /// duration of the speech — the ducked music, the muted recogniser — has to come
    /// back either way, and a stop that leaves the car's podcast quiet forever is the
    /// worst of the two failures.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            onFinished?()
        }
    }
}
