import Foundation

/// Finding jurisdictions in something a person said out loud.
///
/// This is the part that makes voice mode better than Siri, and it is not clever —
/// it is just narrow. A general assistant hears "new jersey" with the whole English
/// language as the candidate space. This has sixty-five candidates, knows every one
/// of them in advance, and can therefore afford to be generous about how they are
/// pronounced, mangled and abbreviated.
///
/// Speech transcription is the weak link, not intent. `SFSpeechRecognizer` is
/// confident and wrong in predictable ways: Oregon becomes "organ", Maine becomes
/// "main", Connecticut becomes "connect a cut". Those are cheap to fix here and
/// impossible to fix anywhere else.
enum PlateSpeech {

    /// A jurisdiction found in a transcript, and where it was found.
    ///
    /// The range matters as much as the code. A live transcript is revised as it is
    /// spoken — "new" becomes "new jer" becomes "new jersey" — so acting on a match
    /// without knowing where it sat would log New Jersey once per revision.
    struct Hit: Equatable {
        let code: String
        /// Offset into the *normalised* transcript, in characters.
        let end: Int
    }

    // MARK: - Vocabulary

    /// Spoken forms that are not simply the jurisdiction's name.
    ///
    /// Three kinds, and they earn their place differently:
    ///
    /// - **Shorthands people actually say.** Nobody says "District of Columbia" in a
    ///   moving car, and "mass", "penn" and "cali" are what comes out.
    /// - **Transcription failures.** "Organ" for Oregon and "main" for Maine are what
    ///   the recogniser returns, not what anyone said, and no amount of matching on
    ///   the correct spelling will ever see them.
    /// - **Letters.** Two-letter codes get transcribed spaced out — "n j", "d c" —
    ///   and are worth catching because a passenger who knows the codes will use them.
    ///
    /// Deliberately excludes anything ambiguous. "Carolina" is not here, because it
    /// is two states and guessing which would be worse than not hearing it; the same
    /// goes for "dakota", "virginia" and "new".
    static let aliases: [String: String] = [
        // shorthands
        "dc": "DC", "d c": "DC", "washington dc": "DC", "washington d c": "DC",
        "the district": "DC",
        "pr": "PR", "p r": "PR",
        "mass": "MA", "penn": "PA", "cali": "CA", "jersey": "NJ",
        "new york city": "NY", "nyc": "NY", "n y c": "NY",
        "bc": "BC", "b c": "BC", "pei": "PE", "p e i": "PE",
        "newfoundland": "NL", "nwt": "NT", "n w t": "NT",
        "sask": "SK", "washington state": "WA",

        // what the recogniser hears
        "organ": "OR", "oregon state": "OR",
        "main": "ME",
        "connect a cut": "CT", "connecticut": "CT",
        "arkansaw": "AR", "our kansas": "AR",
        "i owe a": "IA", "ioway": "IA",
        "hawai i": "HI",
        "kay beck": "QC", "quebec": "QC",
        "you kon": "YT", "yukon territory": "YT",
        "new found land": "NL", "newfoundland and labrador": "NL",
        "prince edward island": "PE",
        "north west territories": "NT", "northwest territories": "NT",
        "nova scotia": "NS", "new brunswick": "NB",
        "rhode island": "RI", "road island": "RI",
        "new hampshire": "NH", "new hamster": "NH",
        "west virginia": "WV", "virginia": "VA",
    ]

    /// Every phrase that resolves to a jurisdiction, longest first.
    ///
    /// Longest-first is load-bearing in both directions. Without it "new york"
    /// matches "york" first and "washington dc" matches "washington", so the two
    /// hardest cases in the set both come out wrong.
    private static let phrases: [(String, String)] = {
        var table: [String: String] = [:]
        for plate in Plate.all {
            table[normalise(plate.name)] = plate.code
            table[normalise(plate.short)] = plate.code
            // "n j", spaced, because that is how letters are transcribed. The bare
            // "nj" is not included: it is not a word anybody says, and as a
            // substring it would fire inside other words.
            table[plate.code.lowercased().map(String.init).joined(separator: " ")] = plate.code
        }
        for (phrase, code) in aliases { table[normalise(phrase)] = code }
        return table.sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value) }
    }()

    // MARK: - Matching

    /// Lower-cased, unaccented, punctuation-free, single-spaced.
    ///
    /// Padded with a space at each end so that every phrase can be matched with
    /// spaces around it — which is what keeps "maine" out of "domain" and, more to
    /// the point here, "or" out of every other sentence.
    static func normalise(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                 locale: .current)
        let cleaned = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Every jurisdiction mentioned in a transcript, in the order they were said.
    ///
    /// Overlapping matches are resolved by taking the longest: "new york" wins over
    /// "york", and the characters it consumed are not offered to any shorter phrase.
    static func hits(in transcript: String) -> [Hit] {
        let text = " " + normalise(transcript) + " "
        guard text.count > 2 else { return [] }

        var claimed = [Bool](repeating: false, count: text.count)
        var found: [(Int, Hit)] = []
        let chars = Array(text)

        for (phrase, code) in phrases {
            let needle = Array(" " + phrase + " ")
            guard needle.count <= chars.count else { continue }
            var i = 0
            while i <= chars.count - needle.count {
                if Array(chars[i..<(i + needle.count)]) == needle {
                    // The trailing space belongs to the *next* word as much as this
                    // one, so it is left unclaimed — otherwise two jurisdictions said
                    // back to back would swallow each other's boundary.
                    let body = i..<(i + needle.count - 1)
                    if !body.contains(where: { claimed[$0] }) {
                        for j in body { claimed[j] = true }
                        found.append((i, Hit(code: code, end: i + needle.count - 1)))
                    }
                    i += needle.count - 1
                } else {
                    i += 1
                }
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Ways of saying "that's enough".
    ///
    /// Matched as whole phrases with spaces around them, like everything else here,
    /// so "stop" does not fire inside "stopped" and — more to the point — a plate
    /// called out as "stop, Ohio!" still logs Ohio before the listening ends.
    private static let stopPhrases = [
        "stop", "stop listening", "thats enough", "that is enough",
        "im done", "i am done", "were done", "we are done", "finished",
        "stop voice mode", "turn it off",
    ]

    /// Whether the tail of what was said is an instruction to stop.
    ///
    /// Only the tail. The whole transcript is re-sent on every revision, so matching
    /// anywhere in it would mean a "stop" said two minutes ago ends the session the
    /// moment anybody says anything else.
    static func saysStop(_ transcript: String) -> Bool {
        let text = " " + normalise(transcript) + " "
        let tail = String(text.suffix(28))
        return stopPhrases.contains { tail.contains(" " + $0 + " ") }
    }

    /// Ways of saying "not that one".
    ///
    /// "Undue" is in here because it is what the recogniser returns for "undo" often
    /// enough to matter, and because nobody in a car has ever said the actual word.
    private static let undoPhrases = [
        "undo", "undue", "undo that", "undo it", "scratch that", "take that back",
        "remove that", "delete that", "cancel that", "not that one", "wrong one",
    ]

    /// Whether what was said *ends* with an instruction to undo.
    ///
    /// Ends with, rather than contains — which is stricter than `saysStop` and has to
    /// be. Stopping ends the session, so a second match costs nothing; undoing removes
    /// a sighting, and a live transcript is re-sent on every revision. Matching
    /// anywhere in it would take "undo" said once and unwind the whole session one
    /// plate per revision. As the end of the sentence it fires once, and the moment
    /// another word arrives it stops matching.
    static func saysUndo(_ transcript: String) -> Bool {
        let text = " " + normalise(transcript)
        return undoPhrases.contains { text.hasSuffix(" " + $0) }
    }

    /// The single best jurisdiction in a phrase, for one-shot uses like Siri.
    static func best(in transcript: String) -> String? {
        hits(in: transcript).last?.code
    }
}
