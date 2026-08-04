import Foundation
import SwiftUI
import UIKit

/// "I saw a green one with a lighthouse on it. What was that?"
///
/// 268 street-legal designs — every jurisdiction's current plate plus the
/// historical ones still on the road — each with a photograph and a written
/// description of what it looks like. `ios/tools/plate_lookup_build.py` turns
/// those descriptions into a sparse TF-IDF vector per design; this searches them
/// by cosine similarity against a vector built the same way from what you typed.
///
/// Scoring is BM25, and that is a measured choice rather than a taste.
/// Against a labelled set of queries with known right answers, on this corpus:
///
///   BM25 over raw term counts .................. 100% top-1
///   TF-IDF cosine .............................. 88%
///   NLEmbedding.sentenceEmbedding (chunked) .... far worse — "covered bridge"
///                                                returned Colorado, "cactus"
///                                                returned Georgia
///   NLContextualEmbedding, mean-pooled ......... worse still; one long
///                                                description dominated nearly
///                                                every query
///
/// Apple's on-device embeddings are the right tool for paraphrase over prose.
/// They are the wrong tool here because these queries are mostly rare concrete
/// nouns — "palmetto", "vacationland", "peach" — where an exact term carries
/// almost all the signal, and mean-pooling a paragraph averages that signal
/// away. Contextual embeddings also have no sentence-similarity training
/// objective, so raw cosines between them sit in a narrow, poorly separated band.
///
/// The honest limit is not the ranking, it is the corpus: nothing here can find
/// a moose, because no description mentions one. `unknownTerms` exists so the
/// interface can say that out loud instead of showing an empty list.
enum PlateLookup {

    struct Design: Identifiable, Hashable {
        let key: String
        let code: String
        let jurisdiction: String
        let years: String
        let caption: String
        let base: String
        let ink: String
        let graphics: String
        let topLegend: String
        let bottomLegend: String
        /// Weighted term counts, not a normalised vector — BM25 does its own
        /// length normalisation and needs the raw numbers.
        let terms: [String: Double]
        let length: Double
        /// Colour coverage measured from the photograph by plate_colours.py —
        /// what fraction of the plate each colour actually occupies.
        let colours: [String: Double]
        /// The design on the road today, per the curated pick in
        /// research/plate-primary.csv.
        let isCurrent: Bool
        /// Who took the photograph and under what terms. Most of these came
        /// from Wikimedia Commons under CC BY or CC BY-SA, which require the
        /// photographer to be named wherever the picture appears, so this is a
        /// condition of shipping the image rather than a nicety.
        let credit: String
        let licence: String

        var id: String { key }

        /// The year this design started, as a number. See `PlateDates`.
        var startYear: Int { PlateDates.startYear(years) }

        /// One line naming the photographer and the licence, or nothing when a
        /// public-domain image has neither.
        var attribution: String? {
            let parts = [credit, licence].filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " · ")
        }

        /// The legends as they are printed, which is often the fastest way to
        /// recognise a plate you half-remember.
        var legends: [String] {
            [topLegend, bottomLegend].filter { !$0.isEmpty }
        }
    }

    struct Match: Identifiable {
        let design: Design
        let score: Double
        var id: String { design.key }
    }

    /// Every matching design for one jurisdiction, as a single result.
    ///
    /// A state keeps a look for decades and reissues it, so "orange and black"
    /// legitimately matches five Newfoundland designs in a row and buries the
    /// forty other jurisdictions underneath them. Collapsing to one row per
    /// place turned 225 results into 60.
    struct Group: Identifiable {
        let code: String
        let jurisdiction: String
        /// The variant shown on the row. Chosen by `pick(from:)`, which leans
        /// modern: a state keeps a look for decades and reissues it, and the
        /// one you are most likely to have just driven past is the newest.
        let best: Design
        let variants: [Design]
        let score: Double

        var id: String { code }
        var isSingle: Bool { variants.count <= 1 }
    }

    /// How far below the top score a design may sit and still be shown instead
    /// of it, on the strength of being newer.
    ///
    /// A jurisdiction's designs are near-identical to a search — Ohio's 2009 and
    /// 2021 plates both talk about sunrises, barns and biplanes — so which one
    /// wins the row comes down to caption wording rather than to anything the
    /// person typed. Within this band the tie is broken by age, because someone
    /// describing a plate they saw through a windscreen this afternoon saw a
    /// plate that is on the road this afternoon. Below the band the older design
    /// genuinely matched better and keeps the row: describe a 1970s plate and
    /// you should get the 1970s plate.
    private static let modernBand = 0.82

    /// Search, folded to one row per jurisdiction, best first.
    static func grouped(_ query: String, limit: Int = 60) -> [Group] {
        var byCode: [String: [Match]] = [:]
        for match in search(query, limit: 400) {
            byCode[match.design.code, default: []].append(match)
        }
        return byCode.values.compactMap { matches -> Group? in
            guard let best = pick(from: matches) else { return nil }
            return Group(
                code: best.design.code,
                jurisdiction: best.design.jurisdiction,
                best: best.design,
                variants: matches.map(\.design).sorted(by: newestFirst),
                score: matches.map(\.score).max() ?? best.score
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    /// The design to put on a jurisdiction's row: the newest of those that
    /// scored close enough to the best to be a real candidate.
    private static func pick(from matches: [Match]) -> Match? {
        guard let top = matches.map(\.score).max(), top > 0 else {
            return matches.first
        }
        return matches
            .filter { $0.score >= top * modernBand }
            .sorted { newestFirst($0.design, $1.design) }
            .first ?? matches.first
    }

    /// Current design first, then by the year it started, newest down to oldest.
    static func newestFirst(_ a: Design, _ b: Design) -> Bool {
        if a.isCurrent != b.isCurrent { return a.isCurrent }
        return a.startYear > b.startYear
    }

    // MARK: - Index

    private struct Payload: Decodable {
        let idf: [String: Double]
        let synonyms: [String: [String]]
        let stop: [String]
        let colourIdf: [String: Double]
        let colourQuery: [String: [String: Double]]
        let current: [String: [String]]
        let designs: [Raw]

        struct Raw: Decodable {
            let k: String, c: String, j: String, y: String
            let cap: String, base: String, ink: String, gfx: String
            let top: String, bot: String
            let v: [String: Double]
            let dl: Double
            let cur: Bool
            let col: [String: Double]
            let cred: String
            let lic: String
        }
    }

    private static let payload: Payload? = {
        guard let url = Bundle.main.url(forResource: "PlateLookup", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("PlateLookup.json missing from the bundle")
            return nil
        }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }()

    static let designs: [Design] = {
        (payload?.designs ?? []).map {
            Design(key: $0.k, code: $0.c, jurisdiction: $0.j, years: $0.y,
                   caption: $0.cap, base: $0.base, ink: $0.ink, graphics: $0.gfx,
                   topLegend: $0.top, bottomLegend: $0.bot,
                   terms: $0.v, length: $0.dl, colours: $0.col,
                   isCurrent: $0.cur, credit: $0.cred, licence: $0.lic)
        }
    }()

    /// Mean document length, for BM25's length normalisation.
    private static let averageLength: Double = {
        guard !designs.isEmpty else { return 1 }
        return designs.reduce(0) { $0 + $1.length } / Double(designs.count)
    }()

    private static var idf: [String: Double] { payload?.idf ?? [:] }
    private static var synonyms: [String: [String]] { payload?.synonyms ?? [:] }

    /// Shipped by the builder so the two stay in step.
    private static let stopWords: Set<String> = Set(payload?.stop ?? [])

    /// Terms belonging to each jurisdiction's *current* design. The Game screen's
    /// search bar uses this so "cactus" finds Arizona, without pulling the whole
    /// 268-design index into a path that runs on every keystroke.
    static let currentTerms: [String: Set<String>] = {
        (payload?.current ?? [:]).mapValues(Set.init)
    }()

    // MARK: - Tokenising
    //
    // Mirrors `tokenize` and `stem` in plate_lookup_build.py exactly. If the two
    // drift, the query lands in a different space from the documents and every
    // score quietly goes wrong, which is why both are this crude.

    static func stem(_ word: String) -> String {
        var w = word
        if w.count > 5, w.hasSuffix("ing") { w.removeLast(3); return w }
        if w.count > 5, w.hasSuffix("ed") { w.removeLast(2); return w }
        if w.count > 4, w.hasSuffix("es") { w.removeLast(2); return w }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { w.removeLast(); return w }
        return w
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
            .map(stem)
    }

    // MARK: - Search

    /// Standard BM25 constants. k1 controls how fast repeated terms saturate,
    /// b how hard length is normalised; these are the tuned values from the
    /// offline evaluation, not the textbook defaults.
    private static let k1 = 1.4
    private static let b = 0.55
    /// How much measured colour counts against the text score. Tuned on the
    /// query that prompted it: at 0 New York's amber plate sat 18th of 60 for
    /// "orange and black"; at 10 it is 6th, behind five plates that genuinely
    /// are more orange and black than it is.
    private static let colourWeight = 10.0

    private static var colourIdf: [String: Double] { payload?.colourIdf ?? [:] }
    private static var colourQuery: [String: [String: Double]] {
        payload?.colourQuery ?? [:]
    }

    /// Every jurisdiction code, so a two-letter query can be recognised.
    private static let codes: Set<String> = Set(designs.map(\.code))

    /// Levenshtein distance within `max`, bailing out as soon as it cannot be.
    private static func within(_ a: String, _ b: String, _ max: Int) -> Bool {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > max { return false }
        var prev = Array(0...y.count)
        for i in 1...x.count {
            var cur = [i]
            for j in 1...y.count {
                cur.append(Swift.min(prev[j] + 1, cur[j - 1] + 1,
                                     prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)))
            }
            if cur.min()! > max { return false }
            prev = cur
        }
        return prev[y.count] <= max
    }

    /// Vocabulary terms close enough to be what someone meant.
    ///
    /// People misspell, and without this one wrong letter drops the word
    /// entirely — "pensylvania" matched nothing, and "new yok" was worse than
    /// nothing because "yok" vanished and the surviving "new" confidently
    /// returned New Jersey.
    ///
    /// Two constraints keep it from inventing answers. The opening letters must
    /// survive, because typos are transpositions and dropped letters in the
    /// middle of a word, almost never the first character — and short words
    /// need two of them, since one edit in a four-letter word is a quarter of
    /// it, which is how "loon" reached "lion" and put Prince Edward Island's
    /// crest in front of someone looking for a bird.
    private static func nearest(_ term: String) -> [(String, Double)] {
        guard term.count >= 3 else { return [] }
        let keep = term.count < 5 ? 2 : 1
        let head = String(term.prefix(keep))
        let near = idf.keys.filter { $0.hasPrefix(head) }

        var hits = near.filter { $0.hasPrefix(term) || term.hasPrefix($0) }
            .map { ($0, 0.75) }
        if hits.isEmpty {
            hits = near.filter { within(term, $0, 1) }.map { ($0, 0.70) }
        }
        // Two edits only on genuinely long words. At seven characters it matched
        // "shuttle" to "subtle", which is not a misspelling, it is another word.
        if hits.isEmpty, term.count >= 9 {
            hits = near.filter { within(term, $0, 2) }.map { ($0, 0.45) }
        }
        return hits.sorted { ($0.1, $1.0.count) > ($1.1, $0.0.count) }.prefix(3).map { $0 }
    }

    /// Query terms that appear nowhere in the corpus.
    ///
    /// Worth surfacing rather than swallowing: "loon" and "moose" return
    /// nothing because no plate description contains those words, which is a
    /// fact about the descriptions, not a failed search. Showing an empty list
    /// makes it look like the app is broken.
    static func unknownTerms(in query: String) -> [String] {
        var seen = Set<String>()
        return query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
            .filter { word in
                // Stopwords are not "missing" — nobody wants to be told that no
                // plate description mentions the word "the".
                guard word.count >= 3, !stopWords.contains(word) else { return false }
                let t = stem(word)
                guard idf[t] == nil, seen.insert(t).inserted else { return false }
                // Synonyms can still reach the index even when the typed word cannot.
                return (synonyms[t] ?? []).allSatisfy { idf[$0] == nil }
            }
    }

    /// BM25 over the weighted term counts, best first.
    ///
    /// Synonyms are expanded on the query rather than baked into the index: a
    /// design does not become more about mountains because someone might call
    /// its ridgeline that. Expanded terms are weighted below typed ones so an
    /// exact word always outranks a guess at what you meant.
    static func search(_ query: String, limit: Int = 40) -> [Match] {
        // Codes first, and the empty check comes after. A two-letter code is the
        // most precise thing anyone can type, and the tokeniser's three-character
        // floor throws it away — so guarding on "no tokens" before looking for
        // one meant "ny" returned nothing.
        let typedCodes = Set(query.split(whereSeparator: { !$0.isLetter })
            .map { $0.uppercased() }
            .filter { codes.contains($0) })

        let typed = tokenize(query)
        guard !typed.isEmpty || !typedCodes.isEmpty else { return [] }

        var weights: [String: Double] = [:]
        for term in typed {
            // Synonyms fire whether or not the typed word is itself indexed.
            // Gating them on "is it in the vocabulary" meant "amber" could never
            // reach "gold" — the one case a colour bridge exists for. Fuzzy
            // matching is the last resort, only when nothing else lands.
            var hit = false
            if idf[term] != nil {
                weights[term, default: 0] += 1
                hit = true
            }
            for syn in synonyms[term] ?? [] where idf[syn] != nil {
                weights[syn] = Swift.max(weights[syn] ?? 0, 0.55)
                hit = true
            }
            if !hit {
                for (candidate, w) in nearest(term) {
                    weights[candidate] = Swift.max(weights[candidate] ?? 0, w)
                }
            }
        }

        var q: [(term: String, weight: Double)] = []
        for (term, w) in weights {
            if let i = idf[term] { q.append((term, w * i)) }
        }
        guard !q.isEmpty || !typedCodes.isEmpty else { return [] }

        // Colour, measured off the photograph rather than read out of a caption.
        // Scored by how much of the plate it covers, because area is what
        // survives a car going past — see plate_colours.py.
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        var wantedColours: [String: Double] = [:]
        for word in words {
            for (name, weight) in colourQuery[word] ?? [:] {
                wantedColours[name] = Swift.max(wantedColours[name] ?? 0, weight)
            }
        }
        // How much colour is allowed to matter depends on what else was typed.
        // "orange and black" is all a person has, so colour decides it. "green
        // plate with a lighthouse" names a thing, and a lighthouse is far more
        // identifying than green — weighing them equally put Colorado above
        // Mississippi and cost ten points of top-1 accuracy.
        let contentIdf = words
            .filter { colourQuery[$0] == nil }
            .compactMap { tokenize($0).first.flatMap { idf[$0] } }
            .max() ?? 0
        let colourK = colourWeight / (1 + 1.6 * contentIdf)

        let avg = averageLength
        var out: [Match] = []
        out.reserveCapacity(designs.count)
        for design in designs {
            var score = 0.0
            // Iterate the query, not the document: a handful of terms against a
            // dictionary hit, rather than 48 lookups per design.
            for (term, weight) in q {
                guard let f = design.terms[term] else { continue }
                score += weight * (f * (k1 + 1))
                    / (f + k1 * (1 - b + b * design.length / avg))
            }
            for (name, weight) in wantedColours {
                if let cover = design.colours[name], cover > 0 {
                    score += colourK * weight * cover * (colourIdf[name] ?? 1)
                }
            }
            // An explicit code outranks anything the words could say.
            if typedCodes.contains(design.code) { score += 10 }
            if score > 0 { out.append(Match(design: design, score: score)) }
        }
        out.sort { $0.score > $1.score }
        return Array(out.prefix(limit))
    }

    /// Everything for one jurisdiction, current design first and then newest
    /// down to oldest — what the detail view shows beside the design you opened.
    static func designs(for code: String) -> [Design] {
        designs.filter { $0.code == code }.sorted(by: newestFirst)
    }

    // MARK: - Photos

    private static let cache = NSCache<NSString, UIImage>()

    /// The plate's photograph. Files land either in a `PlateShots` subdirectory
    /// or flattened into the bundle root depending on how Xcode copies the
    /// resource folder, so try both rather than depending on one.
    static func photo(_ key: String) -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let url = Bundle.main.url(forResource: key, withExtension: "jpg",
                                  subdirectory: "PlateShots")
            ?? Bundle.main.url(forResource: key, withExtension: "jpg")
        guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}
