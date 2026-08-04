import Foundation

/// Where a plate comes from. Only `.state` counts toward the headline "N/50".
enum PlateRegion: String, Codable, Hashable, CaseIterable {
    case state
    case federal      // District of Columbia
    case territory    // Puerto Rico
    case province     // Canada

    var isBonus: Bool { self != .state }
}

/// A plate is a fact about the world, not user data — it never changes, so it is a
/// plain value in a static catalog rather than a persisted model.
struct Plate: Identifiable, Hashable, Sendable {
    let code: String
    let name: String     // full name, used in detail and accessibility
    let short: String    // tile label — abbreviated where the full name will not fit
    /// National-average rarity, 1 (everywhere) to 10 (almost never).
    ///
    /// Only a fallback now. `PlateRarity` computes rarity against the trip's actual
    /// route; this is what it uses before a route has been pinned. A single number
    /// per plate can only ever describe one vantage point, and these describe the
    /// Northeast — which is why New Jersey scores 1 and Montana 8.
    let points: Int
    let region: PlateRegion

    var id: String { code }
}

extension Plate {
    static let all: [Plate] = states + bonus + provinces

    static let states: [Plate] = [
        .init(code: "AL", name: "Alabama",        short: "Alabama",     points: 4,  region: .state),
        .init(code: "AK", name: "Alaska",         short: "Alaska",      points: 10, region: .state),
        .init(code: "AZ", name: "Arizona",        short: "Arizona",     points: 5,  region: .state),
        .init(code: "AR", name: "Arkansas",       short: "Arkansas",    points: 5,  region: .state),
        .init(code: "CA", name: "California",     short: "California",  points: 2,  region: .state),
        .init(code: "CO", name: "Colorado",       short: "Colorado",    points: 4,  region: .state),
        .init(code: "CT", name: "Connecticut",    short: "Connecticut", points: 2,  region: .state),
        .init(code: "DE", name: "Delaware",       short: "Delaware",    points: 6,  region: .state),
        .init(code: "FL", name: "Florida",        short: "Florida",     points: 2,  region: .state),
        .init(code: "GA", name: "Georgia",        short: "Georgia",     points: 3,  region: .state),
        .init(code: "HI", name: "Hawaii",         short: "Hawaii",      points: 10, region: .state),
        .init(code: "ID", name: "Idaho",          short: "Idaho",       points: 8,  region: .state),
        .init(code: "IL", name: "Illinois",       short: "Illinois",    points: 3,  region: .state),
        .init(code: "IN", name: "Indiana",        short: "Indiana",     points: 4,  region: .state),
        .init(code: "IA", name: "Iowa",           short: "Iowa",        points: 6,  region: .state),
        .init(code: "KS", name: "Kansas",         short: "Kansas",      points: 7,  region: .state),
        .init(code: "KY", name: "Kentucky",       short: "Kentucky",    points: 5,  region: .state),
        .init(code: "LA", name: "Louisiana",      short: "Louisiana",   points: 5,  region: .state),
        .init(code: "ME", name: "Maine",          short: "Maine",       points: 6,  region: .state),
        .init(code: "MD", name: "Maryland",       short: "Maryland",    points: 3,  region: .state),
        .init(code: "MA", name: "Massachusetts",  short: "Mass.",       points: 2,  region: .state),
        .init(code: "MI", name: "Michigan",       short: "Michigan",    points: 4,  region: .state),
        .init(code: "MN", name: "Minnesota",      short: "Minnesota",   points: 5,  region: .state),
        .init(code: "MS", name: "Mississippi",    short: "Miss.",       points: 6,  region: .state),
        .init(code: "MO", name: "Missouri",       short: "Missouri",    points: 5,  region: .state),
        .init(code: "MT", name: "Montana",        short: "Montana",     points: 8,  region: .state),
        .init(code: "NE", name: "Nebraska",       short: "Nebraska",    points: 8,  region: .state),
        .init(code: "NV", name: "Nevada",         short: "Nevada",      points: 6,  region: .state),
        .init(code: "NH", name: "New Hampshire",  short: "N.H.",        points: 5,  region: .state),
        .init(code: "NJ", name: "New Jersey",     short: "New Jersey",  points: 1,  region: .state),
        .init(code: "NM", name: "New Mexico",     short: "New Mexico",  points: 7,  region: .state),
        .init(code: "NY", name: "New York",       short: "New York",    points: 1,  region: .state),
        .init(code: "NC", name: "North Carolina", short: "N. Car.",     points: 3,  region: .state),
        .init(code: "ND", name: "North Dakota",   short: "N. Dak.",     points: 9,  region: .state),
        .init(code: "OH", name: "Ohio",           short: "Ohio",        points: 3,  region: .state),
        .init(code: "OK", name: "Oklahoma",       short: "Oklahoma",    points: 6,  region: .state),
        .init(code: "OR", name: "Oregon",         short: "Oregon",      points: 6,  region: .state),
        .init(code: "PA", name: "Pennsylvania",   short: "Penn.",       points: 2,  region: .state),
        .init(code: "RI", name: "Rhode Island",   short: "R.I.",        points: 6,  region: .state),
        .init(code: "SC", name: "South Carolina", short: "S. Car.",     points: 4,  region: .state),
        .init(code: "SD", name: "South Dakota",   short: "S. Dak.",     points: 9,  region: .state),
        .init(code: "TN", name: "Tennessee",      short: "Tennessee",   points: 4,  region: .state),
        .init(code: "TX", name: "Texas",          short: "Texas",       points: 2,  region: .state),
        .init(code: "UT", name: "Utah",           short: "Utah",        points: 6,  region: .state),
        .init(code: "VT", name: "Vermont",        short: "Vermont",     points: 7,  region: .state),
        .init(code: "VA", name: "Virginia",       short: "Virginia",    points: 3,  region: .state),
        .init(code: "WA", name: "Washington",     short: "Washington",  points: 5,  region: .state),
        .init(code: "WV", name: "West Virginia",  short: "W. Va.",      points: 7,  region: .state),
        .init(code: "WI", name: "Wisconsin",      short: "Wisconsin",   points: 5,  region: .state),
        .init(code: "WY", name: "Wyoming",        short: "Wyoming",     points: 9,  region: .state)
    ]

    static let bonus: [Plate] = [
        .init(code: "DC", name: "District of Columbia", short: "D.C.",        points: 6, region: .federal),
        .init(code: "PR", name: "Puerto Rico",          short: "Puerto Rico", points: 9, region: .territory)
    ]

    static let provinces: [Plate] = [
        .init(code: "ON", name: "Ontario",                   short: "Ontario",   points: 6,  region: .province),
        .init(code: "QC", name: "Quebec",                    short: "Quebec",    points: 7,  region: .province),
        .init(code: "BC", name: "British Columbia",          short: "B.C.",      points: 8,  region: .province),
        .init(code: "AB", name: "Alberta",                   short: "Alberta",   points: 9,  region: .province),
        .init(code: "MB", name: "Manitoba",                  short: "Manitoba",  points: 9,  region: .province),
        .init(code: "SK", name: "Saskatchewan",              short: "Sask.",     points: 9,  region: .province),
        .init(code: "NS", name: "Nova Scotia",               short: "N.S.",      points: 9,  region: .province),
        .init(code: "NB", name: "New Brunswick",             short: "N.B.",      points: 9,  region: .province),
        .init(code: "NL", name: "Newfoundland and Labrador", short: "Nfld.",     points: 10, region: .province),
        .init(code: "PE", name: "Prince Edward Island",      short: "P.E.I.",    points: 10, region: .province),
        .init(code: "NT", name: "Northwest Territories",     short: "N.W.T.",    points: 10, region: .province),
        .init(code: "YT", name: "Yukon",                     short: "Yukon",     points: 10, region: .province),
        .init(code: "NU", name: "Nunavut",                   short: "Nunavut",   points: 10, region: .province)
    ]

    private static let index: [String: Plate] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    static func plate(for code: String) -> Plate? { index[code] }

    /// The denominator behind "N/50". Derived, so it can never drift from the catalog.
    static let stateTotal = states.count
}
