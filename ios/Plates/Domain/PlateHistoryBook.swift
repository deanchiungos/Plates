import Foundation

/// Every plate design the app has a photograph of, by jurisdiction.
///
/// 3,113 designs across all 65 jurisdictions, 1903 to 2026, scraped from Wikipedia's
/// per-jurisdiction articles by `ios/tools/wiki_plates.py` and reduced to what a
/// screen needs by `plate_history_build.py`.
///
/// Only designs with a picture. The research CSV deliberately keeps the ones without,
/// because that is how the gaps stay countable, but on a screen for looking at plates
/// a row with nothing to look at is a gap someone scrolls past.
///
/// **The pictures are remote.** The lookup screen's 268 street-legal photographs come
/// to 6.4 MB bundled; these 3,113 would be about 75 MB, which is not a reasonable
/// thing to add to a game. So this is the one screen in the app that wants a network.
/// Nothing you do while actually driving depends on it.
enum PlateHistoryBook {

    struct Design: Identifiable, Hashable {
        let id = UUID()
        let dates: String
        let year: Int
        let isCurrent: Bool
        let note: String
        let url: URL
        let licence: String
        let credit: String
        /// The picture belongs to a neighbouring row that Wikipedia says is the same
        /// design. Worth saying on the card rather than implying this photograph is
        /// of this row.
        let isShared: Bool
    }

    /// Loaded once, on first use, and held. A megabyte of JSON parsed on the main
    /// thread the first time someone opens the screen is a visible stutter, so the
    /// call site does it in a task.
    private static var cache: [String: [Design]]?

    static func designs(for code: String) -> [Design] {
        load()[code] ?? []
    }

    /// Jurisdictions that have at least one photographed design, in the order the
    /// rest of the app lists plates.
    static var jurisdictions: [Plate] {
        let book = load()
        return Plate.all.filter { !(book[$0.code]?.isEmpty ?? true) }
    }

    @discardableResult
    static func load() -> [String: [Design]] {
        if let cache { return cache }

        guard let url = Bundle.main.url(forResource: "PlateHistory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]]
        else {
            cache = [:]
            return [:]
        }

        var out: [String: [Design]] = [:]
        for (code, entries) in raw {
            out[code] = entries.compactMap { e in
                guard let link = e["url"] as? String, let url = URL(string: link) else {
                    return nil
                }
                return Design(dates: e["dates"] as? String ?? "",
                              year: e["year"] as? Int ?? 0,
                              isCurrent: e["current"] as? Bool ?? false,
                              note: e["note"] as? String ?? "",
                              url: url,
                              licence: e["licence"] as? String ?? "",
                              credit: e["credit"] as? String ?? "",
                              isShared: e["shared"] as? Bool ?? false)
            }
        }
        cache = out
        return out
    }
}
