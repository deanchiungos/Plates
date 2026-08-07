import AppIntents
import SwiftData

// Siri, via App Intents.
//
// These run inside the app's process but outside its view hierarchy, so they reach
// SwiftData through `PlatesStore` rather than the environment. `openAppWhenRun` is
// false throughout: the entire point is logging a plate at 70mph without unlocking
// anything.
//
// One platform constraint worth knowing: an App Shortcut phrase **must** contain the
// app name. "Hey Siri, log a New Jersey plate" cannot be registered by an app; it has
// to be "…in Plates". Users can rename any of these to whatever they like in the
// Shortcuts app, which is the supported way to get a shorter phrase.

// MARK: - The plate as something Siri can name

struct PlateEntity: AppEntity {
    let id: String          // the two-letter code
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Plate" }
    static var defaultQuery = PlateQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }

    init(_ plate: Plate) {
        id = plate.code
        name = plate.name
    }
}

/// `EntityStringQuery`, not a plain `EntityQuery`, so Siri can turn the words it
/// heard into a plate. Without the string half, "New Jersey" resolves to nothing and
/// every request turns into a disambiguation list of sixty-five options.
struct PlateQuery: EntityStringQuery {

    func entities(for identifiers: [String]) async throws -> [PlateEntity] {
        identifiers.compactMap { Plate.plate(for: $0).map(PlateEntity.init) }
    }

    /// Returns the *narrowest* tier of match that hit, not everything that hit.
    ///
    /// This is the difference between one answer and a menu. The old version
    /// returned exact, prefix and substring matches all together, so "New Jersey"
    /// came back as four entities — New Jersey plus every other state containing
    /// "new" — and App Intents can only respond to four candidates by reading them
    /// out and asking you to pick. At the wheel that is the whole failure.
    ///
    /// So: if anything matches exactly, that is the answer and nothing else is
    /// offered. Only if nothing does are looser matches considered.
    func entities(matching string: String) async throws -> [PlateEntity] {
        let q = Self.normalise(string)
        guard !q.isEmpty else { return [] }

        // Spoken shorthands that no amount of substring matching would ever reach.
        if let code = Self.spokenAliases[q], let plate = Plate.plate(for: code) {
            return [PlateEntity(plate)]
        }

        let exact = Plate.all.filter {
            Self.normalise($0.name) == q || Self.normalise($0.short) == q
                || $0.code.lowercased() == q
        }
        if !exact.isEmpty { return exact.map(PlateEntity.init) }

        let prefix = Plate.all.filter { Self.normalise($0.name).hasPrefix(q) }
        if !prefix.isEmpty { return prefix.map(PlateEntity.init) }

        // Last resort: "jersey" for New Jersey, "carolina" for either of them.
        return Plate.all
            .filter { Self.normalise($0.name).contains(q) }
            .map(PlateEntity.init)
    }

    /// Strips the things speech transcription varies on: case, accents, punctuation
    /// and the spaces inside "New  Jersey".
    private static func normalise(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How people actually say these out loud.
    ///
    /// One table, shared with voice mode. There were two, they had already drifted —
    /// voice mode knew "organ" was Oregon and Siri did not — and a jurisdiction the
    /// app can hear one way but not the other is the sort of inconsistency nobody
    /// ever reports as a bug, they just stop using the feature.
    private static let spokenAliases = PlateSpeech.aliases

    /// Deliberately short.
    ///
    /// These are what the Shortcuts app offers in a picker, and they are also what
    /// gets read aloud if disambiguation ever does happen. Sixty-five entries made
    /// that read-out interminable; the handful you have not found yet on the thing
    /// you are currently filling is both shorter and more useful.
    @MainActor
    func suggestedEntities() async throws -> [PlateEntity] {
        guard let target = PlatesStore.currentTarget() else {
            return Array(Plate.states.prefix(8)).map(PlateEntity.init)
        }
        let unfound = Plate.states.filter { !target.hasSeen($0) }
        return Array((unfound.isEmpty ? Plate.states : unfound).prefix(8))
            .map(PlateEntity.init)
    }
}

// MARK: - Log a plate

struct LogPlateIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a plate"
    static var description = IntentDescription(
        "Records a plate on whatever you are filling — a trip or your book — and reads back something about it.")
    static var openAppWhenRun = false

    /// `requestValueDialog` is the whole fix for "log a plate".
    ///
    /// Without it, an unfilled entity parameter is resolved by *disambiguation*:
    /// Siri reads the candidate list aloud and waits for a tap. With it, Siri asks
    /// the question out loud and listens, and the answer goes through
    /// `PlateQuery.entities(matching:)` — which is speech, end to end, hands never
    /// leaving the wheel.
    @Parameter(title: "Plate",
               requestValueDialog: IntentDialog("Which plate did you see?"))
    var plate: PlateEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$plate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = Plate.plate(for: plate.id) else {
            return .result(dialog: "I do not know that plate.")
        }
        guard let trip = PlatesStore.currentTarget() else {
            return .result(dialog: "Start a trip or a book in Plates first.")
        }

        if trip.hasSeen(target) {
            let count = trip.sightingCount(for: target)
            return .result(dialog: IntentDialog(
                "You already logged \(target.name) on \(trip.name)\(count > 1 ? ", \(count) times" : "")."))
        }

        // Attributed to this phone's own player, like every other way in. It used to
        // land unowned, on the reasoning that Siri cannot ask who spotted it
        // mid-drive — true, and no longer a question anyone has to answer: the phone
        // being spoken to *is* the person. A Siri-logged plate now shows up in the
        // standings instead of quietly counting for nobody.
        //
        // Through `PlateLogger` like every other route in, which is what gets a
        // Siri-logged plate its banked rarity and its place on the trail. Logging it
        // here by hand is how it went without both for as long as it did.
        let outcome = PlateLogger.record(target, in: trip,
                                         by: DevicePlayer.current(in: PlatesStore.context),
                                         at: TripLocation.shared.coordinate,
                                         context: PlatesStore.context)
        let tier = outcome.tier
        let fact = FactBook.fact(for: target.code)

        var line = "\(target.name) logged."
        if tier >= .rare { line = "\(tier.label.capitalized)! " + line }
        line += " That is \(trip.statesFound) of \(Plate.stateTotal)."
        if let fact { line += " \(fact)" }

        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - How am I doing

struct PlateProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Check plate progress"
    static var description = IntentDescription(
        "Says how many plates you have logged on the trip or book you are filling.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let trip = PlatesStore.currentTarget() else {
            return .result(value: 0, dialog: "You have not started a trip or a book yet.")
        }

        let states = trip.statesFound
        let extra = trip.platesFound - states

        var line = "You have logged \(states) of \(Plate.stateTotal) states on \(trip.name)"
        if extra > 0 {
            line += ", plus \(extra) bonus plate\(extra == 1 ? "" : "s")"
        }
        line += "."

        return .result(value: states, dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - Have I got it

struct PlateStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a plate"
    static var description = IntentDescription(
        "Says whether you have already logged a particular plate, and how rare it is.")
    static var openAppWhenRun = false

    @Parameter(title: "Plate",
               requestValueDialog: IntentDialog("Which plate shall I check?"))
    var plate: PlateEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$plate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        guard let target = Plate.plate(for: plate.id),
              let trip = PlatesStore.currentTarget() else {
            return .result(value: false, dialog: "I could not check that.")
        }

        let found = trip.hasSeen(target)
        let tier = RarityTier.forRarity(PlateRarity.rarity(target.code, on: trip.route))
        let line = found
            ? "Yes, \(target.name) is already logged."
            : "Not yet. \(target.name) is \(tier.label.lowercased())."

        return .result(value: found, dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - What should I look for

struct RarestFindIntent: AppIntent {
    static var title: LocalizedStringResource = "Best plate so far"
    static var description = IntentDescription(
        "Names the rarest plate you have logged.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trip = PlatesStore.currentTarget() else {
            return .result(dialog: "You have not started a trip or a book yet.")
        }

        let best = trip.seenCodes
            .compactMap { Plate.plate(for: $0) }
            .max { trip.rarity(of: $0) < trip.rarity(of: $1) }

        guard let best else {
            return .result(dialog: "You have not logged anything yet.")
        }

        let tier = RarityTier.forRarity(trip.rarity(of: best))
        return .result(dialog: IntentDialog(
            "Your best find is \(best.name), \(tier.label.lowercased()), on \(trip.name)."))
    }
}


// MARK: - Hands free

/// "Hey Siri, log some plates in Plates" — and then stop talking to Siri.
///
/// The other intents here each do one thing per invocation, which is right for "have
/// I logged Ohio" and wrong for a drive. This one opens the app's own voice mode and
/// gets out of the way: after this you are talking to Plates, not to Siri, and you
/// can call twenty plates without saying the app's name again.
///
/// `openAppWhenRun` is true, uniquely. Every other intent avoids it on purpose —
/// logging a plate should not drag you out of your map app — but a microphone that
/// opens without the app coming forward would be listening invisibly, which is not a
/// thing to build.
struct StartVoiceModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Start voice mode"
    static var description = IntentDescription(
        "Opens Plates and starts listening, so you can call out plates without touching anything.")
    static var openAppWhenRun = true

    /// Optional, and that is the whole trick.
    ///
    /// It lets one intent answer both "log a plate in Plates" and "log New Jersey in
    /// Plates". Optional parameters are never prompted for, so the bare phrase does
    /// not turn into Siri asking "which plate?" — it just opens the microphone. When
    /// a plate *was* named, it rides along and is logged as the screen opens, because
    /// making somebody repeat a word they already said is the thing voice mode exists
    /// to avoid.
    @Parameter(title: "Plate")
    var plate: PlateEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start voice mode") {
            \.$plate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceHandoff.shared.handOff(plate: plate?.id)
        return .result()
    }
}

// MARK: - Phrases

/// EVERY SPOKEN ROUTE THAT INVOLVES LOGGING NOW OPENS VOICE MODE.
///
/// It used to be split: naming a plate ran `LogPlateIntent` without opening the app,
/// which is lovely when it works and is the exact thing that kept not working — Siri
/// has to match a phrase *and* resolve a state name inside it, and it would drop the
/// whole request rather than get half of it right. One plate per invocation also meant
/// saying "in Plates" again for the next one.
///
/// So all of it — "log a plate", "log New Jersey", "I saw a plate", "start voice mode"
/// — lands on `StartVoiceModeIntent`. Siri only has to match the phrase; the state
/// name is then heard by the app's own recogniser, which knows sixty-five candidates
/// instead of the entire language. And you are left in a mode that takes the next
/// twenty plates without being spoken to again.
///
/// "OPEN PLATES" IS DELIBERATELY NOT HERE, and no phrase below may begin with "Open
/// \(.applicationName)". A plain launch has to stay a plain launch: it is
/// indistinguishable from tapping the icon, so treating it as a voice request would
/// open the microphone every time anybody opened the app.
///
/// `LogPlateIntent` and `PlateStatusIntent` are kept as intents — they still appear in
/// the Shortcuts app, and any shortcut or automation already built on them still runs.
/// They have simply lost their spoken phrases.
struct PlatesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // First, so it is the one Siri reaches for when the app is named.
        AppShortcut(
            intent: StartVoiceModeIntent(),
            phrases: [
                "Log \(\.$plate) in \(.applicationName)",
                "Log a plate in \(.applicationName)",
                "Log plates in \(.applicationName)",
                "Log something in \(.applicationName)",
                "I saw \(\.$plate) in \(.applicationName)",
                "Add a plate in \(.applicationName)",
                "Start voice mode in \(.applicationName)",
                "Start logging in \(.applicationName)",
                "Listen in \(.applicationName)",
                "\(.applicationName) voice mode"
            ],
            shortTitle: "Voice mode",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: PlateProgressIntent(),
            phrases: [
                "How many plates have I logged in \(.applicationName)",
                "My \(.applicationName) progress",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "Plate progress",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: RarestFindIntent(),
            phrases: [
                "What is my best find in \(.applicationName)",
                "My rarest plate in \(.applicationName)"
            ],
            shortTitle: "Best find",
            systemImageName: "rosette"
        )
    }
}
