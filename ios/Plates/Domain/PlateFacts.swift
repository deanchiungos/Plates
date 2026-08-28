import Foundation

/// Road-trip trivia, several lines per region, loaded from `PlateFacts.json`.
///
/// The content lives in JSON rather than in a Swift literal so it can be edited
/// with ordinary tools — a text editor, a script, a spreadsheet via
/// `tools/facts.py` — without touching code or understanding Swift escaping. This
/// file is only the reader.
///
/// **To add or change a fact, edit `Plates/Resources/PlateFacts.json`.** Keys are
/// `Plate.code`; each value is an array of `{ text, source }`. Adding, deleting and
/// reordering are all safe — `FactBook` tracks what has been read by content, not
/// by position.
///
/// THE EDITORIAL BAR, and it is a bar rather than a style note. A fact earns its
/// place only if it changes what the reader *notices from now on*. Learning that
/// California's plates are stamped by inmates at Folsom rewrites an object seen a
/// hundred times a day; learning that Alabama's first digit is the county rank by
/// 1941 population hands over a decoder usable at the next red light. Both stick.
///
/// What does not: a thing exists, it is large or old, here is the year it opened.
/// An earlier version of this comment invited "roads, bridges, car history and
/// landmarks", and the corpus duly filled with bridge opening dates until 59% of it
/// was not about plates and only 6% was worth reading aloud. Subject matter was
/// never the problem — anything about the region qualifies — so the invitation is
/// withdrawn and replaced with the test above.
///
/// Mechanically: one sentence, at most 120 characters, dry and specific, no
/// exclamation marks, aimed at a kid reading it aloud in a back seat. Every fact
/// carries a `source` it was actually checked against; `tools/facts.py check`
/// enforces the length and refuses an import that drops one.
///
/// `FactBook` decides which one you actually see, and remembers the ones already read.
enum PlateFacts {

    /// One fact and where it was checked. The source is never shown to a reader —
    /// it exists so a fact someone disputes can be re-checked instead of argued
    /// about, and so a bad one can be traced to whatever produced it.
    /// `tools/facts.py` refuses to import a fact without a source.
    private struct Entry: Decodable {
        let text: String
        let source: String
    }

    private static let entries: [String: [Entry]] = load()

    /// Keyed by `Plate.code`. Empty only if the bundled JSON is missing or broken,
    /// which in a debug build stops the app instead.
    static let byCode: [String: [String]] = entries.mapValues { $0.map(\.text) }

    // A `sourceByFact` index used to sit here, keyed by a fact's own words, with a
    // note saying nothing read it yet. Nothing ever did. Provenance has not gone
    // anywhere — every entry still carries its `source`, which is where it belongs —
    // so anything that wants to show it can ask the fact rather than a second table
    // that has to be kept in step with the first.

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

    /// Facts whose spelling changed but whose sentence did not.
    ///
    /// "Rewording one makes it unread again" is the right rule and these are the
    /// exception that proves it: four Canadian facts had `licence` normalised to
    /// `license` to match the spelling used everywhere else in the app. Nothing was
    /// said differently, so telling somebody they had not read a sentence they
    /// plainly had would be the reading that is wrong.
    ///
    /// Only respellings belong here. A fact that was genuinely rewritten is a
    /// different fact and re-locks on purpose; a fact that was replaced outright is
    /// simply gone, and the id stored against it falls out of `live` on its own.
    ///
    /// Old id to new id. Append-only — an id absent from the table is already
    /// current, so reading through it is safe for every fact including future ones.
    private static let aliases: [Int: Int] = [
        4_520_807_808_077_570_484: 6_617_142_944_412_410_980,    // ON
        7_601_569_965_746_654_469: 3_295_329_996_944_884_117,    // NS
        1_862_550_220_119_624_026: -6_872_094_558_759_850_582,   // NL
        3_090_486_213_346_438_680: 2_333_505_581_130_656_040,    // YT
    ]

    /// What a stored id means today.
    ///
    /// Everything that reads the fact ledger goes through this, so a respelling
    /// costs one line in `aliases` rather than a migration pass over `UserDefaults`.
    static func canonical(_ id: Int) -> Int { aliases[id] ?? id }

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
    private static func load() -> [String: [Entry]] {
        guard let url = Bundle.main.url(forResource: "PlateFacts", withExtension: "json") else {
            #if DEBUG
            print("[PlateFacts] PlateFacts.json is not in the bundle — no trivia will "
                  + "show. Put it back at Plates/Resources/PlateFacts.json.")
            #endif
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: [Entry]].self, from: data)
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
    private static func audit(_ facts: [String: [Entry]]) {
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
            if Set(lines.map(\.text)).count != lines.count {
                print("[PlateFacts] \(code) repeats a fact")
            }
            for line in lines where line.text.count > 120 {
                print("[PlateFacts] \(code) is \(line.text.count) chars, over the 120 guide: \(line.text)")
            }
        }
    }
    #endif
}
