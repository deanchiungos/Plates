import Foundation

/// Road-trip trivia, several lines per region, loaded from `PlateFacts.json`.
///
/// The content lives in JSON rather than in a Swift literal so it can be edited
/// with ordinary tools — a text editor, a script, a spreadsheet via
/// `tools/facts.py` — without touching code or understanding Swift escaping. This
/// file is only the reader.
///
/// **To add or change a fact, edit `Plates/Resources/PlateFacts.json`.** Keys are
/// `Plate.code`; each value is an array of sentences. Adding, deleting and
/// reordering are all safe — `FactBook` tracks what has been read by content, not
/// by position.
///
/// Editorial conventions, for anything added later: one sentence, at most about 120
/// characters, aimed at a kid reading it aloud in a back seat. Dry and specific, no
/// exclamation marks, no claim that cannot be checked. Not only about plates —
/// slogans run out fast, so roads, bridges, car history and landmarks all count, as
/// long as the fact belongs to that region.
///
/// `FactBook` decides which one you actually see, and remembers the ones already read.
enum PlateFacts {

    /// Keyed by `Plate.code`. Empty only if the bundled JSON is missing or broken,
    /// which in a debug build stops the app instead.
    static let byCode: [String: [String]] = load()

    static func facts(for code: String) -> [String] { byCode[code] ?? [] }

    /// A stable identifier for a fact, derived from its text.
    ///
    /// This is what `FactBook` records as "already read", rather than the fact's
    /// position in the array. Position is the obvious choice and it is a trap:
    /// inserting a line at the top of a region shifts every index below it, so facts
    /// already read would point at different sentences — and a newly added fact
    /// could be born already marked as seen, so you would not see it for a whole
    /// cycle. Keying on content means facts can be added, deleted and reordered
    /// freely. Rewording one makes it unread again, which is right: it is a
    /// different sentence now.
    ///
    /// FNV-1a rather than `hashValue`, because Swift seeds its hashing per process
    /// and the value would differ on every launch.
    static func id(of fact: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in fact.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    // MARK: - Loading

    /// Two different failures, treated differently.
    ///
    /// A *missing* file is something you did on purpose — pulled it out to work on
    /// it elsewhere — so the app says so in the console and runs on without trivia.
    /// *Malformed* JSON is a typo you want shouted about the moment you make it, so
    /// debug builds stop dead with the parse error.
    ///
    /// Release never crashes either way: a broken resource must not take down a
    /// shipped app over what is, in the end, decoration.
    private static func load() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "PlateFacts", withExtension: "json") else {
            #if DEBUG
            print("[PlateFacts] PlateFacts.json is not in the bundle — no trivia will "
                  + "show. Put it back at Plates/Resources/PlateFacts.json.")
            #endif
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
            #if DEBUG
            audit(decoded)
            #endif
            return decoded
        } catch {
            #if DEBUG
            fatalError("PlateFacts.json could not be read: \(error)")
            #else
            return [:]
            #endif
        }
    }

    #if DEBUG
    /// Debug-only sanity check on hand-edited content. Complains in the console
    /// rather than crashing: a region briefly left empty mid-edit should not stop
    /// you running the app.
    private static func audit(_ facts: [String: [String]]) {
        let known = Set(Plate.all.map(\.code))

        for code in known.subtracting(facts.keys).sorted() {
            print("[PlateFacts] no facts for \(code)")
        }
        for code in Set(facts.keys).subtracting(known).sorted() {
            print("[PlateFacts] \(code) is not a plate code")
        }
        for (code, lines) in facts.sorted(by: { $0.key < $1.key }) {
            if lines.isEmpty {
                print("[PlateFacts] \(code) has an empty list")
            }
            if Set(lines).count != lines.count {
                print("[PlateFacts] \(code) repeats a fact")
            }
            for line in lines where line.count > 120 {
                print("[PlateFacts] \(code) is \(line.count) chars, over the 120 guide: \(line)")
            }
        }
    }
    #endif
}
