import SwiftData
import SwiftUI

/// Voice mode: the phone in the cupholder, everyone calling plates, nobody tapping.
///
/// The whole screen does one thing, and the restraint is the design. There is no
/// confirmation step, no "did you mean", no wake word — you say a state and it goes
/// on the board with a haptic. That is only defensible because it is trivially
/// reversible: everything logged this session sits in a list with an Undo beside it,
/// so a mishearing costs one tap and never has to be hunted down in the grid later.
///
/// Deliberately not a background feature. It runs while this screen is open and stops
/// when it closes, because a microphone that keeps listening after you have put the
/// phone down is a different product from a plate game.
struct VoiceModeScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let collection: any PlateCollection
    var players: [Player] = []

    @State private var voice = VoiceLogger()
    @State private var speech = VoiceSpeaker()
    /// True until somebody has been named. With one player there is nobody to ask.
    @State private var askingWho = false
    @State private var logged: [Entry] = []
    /// The transcript that last triggered an undo, so its revisions cannot trigger
    /// another. See `hearUndo`.
    @State private var lastUndoHeard = ""
    /// A plate whose repeat guard is being held only until the app stops talking about
    /// it. See `hearUndo`.
    @State private var releaseAfterSpeech: String?
    @State private var speaker: Player?
    @AppStorage("voiceSpeaker") private var speakerID = ""

    private let location = TripLocation.shared

    #if DEBUG
    /// `-voice "new jersey ohio thats a texas"`.
    static var launchTranscript: String? { Self.argument("-voice") }

    /// `-siri NJ` stands in for "Hey Siri, log New Jersey in Plates", which is
    /// otherwise only reachable by actually talking to Siri on a real phone.
    static var launchPlate: String? { Self.argument("-siri") }

    private static func argument(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count,
              !args[i + 1].hasPrefix("-") else { return nil }
        return args[i + 1]
    }
    #endif

    private struct Entry: Identifiable {
        let id = UUID()
        let plate: Plate
        let outcome: PlateLogger.Outcome
        let at = Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    listener
                    if players.count > 1 { speakerPicker }
                    Divider().overlay(Theme.line)
                    heard
                }
            }
            .navigationTitle("Voice mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.plates(size: 16, weight: .semibold))
                }
            }
        }
        .task {
            speaker = players.first { $0.id.uuidString == speakerID } ?? players.first
            voice.onHeard = { plate in log(plate) }
            voice.onPhrase = { heard in
                hearPlayer(in: heard)
                hearUndo(in: heard)
                hearStop(in: heard)
            }
            voice.ownWords = { speech.recentlySaid.map(\.text) }

            // The app talks, then listens. Wiring the second to the *end* of the
            // first — rather than to a guess at how long it takes to say — is what
            // stops the opening prompt being transcribed as the first answer.
            speech.onStarted = { voice.duckOthers(true) }
            speech.onFinished = {
                voice.isMuted = false
                voice.duckOthers(false)
                if let code = releaseAfterSpeech {
                    voice.release(code)
                    releaseAfterSpeech = nil
                }
            }
            #if DEBUG
            if let scripted = Self.launchTranscript {
                // Word by word, the way the recogniser revises it, so the run
                // exercises the de-duplication rather than stepping around it.
                var said = ""
                for word in scripted.split(separator: " ") {
                    said += (said.isEmpty ? "" : " ") + word
                    voice.feed(said)
                    try? await Task.sleep(for: .milliseconds(120))
                }
                return
            }
            #endif
            #if DEBUG
            if let forced = Self.launchPlate { VoiceHandoff.shared.handOff(plate: forced) }
            #endif
            await voice.start()

            // "Log New Jersey in Plates" arrives with the plate already named. Log it
            // and let the confirmation stand in for the greeting — being asked "what
            // did you see?" immediately after saying what you saw is the kind of thing
            // that makes people stop trusting a voice interface.
            if let code = VoiceHandoff.shared.takePendingPlate(),
               let named = Plate.plate(for: code) {
                voice.claim(named.code)
                log(named)
            } else {
                greet()
            }
        }
        .onDisappear {
            voice.stop()
            speech.stop()
        }
    }

    // MARK: - The listening half

    private var listener: some View {
        VStack(spacing: 14) {
            ZStack {
                // Grows with the room. The only moving thing on the screen, so it is
                // also the only proof that the microphone is actually open.
                Circle()
                    .fill(Theme.route.opacity(0.13))
                    .frame(width: 132, height: 132)
                    .scaleEffect(isListening ? 1 + voice.level * 0.45 : 1)
                    .animation(.easeOut(duration: 0.12), value: voice.level)

                Circle()
                    .fill(isListening ? Theme.route : Theme.inkMuted.opacity(0.5))
                    .frame(width: 84, height: 84)

                Image(systemName: isListening ? "waveform" : "mic.slash.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.top, 26)

            Text(headline)
                .font(.plates(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(subhead)
                .font(.plates(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .frame(minHeight: 34, alignment: .top)

            if case .denied(let why) = voice.status {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.plates(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(Theme.route))
                .accessibilityHint(why)
            }

            // The app picks the most natural voice installed, but a device that has
            // never downloaded one has only the compact voice to offer, and no app
            // can fetch it on the user's behalf. Said once, early: it disappears as
            // soon as anything is logged, because by then it is just clutter.
            if VoiceSpeaker.voiceIsCompact && logged.isEmpty {
                Text("Voice sounds robotic? Download a natural one in \(VoiceSpeaker.voiceSettingsPath), then tap the \u{2913} beside a voice marked Enhanced or Premium.")
                    .font(.plates(size: 11))
                    .foregroundStyle(Theme.inkMuted.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
            }
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private var isListening: Bool { voice.status == .listening }

    private var headline: String {
        switch voice.status {
        case .listening: return "Listening"
        case .starting:  return "Starting…"
        case .idle:      return "Paused"
        case .denied:    return "Microphone is off"
        case .failed:    return "Could not listen"
        }
    }

    /// Shows the live transcript once there is one, and instructions before that.
    /// Both matter: the instruction teaches the interaction, and the transcript is
    /// what makes a silent microphone believable.
    private var subhead: String {
        switch voice.status {
        case .listening:
            let heard = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if heard.isEmpty {
                return "Just say the states as you see them — \u{201C}New Jersey\u{201D}, \u{201C}Ohio\u{201D}, \u{201C}that\u{2019}s a Texas\u{201D}."
            }
            return "\u{201C}" + String(heard.suffix(70)) + "\u{201D}"
        case .denied(let why):  return why
        case .failed(let why):  return why
        default:                return ""
        }
    }

    // MARK: - Who is talking

    /// Only when there is more than one player. Voice cannot tell who spoke, so this
    /// is the honest version: say up front whose finds these are, and let it be
    /// changed mid-drive when the phone gets handed over.
    private var speakerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Logging as")
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                ForEach(players) { player in
                    let on = speaker?.id == player.id
                    Button {
                        speaker = player
                        speakerID = player.id.uuidString
                        Haptics.selection()
                    } label: {
                        Text(player.name)
                            .font(.plates(size: 13, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? .white : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                Capsule().fill(on ? Theme.playerColor(player.colorIndex)
                                                  : Theme.surface))
                            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.bottom, 12)
    }

    // MARK: - What it heard

    @ViewBuilder
    private var heard: some View {
        if logged.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "car.side")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.inkMuted.opacity(0.55))
                Text("Nothing logged yet")
                    .font(.plates(size: 14))
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(logged) { entry in
                        row(entry)
                    }
                }
                .padding(Theme.screenPadding)
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            PlateTile(plate: entry.plate, isFound: true,
                      rarity: collection.rarity(of: entry.plate.code))
                .frame(width: 86)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.plate.name)
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(entry.outcome.isFirstFind
                     ? entry.outcome.tier.label.capitalized
                     : "Seen \(entry.outcome.count) times")
                    .font(.plates(size: 12))
                    .foregroundStyle(entry.outcome.isFirstFind && entry.outcome.tier >= .rare
                                     ? entry.outcome.tier.color : Theme.inkMuted)
            }

            Spacer(minLength: 0)

            Button("Undo") { undo(entry) }
                .font(.plates(size: 13, weight: .semibold))
                .foregroundStyle(Theme.route)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.line, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Talking

    /// The opening line, and the only place the app asks a question.
    ///
    /// Two players or more and it does not know whose finds these are, so it asks.
    /// One player and asking would be theatre — it says what it wants and starts.
    private func greet() {
        guard voice.status == .listening else { return }
        voice.isMuted = true
        if players.count > 1 && speaker == nil {
            askingWho = true
            speech.say("Who is logging?")
        } else if let speaker, players.count > 1 {
            speech.say("Logging for \(speaker.name). What did you see?")
        } else {
            speech.say("What did you see?")
        }
    }

    /// Catches a player's name in the answer to "who is logging?".
    ///
    /// Only while that question is open. Left running it would reassign the logger
    /// every time somebody in the back said a name, which is a very easy way to put
    /// forty plates on the wrong person.
    private func hearPlayer(in heard: String) {
        guard askingWho else { return }
        let said = PlateSpeech.normalise(heard)
        guard let match = players.first(where: {
            let name = PlateSpeech.normalise($0.name)
            return !name.isEmpty && (" " + said + " ").contains(" " + name + " ")
        }) else { return }

        askingWho = false
        speaker = match
        speakerID = match.id.uuidString
        Haptics.selection()
        voice.isMuted = true
        speech.say("Thanks \(match.name). What did you see?")
    }

    /// "Undo", and the last thing logged comes back off.
    ///
    /// The spoken twin of the Undo button beside every row, and the reason the button
    /// can stay where it is: reaching for it means looking at the screen, which is the
    /// one thing this whole mode exists to avoid. A mishearing is now fixable in the
    /// same breath that noticed it.
    private func hearUndo(in heard: String) {
        guard !askingWho, PlateSpeech.saysUndo(heard) else { return }
        // The same words, re-sent. A recogniser revises a phrase several times before
        // it settles, and every one of those revisions still ends in "undo" — without
        // this the sentence unwinds the session one plate at a time.
        let said = PlateSpeech.normalise(heard)
        guard said != lastUndoHeard else { return }
        lastUndoHeard = said

        guard let newest = logged.first else {
            speech.say("Nothing to undo.")
            return
        }
        undo(newest)

        // NOT muted while this is said, for the reason `log` sets out — and with more
        // force here. The word after "undo" is very often the plate that was meant,
        // and muting to say "Ohio removed" would deafen the app for exactly the second
        // it takes somebody to correct themselves.
        //
        // `undo` has just cleared this plate's repeat guard, which is right for a
        // person and wrong for the confirmation about to be spoken: the app is a
        // moment away from saying the plate's name out loud, and hearing itself would
        // put back what was just taken off. So the guard goes on again for the length
        // of the sentence and comes off when it ends.
        voice.claim(newest.plate.code)
        releaseAfterSpeech = newest.plate.code
        speech.say("\(newest.plate.name) removed.")
    }

    /// "Stop", and the session ends.
    ///
    /// Hands-free has to include the way out, or the last thing you do every drive is
    /// pick the phone up to end something you started by talking to it.
    private func hearStop(in heard: String) {
        guard !askingWho, PlateSpeech.saysStop(heard) else { return }
        voice.stop()
        speech.stop()
        Haptics.undo()
        dismiss()
    }

    // MARK: - Acting

    private func log(_ plate: Plate) {
        let outcome = PlateLogger.record(plate, in: collection, by: speaker,
                                         at: location.coordinate, context: context)
        withAnimation(.snappy(duration: 0.25)) {
            logged.insert(Entry(plate: plate, outcome: outcome), at: 0)
        }
        // The whole confirmation, and it has to be felt rather than seen: the screen
        // is in a cupholder and everybody's eyes are out of the window.
        if outcome.isFirstFind { outcome.tier.playHaptic() } else { Haptics.repeatSighting() }

        // Said out loud as well as felt. The haptic confirms *something* happened;
        // only the name confirms it was the right something, and hands-free means
        // never having to look to find that out.
        //
        // NOT muted while this is said, deliberately. Muting drops everything the
        // microphone hears for the second or so the app is talking, which is exactly
        // when the next person calls the next plate — and losing a real sighting is a
        // worse failure than the one muting prevents. It is also a failure that
        // cannot happen: the only plate name in a confirmation is the one just
        // logged, and that code is inside its own cooldown for four seconds, so
        // hearing itself changes nothing.
        speech.say(VoiceSpeaker.confirmation(for: plate, outcome: outcome))
    }

    /// Removes the sighting this entry created, not every sighting of the plate — a
    /// mishearing on the fourth Ohio of the day must not wipe the first three.
    private func undo(_ entry: Entry) {
        let matches = collection.allSightings
            .filter { $0.plateCode == entry.plate.code }
            .sorted { $0.spottedAt > $1.spottedAt }
        if let newest = matches.first {
            let withdrawn = newest.id
            let trip = newest.trip?.id
            context.delete(newest)
            try? context.save()
            if let trip { PartySession.shared?.broadcastRemoval([withdrawn], in: trip) }
        }
        withAnimation(.snappy(duration: 0.2)) {
            logged.removeAll { $0.id == entry.id }
        }
        // Out of the cooldown as well as off the board. A plate is undone because it
        // was the wrong one *or* because it was right and got mangled, and in the
        // second case the next thing said is the same state again — which the
        // four-second repeat guard would otherwise swallow.
        voice.release(entry.plate.code)
        Haptics.undo()
    }
}
