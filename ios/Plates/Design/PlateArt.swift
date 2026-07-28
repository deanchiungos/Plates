import SwiftUI

// ORIGINAL ARTWORK — NOT REPRODUCTIONS.
//
// US state plate designs are presumed copyrighted: state works are not public
// domain the way federal works are, and Wikimedia Commons has deleted modern
// plate images on exactly those grounds. Some designs are not even owned by the
// state (California's Arts plate is copyright Wayne Thiebaud).
//
// So nothing here traces or copies a real plate. Each style is a palette and a
// simple original shape that evokes the place — which is also the only thing
// that survives at 84x50 points, where real plate artwork turns to mud.
//
// Deliberately omitted: New Mexico's Zia sun. It is a sacred symbol of Zia
// Pueblo and its use is actively disputed — a separate problem from copyright,
// and one that redrawing it does not solve.

enum Motif {
    case mountains       // ranges and ridgelines
    case star            // lone stars, tri-stars
    case sunDisc         // desert and sunshine states
    case rainbow         // Hawaii
    case scriptBar       // stands in for a script wordmark
    case skyline         // cities
    case wave            // coastal
    case pine            // forest
    case wheat           // plains
    case maple           // Canada
    case horizon         // generic two-tone split, the default when nothing fits
}

struct PlateStyle {
    var background: [Color]
    var ink: Color
    var accent: Color?
    var motif: Motif?

    // kept for the DEBUG contrast audit — both stops, since ink has to stay
    // legible across the whole gradient, not just the top of it
    var bgHex: UInt32
    var bgHex2: UInt32
    var inkHex: UInt32

    /// One line per plate. Terse on purpose — 65 of these is a table, not 65
    /// hand-built views.
    init(_ bg: UInt32, _ bg2: UInt32? = nil,
         ink: UInt32, accent: UInt32? = nil, _ motif: Motif? = nil) {
        self.background = [Color(hex: bg), Color(hex: bg2 ?? bg)]
        self.ink = Color(hex: ink)
        self.accent = accent.map { Color(hex: $0) }
        self.motif = motif
        self.bgHex = bg
        self.bgHex2 = bg2 ?? bg
        self.inkHex = ink
    }

    /// Anything not yet styled falls back to route blue, so the grid stays
    /// coherent while the catalog is filled in.
    static let fallback = PlateStyle(0x12395E, ink: 0xFFFFFF)

    static func style(for code: String) -> PlateStyle? { catalog[code] }

    // MARK: - The catalog
    //
    // Each entry takes the plate's dominant colours and one evocative shape.
    // Where a real plate is plain white-on-dark, the state's own accent colour
    // does the distinguishing so neighbouring tiles never read as identical.

    static let catalog: [String: PlateStyle] = [

        // ---- states ----
        "AL": .init(0xFFFFFF, 0xEFF3F6, ink: 0x1B3A6B, accent: 0xB3282D, .horizon),
        "AK": .init(0xF6C544, 0xE39F1E, ink: 0x18355F, accent: 0xC8801E, .sunDisc),
        // sunset lifted and the maroon deepened; the original failed at the
        // bottom of the gradient only
        "AZ": .init(0xF6B072, 0xE8834F, ink: 0x4A1214, accent: 0xFBD9A0, .sunDisc),
        "AR": .init(0xFDFDF8, 0xE8EFE6, ink: 0x1F5C3A, accent: 0xB3282D, .mountains),
        "CA": .init(0xFFFFFF, 0xF3F1E8, ink: 0x1A3E7C, accent: 0xC8102E, .scriptBar),
        "CO": .init(0x2F7D4F, 0x1C5334, ink: 0xFFFFFF, accent: 0xBFE3CC, .mountains),
        "CT": .init(0xF7FAFD, 0xE3ECF5, ink: 0x123C6B, accent: 0x7FA8CE, .horizon),
        "DE": .init(0x14315C, 0x0D2440, ink: 0xF2C14E, accent: 0xF2C14E),
        "FL": .init(0xFFFFFF, 0xFFF3E0, ink: 0x1F6F3C, accent: 0xF29F3D, .sunDisc),
        "GA": .init(0xFFFFFF, 0xFBEDE6, ink: 0x1C3F94, accent: 0xE0876A, .horizon),
        "HI": .init(0xFFFFFF, 0xF2F6FA, ink: 0x14539A, accent: nil, .rainbow),
        "ID": .init(0xF6F9FC, 0xDCE9F2, ink: 0x1D4E76, accent: 0x8FB4D6, .mountains),
        "IL": .init(0xFFFFFF, 0xEDF1F6, ink: 0x14305C, accent: 0xB3282D, .skyline),
        "IN": .init(0xFFFFFF, 0xEAF0F7, ink: 0x16386B, accent: 0xE0A33E, .star),
        "IA": .init(0xFCFBF3, 0xEDEBD6, ink: 0x2C5E2E, accent: 0xE0B84B, .wheat),
        "KS": .init(0xFDF6E0, 0xF2E2B0, ink: 0x2F4E86, accent: 0xE0A83E, .wheat),
        "KY": .init(0xF7FAFC, 0xE6EEF5, ink: 0x1B4A82, accent: 0x9FC4E0, .horizon),
        "LA": .init(0xFFFDF5, 0xF2EBD8, ink: 0x1C3F7A, accent: 0xC9A227, .wave),
        "ME": .init(0xFAFDF9, 0xE4EFE2, ink: 0x1F5230, accent: 0xC8801E, .pine),
        "MD": .init(0xFFFFFF, 0xF4EFE2, ink: 0x1F1F1F, accent: 0xC8A02E, .horizon),
        "MA": .init(0xFFFFFF, 0xF3F5F8, ink: 0xB3282D, accent: 0x1B3A6B, .horizon),
        "MI": .init(0xEAF4FB, 0x9FC9E4, ink: 0x14406E, accent: 0xFFFFFF, .wave),
        "MN": .init(0xF2F9FC, 0xCFE4F0, ink: 0x1B5E4A, accent: 0x2E7D8F, .pine),
        "MS": .init(0xFFFFFF, 0xF6EEF2, ink: 0x1C3F6B, accent: 0xC26A8D, .horizon),
        "MO": .init(0xFFFFFF, 0xEDF0F5, ink: 0x1A3A6B, accent: 0xB3282D, .skyline),
        // sky lightened so the navy holds at both ends of the gradient
        "MT": .init(0x9FC9E8, 0xE3F0F9, ink: 0x13294B, accent: 0xFFFFFF, .mountains),
        "NE": .init(0xFDF8E8, 0xEFE2BE, ink: 0x2B4C7E, accent: 0xC8A02E, .wheat),
        "NV": .init(0xE9EDF2, 0xB9C4D1, ink: 0x22384F, accent: 0x7A8899, .mountains),
        "NH": .init(0xF6FAF6, 0xDCE9DC, ink: 0x1F5230, accent: 0x8FB08F, .mountains),
        "NJ": .init(0xF7E7A8, 0xE9D076, ink: 0x2E2A1A, accent: 0x9C8A3E),
        // deeper teal than the real plate: yellow-on-turquoise measures 2.0:1
        "NM": .init(0x14615C, 0x0E4A46, ink: 0xF7D84B, accent: 0xF7D84B),
        "NY": .init(0x143A75, 0x0E2A57, ink: 0xF5A623, accent: 0xF5A623, .skyline),
        "NC": .init(0xFFFFFF, 0xEFF2F7, ink: 0x1B3A8C, accent: 0xB3282D, .horizon),
        "ND": .init(0xF4F8F2, 0xD9E6D2, ink: 0x2B5738, accent: 0xB08A4A, .wheat),
        "OH": .init(0xFFFFFF, 0xFDEFE0, ink: 0x1C3F7A, accent: 0xE07B39, .sunDisc),
        "OK": .init(0xF9FBFD, 0xDCE9F2, ink: 0x1F4E79, accent: 0xC8623E, .wheat),
        "OR": .init(0xF5FAF6, 0xD9EADF, ink: 0x1B5E3A, accent: 0x2E8B57, .pine),
        "PA": .init(0xFFFFFF, 0xEDF1F7, ink: 0x14305C, accent: 0xE0B84B, .horizon),
        "RI": .init(0xFAFCFE, 0xDCEBF5, ink: 0x1B4A82, accent: 0x6FA8DC, .wave),
        "SC": .init(0x1B4A5A, 0x0F323E, ink: 0xF2F7F5, accent: 0x8FCBB8, .pine),
        "SD": .init(0xF7F4EC, 0xE2D9C4, ink: 0x3E4A5A, accent: 0x9A8468, .mountains),
        "TN": .init(0xFFFFFF, 0xEDF2F0, ink: 0x1B5E4A, accent: 0xC8A02E, .star),
        "TX": .init(0xFBFBFC, 0xDDE1E6, ink: 0x22262B, accent: 0x8A9099, .star),
        "UT": .init(0xFDF1E6, 0xE8C4A0, ink: 0x8A3A1E, accent: 0xC8623E, .mountains),
        "VT": .init(0x2E6B47, 0x1C4A30, ink: 0xF7FBF8, accent: 0xA8D8BE, .pine),
        "VA": .init(0xFFFFFF, 0xEDF1F6, ink: 0x1B3A6B, accent: 0x7FA8CE, .horizon),
        "WA": .init(0xF2F8FB, 0xCFE2EE, ink: 0x1B5E4A, accent: 0xFFFFFF, .mountains),
        "WV": .init(0xF7FAFC, 0xE0EAF2, ink: 0x1C3F7A, accent: 0xC8A02E, .mountains),
        "WI": .init(0xFFF8F0, 0xF2DCC4, ink: 0x8A2B2B, accent: 0xC8623E, .wheat),
        "WY": .init(0xF7FAFD, 0xDCE9F2, ink: 0x8A3A1E, accent: 0x2B4C7E, .mountains),

        // ---- bonus ----
        "DC": .init(0xFFFFFF, 0xEDF1F7, ink: 0x1B3A8C, accent: 0xB3282D, .skyline),
        "PR": .init(0xF2FAFB, 0xCFE9EE, ink: 0x1B5E7A, accent: 0xC8283E, .wave),

        // ---- Canada ----
        "ON": .init(0xFFFFFF, 0xEDF2F7, ink: 0x1B4A8C, accent: 0x6FA8DC, .maple),
        "QC": .init(0xFFFFFF, 0xE9EFF7, ink: 0x1B3A8C, accent: 0x4A78C4, .maple),
        "BC": .init(0xF4F9FB, 0xD6E7EF, ink: 0x1B4A6B, accent: 0x2E8B8B, .mountains),
        "AB": .init(0xFFFFFF, 0xF2ECEC, ink: 0x8A2B2B, accent: 0xC8623E, .wheat),
        "MB": .init(0xF7FBF7, 0xDCEADC, ink: 0x1F5230, accent: 0x6FA88A, .maple),
        "SK": .init(0xFDF8E8, 0xEFE2BE, ink: 0x2B6B3E, accent: 0xC8A02E, .wheat),
        "NS": .init(0xF7FAFD, 0xDCE9F5, ink: 0x1B3A8C, accent: 0x6FA8DC, .wave),
        "NB": .init(0xFFFAF2, 0xF2E4D2, ink: 0x8A4A1E, accent: 0xC8801E, .pine),
        "NL": .init(0xF5FAF7, 0xD9EAE0, ink: 0x1B5E4A, accent: 0xB3282D, .wave),
        "PE": .init(0xFDF4F4, 0xF2D9D9, ink: 0x8A2B3E, accent: 0xC8623E, .wave),
        "NT": .init(0xF2F8FC, 0xD2E6F2, ink: 0x1B4A7A, accent: 0x8FB4D6, .mountains),
        "YT": .init(0xFDF6E0, 0xEDD9A8, ink: 0x6B4A1E, accent: 0xC8A02E, .mountains),
        "NU": .init(0xF4FAFC, 0xD6EAF2, ink: 0x1B4A6B, accent: 0x7FB8CE, .horizon)
    ]
}
