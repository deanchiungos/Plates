import Foundation

/// What the Drive screen draws.
///
/// A view preference and nothing more. It never reaches scoring, counts, rarity or
/// the map: hiding a plate you have already found does not un-find it, and turning
/// Canada off does not delete the provinces you collected. Every "N / M found" line
/// on the screen keeps reporting the real total, because the denominator is a fact
/// about the catalog and not about what you are looking at right now.
///
/// Two knobs, from two different review asks:
///
///   * `hideFound` — *"would like the option to view only the states that haven't
///     been claimed"*, and *"I wish we could have a states left list and not just a
///     state found list"*.
///   * `sets` — *"select any or all of 4 sets … then if someone wanted to hunt both
///     US and Canada, or US and territories, or all they could decide exactly how to
///     play"*. Note the asks point both ways: two reviewers wanted territories out of
///     their hunt, one wanted them in. That is the argument for a filter over a fixed
///     list.
struct PlateFilter: Equatable, Sendable {
    static let key = "plateFilter"

    var hideFound = false
    var sets: Set<PlateRegion> = Set(PlateRegion.allCases)

    /// Whether the filter is doing anything, which is what decides if the chip
    /// announces itself. A filter you cannot tell is on is a bug report waiting to
    /// happen — "where did Wyoming go?"
    var isActive: Bool { hideFound || sets != Set(PlateRegion.allCases) }

    func includes(_ region: PlateRegion) -> Bool { sets.contains(region) }

    /// Turning off the last set would leave nothing to hunt and no obvious way back,
    /// so the final one sticks. Everything else toggles freely.
    mutating func toggle(_ region: PlateRegion) {
        if sets.contains(region) {
            guard sets.count > 1 else { return }
            sets.remove(region)
        } else {
            sets.insert(region)
        }
    }

    /// The plates to draw from one section.
    ///
    /// `isFound` is injected rather than taking a collection, so this stays a pure
    /// function of the filter and can be reasoned about on its own.
    func visible(_ plates: [Plate], isFound: (Plate) -> Bool) -> [Plate] {
        plates.filter { plate in
            guard sets.contains(plate.region) else { return false }
            return !(hideFound && isFound(plate))
        }
    }

    /// Search wins over the filter, always.
    ///
    /// Typing "Yukon" and getting nothing because Canada is switched off — or typing
    /// a state you already found while "only what's left" is on — would make the
    /// search box lie about the catalog. So while a search is live the filter stands
    /// down entirely and the hidden sections come back. The filter shapes browsing;
    /// search answers questions.
    func standingDown(while searching: Bool) -> PlateFilter {
        searching ? PlateFilter() : self
    }
}

// MARK: - Naming the sets

extension PlateRegion {
    /// Display names for the filter. `PlateRegion`'s own cases are modelling terms
    /// (`.federal` is one plate, D.C.) and would read as jargon on a chip.
    var filterLabel: String {
        switch self {
        case .state:     return "States"
        case .federal:   return "D.C."
        case .territory: return "Territories"
        case .province:  return "Canada"
        }
    }

    /// Written out rather than counted from `plates`, so the subtitle stays right if
    /// a plate is ever added to a set.
    var filterDetail: String {
        let n = Self.byRegion[self]?.count ?? 0
        switch self {
        case .state:     return "All 50"
        case .federal:   return "District of Columbia"
        case .territory: return "Puerto Rico"
        case .province:  return "\(n) provinces and territories"
        }
    }

    static let byRegion: [PlateRegion: [Plate]] =
        Dictionary(grouping: Plate.all, by: \.region)

    var plates: [Plate] { Self.byRegion[self] ?? [] }
}

// MARK: - Persistence

/// Stored as one string so the whole filter is a single `@AppStorage` property and
/// cannot half-save. Hand-rolled rather than JSON because the format wants to stay
/// readable in `defaults read` while debugging: `"1|state,province"`.
extension PlateFilter: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1,
                                   omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let decoded = Set(parts[1].split(separator: ",").compactMap {
            PlateRegion(rawValue: String($0))
        })

        self.hideFound = parts[0] == "1"
        // An empty or unreadable set would render a blank screen with no way out.
        self.sets = decoded.isEmpty ? Set(PlateRegion.allCases) : decoded
    }

    var rawValue: String {
        // Sorted so the stored string is stable — an unordered Set would otherwise
        // rewrite the preference on every launch.
        let codes = sets.map(\.rawValue).sorted().joined(separator: ",")
        return "\(hideFound ? "1" : "0")|\(codes)"
    }
}
