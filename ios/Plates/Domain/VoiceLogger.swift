import AVFoundation
import Observation
import Speech

/// The microphone half of voice mode: listen continuously, hand every revision of the
/// transcript to `PlateSpeech`, and report jurisdictions as they are said.
///
/// WHY THIS EXISTS RATHER THAN A SIRI SHORTCUT. An App Shortcut phrase is required to
/// contain the app name, so the shortest thing anybody can say is "log New Jersey in
/// Plates", and it is one plate per invocation with a round trip through Siri between
/// each. On a motorway with three people calling plates that is not a feature, it is
/// a queue. This listens once and keeps listening.
///
/// ON-DEVICE BY PREFERENCE. `requiresOnDeviceRecognition` is set wherever the device
/// supports it, which means no audio leaves the phone and it works in the places this
/// app is actually used — a canyon, a tunnel, rural Montana with one bar. Where the
/// device cannot do it the recogniser falls back to the server and the UI says so,
/// because "it stopped working when we lost signal" deserves an explanation.
///
/// THE HARD PART IS NOT HEARING, IT IS NOT HEARING TWICE. A live transcript is
/// revised as it is spoken: "new" becomes "new jer" becomes "new jersey", and each
/// revision arrives as its own result carrying the whole sentence so far. Logging on
/// every match would put New Jersey on the board a dozen times. `consumed` is the
/// answer — the transcript is only ever read past the point already acted on.
@Observable
@MainActor
final class VoiceLogger {

    enum Status: Equatable {
        case idle
        case starting
        case listening
        case denied(String)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// What is being heard right now, for the screen to show. Purely reassurance:
    /// nothing is decided from this, and a listener who can see their words appear
    /// trusts a thing that is otherwise silent until it acts.
    private(set) var transcript = ""
    private(set) var isOnDevice = false
    /// Loudest recent sample, 0...1, for the level ring.
    private(set) var level: Double = 0

    /// Called on the main actor for each jurisdiction heard, once.
    var onHeard: ((Plate) -> Void)?

    /// What the app itself has said recently, to be subtracted from what it hears.
    /// Echo cancellation removes most of it; this removes the rest.
    var ownWords: () -> [String] = { [] }

    /// Anything else said while listening, once it has settled. Voice mode uses this
    /// to catch a player's name in answer to "who is logging?"; nothing else does.
    var onPhrase: ((String) -> Void)?

    /// Set only while the app is asking a *question* — "who is logging?" — where the
    /// answer has not been said yet and there is nothing to lose by not listening.
    ///
    /// Confirmations are deliberately spoken unmuted. Dropping a second of audio
    /// after every find would lose the next call-out, and the app hearing its own
    /// confirmation is harmless anyway: the only plate name in it is the one just
    /// logged, which is inside its own cooldown.
    var isMuted = false {
        didSet { if isMuted { held = nil } }
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// How far into the normalised transcript has already been turned into sightings.
    private var consumed = 0
    /// The last time each jurisdiction was logged. A backstop for the case `consumed`
    /// cannot cover: the recogniser occasionally rewrites a sentence it had already
    /// settled, which resets the text underneath the pointer.
    private var lastLogged: [String: Date] = [:]
    private static let cooldown: TimeInterval = 4

    /// A match sitting at the very end of the transcript, which might still grow into
    /// a longer jurisdiction. See `ingest`.
    private var held: (PlateSpeech.Hit, Date)?
    private static let settleDelay: TimeInterval = 0.7
    private var ticker: Task<Void, Never>?

    // MARK: - Permission

    static func requestAuthorisation() async -> Bool {
        let speech = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await withCheckedContinuation { done in
            AVAudioApplication.requestRecordPermission { done.resume(returning: $0) }
        }
    }

    // MARK: - Running

    func start() async {
        guard status != .listening, status != .starting else { return }
        status = .starting

        guard await Self.requestAuthorisation() else {
            status = .denied(String(localized: "Voice mode needs the microphone and speech recognition. Both can be turned on in Settings."))
            return
        }
        guard let recogniser, recogniser.isAvailable else {
            status = .failed("Speech recognition is not available on this device.")
            return
        }

        do {
            try configureSession()
            try beginTask(on: recogniser)
            status = .listening
            startTicker()
            Haptics.selection()
        } catch {
            stop()
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        held = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        level = 0
        if status == .listening || status == .starting { status = .idle }
    }

    /// `.playAndRecord` with `.mixWithOthers` rather than `.record`, so the music or
    /// the podcast everyone in the car is listening to keeps playing. `.record` stops
    /// it dead, which is a startling thing for a plate game to do.
    /// Shared by `configureSession` and `duckOthers`, so that ducking cannot quietly
    /// drop one of them — losing `.defaultToSpeaker` mid-drive would move every
    /// confirmation to the earpiece, which in a car is the same as losing it.
    ///
    /// `.allowBluetooth` warns as deprecated and stays anyway. Its replacement,
    /// `.allowBluetoothHFP`, is iOS 26 and up; this app deploys to 18, so the old
    /// spelling is the only one that compiles across the whole supported range.
    /// It is a pure rename onto the same raw value, and an availability fork would
    /// still have to name the deprecated case in its `else` branch, so the fork
    /// buys a longer file and the same warning.
    private static let baseOptions: AVAudioSession.CategoryOptions =
        [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]

    /// Quietens the music while the app is talking, and only while it is talking.
    ///
    /// `AVSpeechUtterance.volume` is already 1.0 — there is no louder. The app's voice
    /// is quiet in a car because it is mixed on top of whatever everyone is listening
    /// to at full level, so the fix is not more gain, it is less competition.
    ///
    /// Set for the length of an utterance rather than for the session: ducking a
    /// podcast for an entire drive to say four words a dozen times is a much worse
    /// trade than ducking it for a second at a time.
    func duckOthers(_ on: Bool) {
        guard on != isDucking else { return }
        isDucking = on
        // Options only — same category, same mode, same route. Nothing here restarts
        // the engine or the recognition task, which is why this is safe to do while
        // the microphone is live.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .voiceChat,
                options: on ? Self.baseOptions.union(.duckOthers) : Self.baseOptions)
        } catch {
            // Not worth surfacing: the confirmation is still spoken, just over the
            // top of the music the way it was before.
            isDucking = !on
        }
        #if DEBUG
        print("AUDIO: duck=\(isDucking) status=\(status)")
        #endif
    }

    private var isDucking = false

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.voiceChat` rather than `.measurement`, for the one thing it turns on:
        // acoustic echo cancellation. `.measurement` disables all input processing,
        // which is right for measuring a room and wrong for a device that talks and
        // listens at the same time — without AEC the phone transcribes its own
        // confirmations straight back into the transcript.
        isDucking = false
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: Self.baseOptions)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func beginTask(on recogniser: SFSpeechRecognizer) throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recogniser.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            isOnDevice = true
        }
        // Every plate name is a place. Handing the recogniser the vocabulary it is
        // about to hear is the cheapest accuracy there is.
        request.contextualStrings = Plate.all.map(\.name)
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let peak = Self.peak(of: buffer)
            Task { @MainActor in self?.level = peak }
        }

        engine.prepare()
        try engine.start()

        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.ingest(result.bestTranscription.formattedString)
                }
                // A recognition task has a hard ceiling of about a minute, and ends
                // on silence besides. Neither is a failure here: voice mode is meant
                // to sit open for the length of a drive, so it simply starts another.
                if error != nil || result?.isFinal == true {
                    self.restart()
                }
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                // Not awaited: the task inherits this class's main-actor isolation,
                // so the call is direct. The `await` read as a hop that never was.
                self?.settleHeld()
            }
        }
    }

    private func restart() {
        guard status == .listening, let recogniser else { return }
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // The transcript restarts empty, so the pointer into it has to as well. The
        // per-jurisdiction cooldown is what stops a name still hanging in the air
        // from being logged twice across the seam.
        if let (hit, _) = held { held = nil; commit(hit) }
        transcript = ""
        consumed = 0

        do { try beginTask(on: recogniser) } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Hearing

    private func ingest(_ raw: String) {
        guard !isMuted else {
            // Keep the pointer at the end of whatever arrived while muted, so the
            // app's own words are never revisited once it stops talking.
            consumed = PlateSpeech.normalise(raw).count + 1
            return
        }

        // Whatever the app said out loud, struck out of what it heard.
        //
        // Echo cancellation catches most of it, but "most" is not good enough when
        // the leftovers are plate names being shown back to the user as though
        // somebody had said them. Blanked in place rather than deleted, so every
        // offset — including `consumed` — still means what it meant.
        //
        // ONLY PAST `consumed`. A confirmation opens with the name of the plate that
        // was just logged, which is the same phrase the user said to log it — so
        // striking the whole transcript would erase their own call-out from the
        // display along with the echo of it. Everything before `consumed` has already
        // been acted on and was, by definition, said before the app started talking.
        let normalised = Self.strike(ownWords(),
                                     from: PlateSpeech.normalise(raw),
                                     after: consumed)
        transcript = normalised.split(separator: " ").joined(separator: " ")

        // A revision that shortened the text means the recogniser changed its mind
        // about something already read. Rewind rather than skip the rest of it.
        if normalised.count + 1 < consumed { consumed = 0 }

        let hits = PlateSpeech.hits(in: normalised)
        // The end of the padded string a hit would occupy if it ran to the last word.
        let tail = normalised.count + 1

        for (i, hit) in hits.enumerated() where hit.end > consumed {
            // THE LAST WORD IS NEVER SAFE TO ACT ON. "Washington" is a complete,
            // correct match, and it is also the first half of "Washington DC" —
            // which is a different jurisdiction. The recogniser emits the first
            // before the second, so committing on sight logs Washington *and* the
            // District of Columbia from one phrase. The same trap is set by "new
            // york" over "new", and "west virginia" over "virginia".
            //
            // So a match at the very end of the transcript is held, not logged. It
            // commits as soon as another word arrives after it — which proves the
            // speaker has moved on and the phrase is not going to grow — or after a
            // moment's silence, for the case where they said one state and stopped.
            if i == hits.count - 1 && hit.end >= tail {
                held = (hit, Date())
                continue
            }
            commit(hit)
        }

        // The loop above already re-decides what is held: a match that used to sit at
        // the end and now has words after it gets committed by it, and one that grew
        // into a longer jurisdiction gets replaced by it. All that is left is to drop
        // the reference once it has been acted on, so the ticker does not act again.
        if let (hit, _) = held, hit.end <= consumed { held = nil }

        // AFTER the plates in this phrase, not before. The commands that read this —
        // "undo", "stop" — both act on what has already been logged, and a phrase can
        // carry a plate *and* a command: "Nevada, undo". Announcing the phrase first
        // ran the undo while Nevada was still uncommitted, so it took back the plate
        // before it and then logged the one it was meant to cancel. "Ohio, stop" has
        // the same shape and the same fix: log it, then end the session.
        onPhrase?(normalised)
    }

    /// Commits whatever is being held once the room has gone quiet.
    ///
    /// Without this, saying a single state and then nothing would leave it held for
    /// ever — the transcript never grows, so the "another word arrived" test never
    /// fires. The delay is short enough not to feel like lag and long enough for
    /// "Washington" to become "Washington DC".
    private func settleHeld() {
        guard let (hit, at) = held, Date().timeIntervalSince(at) >= Self.settleDelay
        else { return }
        held = nil
        commit(hit)
    }

    private func commit(_ hit: PlateSpeech.Hit) {
        consumed = max(consumed, hit.end)
        guard let plate = Plate.plate(for: hit.code) else { return }
        if let last = lastLogged[hit.code],
           Date().timeIntervalSince(last) < Self.cooldown { return }
        lastLogged[hit.code] = Date()
        onHeard?(plate)
    }

    /// Marks a plate as just logged without logging it.
    ///
    /// For the one that arrived through Siri — "log New Jersey in Tags". It is on
    /// the board before the microphone opens, and the person who said it is quite
    /// likely to say it again while watching to see whether it worked. Putting it
    /// straight into the cooldown makes that second call-out a no-op rather than a
    /// repeat sighting.
    func claim(_ code: String) {
        lastLogged[code] = Date()
    }

    /// The opposite: lets a plate be logged again straight away.
    ///
    /// For undo. The cooldown exists so a name still hanging in the air is not logged
    /// twice; once the sighting has been taken back, that reasoning is gone and the
    /// guard is only in the way.
    func release(_ code: String) {
        lastLogged[code] = nil
    }

    #if DEBUG
    /// Push a transcript through the real matching path without a microphone.
    ///
    /// The simulator has no usable mic, and more to the point the interesting bugs in
    /// this feature are not acoustic — they are "New Jersey logged eleven times"
    /// and "Washington DC logged Washington". Both are reachable from text, so both
    /// are testable from text. `-voice "new jersey ohio thats a texas"`.
    func feed(_ text: String) {
        status = .listening
        if ticker == nil { startTicker() }
        ingest(text)
    }
    #endif

    /// Replaces each phrase with spaces of the same length, leaving every other
    /// character where it was.
    ///
    /// Longest *prefix* rather than whole phrase, because the microphone rarely gets
    /// all of what the app said. Echo cancellation clips the start, the road drowns
    /// the middle, and "New Jersey. The Garden State has more diners than anywhere"
    /// comes back as "new jersey the garden". Matching only the complete utterance
    /// would leave that in the transcript — with the plate name still in it, which is
    /// the whole thing being prevented.
    static func strike(_ phrases: [String], from text: String, after: Int = 0) -> String {
        var chars = Array(text)
        let floor = max(0, min(after, chars.count))
        for phrase in phrases where phrase.count >= minEcho {
            var length = phrase.count
            while length >= minEcho {
                let needle = Array(phrase.prefix(length))
                if let at = index(of: needle, in: chars, from: floor) {
                    for j in at..<(at + needle.count) { chars[j] = " " }
                    break
                }
                length -= 1
            }
        }
        return String(chars)
    }

    /// Short enough to catch "new jersey", long enough that it is not striking words
    /// out of what somebody actually said.
    private static let minEcho = 8

    private static func index(of needle: [Character], in haystack: [Character],
                              from start: Int) -> Int? {
        guard !needle.isEmpty, start + needle.count <= haystack.count else { return nil }
        for i in start...(haystack.count - needle.count)
        where Array(haystack[i..<(i + needle.count)]) == needle {
            return i
        }
        return nil
    }

    private static func peak(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var loudest: Float = 0
        for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(data[i])) }
        // Compressed hard: speech peaks low and a linear ring barely moves.
        return min(1, Double(loudest) * 4)
    }
}
