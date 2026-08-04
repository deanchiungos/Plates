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
//
// The palette below is grounded, not guessed: `research/plate-primary.csv` has
// one real, described photograph per jurisdiction (plate_vision.py), and every
// entry here except WY and YT — no free photo exists for either — was checked
// against it and adjusted where the two disagreed. Colours were then pushed
// through a WCAG-AA check against both gradient stops; a few (marked below)
// had to be pulled off the literal photographed hue to stay legible, the same
// tradeoff CO/MT/AZ already made before any of this data existed.

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
    case fleurDeLis       // Quebec — was sharing .maple with Ontario, read as identical
    case stateOutline     // a small place-mark separator (New Jersey, Missouri)
    case arch             // Utah's sandstone arch
    case cactus           // Arizona's saguaro
    case bloom            // a single stylised flower (Alberta's rose, Newfoundland's pitcher plant)
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
        // coastal sunset/lighthouse scene; wave motif for the shoreline
        "AL": .init(0xE0C97A, 0x7FA9C4, ink: 0x1C1C1C, accent: 0xB3282D, .wave),
        // Big Dipper flag, not a sun — kept sunDisc as the closest existing shape
        "AK": .init(0xF6C544, 0xE0A32A, ink: 0x14305C, accent: 0xC8623E, .sunDisc),
        // saguaro + purple mountains desert scene (colours adjusted from the raw photo to clear WCAG AA)
        "AZ": .init(0xBFE0EE, 0xF2D9A0, ink: 0x0E4E4B, accent: 0xE0876A, .cactus),
        // pale blue-to-white gradient, faint diamond watermark
        "AR": .init(0xE8F0F6, 0xFFFFFF, ink: 0x1C1C1C, accent: 0x1F5C3A, .horizon),
        // unchanged — matched already
        "CA": .init(0xFFFFFF, 0xF3F1E8, ink: 0x14305C, accent: 0xB3282D, .scriptBar),
        // was inverted: real plate is white bg / green ink, not green bg / white ink
        "CO": .init(0xFFFFFF, 0xEAF0EC, ink: 0x1B5230, accent: 0x1B5230, .mountains),
        // sky-blue-to-white gradient; small state outline
        "CT": .init(0xBFE0F2, 0xFFFFFF, ink: 0x14305C, accent: 0x6FA8DC, .horizon),
        // unchanged — matched already
        "DE": .init(0x14305C, 0x0E2A57, ink: 0xF2C14E, accent: 0xF2C14E, nil),
        // orange-blossom plate; kept the closest existing warm-state shape
        "FL": .init(0xFFFFFF, 0xE8F2EA, ink: 0x1B5230, accent: 0xD97B3D, .sunDisc),
        // flat grey field, peach graphic; no peach motif exists yet
        "GA": .init(0xEDEDED, 0xE0E0E0, ink: 0x1C1C1C, accent: 0xD97B3D, .horizon),
        // ink was navy, real serial is black
        "HI": .init(0xFFFFFF, 0xF2F6FA, ink: 0x1C1C1C, accent: nil, .rainbow),
        // red/white/blue banded potato-and-mountains plate
        "ID": .init(0xE8A0A0, 0xFFFFFF, ink: 0x1C1C1C, accent: 0x1B7D78, .mountains),
        // was white bg / navy ink: real plate is a blue gradient with a red serial (colours adjusted from the raw photo to clear WCAG AA)
        "IL": .init(0xD9E9F5, 0xEFF6FB, ink: 0x9E1A24, accent: 0x9E1A24, .skyline),
        // covered bridge + pine trees; no bridge motif, pine is the closest fit
        "IN": .init(0xBFE0F2, 0x8FB4D6, ink: 0x14305C, accent: 0xB3282D, .pine),
        // skyline + wind turbine top band, green ground
        "IA": .init(0xBFE0F2, 0xFFFFFF, ink: 0x1C1C1C, accent: 0x1F5C3A, .skyline),
        // unchanged — matched already
        "KS": .init(0xD6E9F5, 0xC2DCEE, ink: 0x1C1C1C, accent: 0xE0B84B, .wheat),
        // white-to-cyan gradient
        "KY": .init(0xFFFFFF, 0xBFE8EE, ink: 0x14305C, accent: 0x6FA8DC, .horizon),
        // pelican on a post; wave is the closest coastal shape available
        "LA": .init(0xFFFFFF, 0xF2ECD8, ink: 0x1C1C1C, accent: 0xE0B84B, .wave),
        // unchanged — matched already
        "ME": .init(0xFFFFFF, 0xF2F2F2, ink: 0x14305C, accent: 0x14305C, .horizon),
        // state-flag ribbon across the lower half; ink was correct, adjusted from navy-black to true black
        "MD": .init(0xFFFFFF, 0xF4EFE2, ink: 0x1C1C1C, accent: 0xE0B84B, .horizon),
        // unchanged — matched already
        "MA": .init(0xFFFFFF, 0xF3F5F8, ink: 0xB3282D, accent: 0x14305C, .horizon),
        // was mostly-blue bg: real plate is white with a wave band across only the bottom third
        "MI": .init(0xFFFFFF, 0xBFE0F2, ink: 0x1B4A8C, accent: 0x1B4A8C, .wave),
        // lakeshore/canoe/pine scene; ink was green, real serial is black
        "MN": .init(0xBFE0F2, 0xFFFFFF, ink: 0x1C1C1C, accent: 0x1B7D78, .pine),
        // unchanged — matched already
        "MS": .init(0xFFFFFF, 0xF6EEF2, ink: 0x14305C, accent: 0xC26A8D, .horizon),
        // state outline + bluebird; was skyline, which doesn't exist on this plate
        "MO": .init(0xFFFFFF, 0xF2F6FA, ink: 0x1B4A8C, accent: 0x1B4A8C, .stateOutline),
        // unchanged shape, ink lightened from navy to the true dark-grey serial
        "MT": .init(0xBFE0F2, 0xFFFFFF, ink: 0x3E3D46, accent: 0xE0B84B, .mountains),
        // silver-grey field with a ghosted watermark; wheat motif from before doesn't match the current design
        "NE": .init(0xE8ECEF, 0xD6DCE2, ink: 0x14305C, accent: 0xE0B84B, .horizon),
        // low-poly mountain range; unchanged shape
        "NV": .init(0xBFE0F2, 0xE0C97A, ink: 0x1C1C1C, accent: 0x1F5C3A, .mountains),
        // unchanged shape — Old Man of the Mountain watermark reads as a mountain motif
        "NH": .init(0xFFFFFF, 0xF2F2F2, ink: 0x1B5230, accent: 0x1B5230, .mountains),
        // background was too saturated/gold — real plate is a pale cream; added the state-outline motif for its actual separator mark
        "NJ": .init(0xF7F3E6, 0xE9DFC4, ink: 0x1C1C1C, accent: 0x1C1C1C, .stateOutline),
        // unchanged — matched already; Zia deliberately omitted, see file header
        "NM": .init(0x14615C, 0x0E4A46, ink: 0xF7D84B, accent: 0xF7D84B, nil),
        // was navy bg / gold ink — that's the retired ~2010-2020 plate; the current Excelsior design is cream with a navy serial and a skyline vignette
        "NY": .init(0xF7F3E6, 0xE8E4DC, ink: 0x14305C, accent: 0x14305C, .skyline),
        // Wright Flyer + beach grass; wave motif for the dune/water linework
        "NC": .init(0xF2EFE6, 0xFFFFFF, ink: 0x1B3A9E, accent: 0xB3282D, .wave),
        // badlands sunset with a bison; mountains is the closest existing shape
        "ND": .init(0xBFE0F2, 0xE0A05A, ink: 0x1C1C1C, accent: 0xC8623E, .mountains),
        // was white bg / navy ink / orange accent: real current plate is flat gold with a red serial (colours adjusted from the raw photo to clear WCAG AA)
        "OH": .init(0xF6C544, 0xE0A32A, ink: 0x7A1015, accent: 0xB3282D, nil),
        // was pale blue / navy: the Sept-2024 design is solid saturated red with a white serial and star device
        "OK": .init(0xB3282D, 0x9E1A24, ink: 0xFFFFFF, accent: 0xFFFFFF, .star),
        // unchanged — matched already
        "OR": .init(0xBFE0F2, 0xFFFFFF, ink: 0x14305C, accent: 0x1F5C3A, .pine),
        // banded blue/white/gold; added state-outline for its corner mark (colours adjusted from the raw photo to clear WCAG AA)
        "PA": .init(0x6FA8DC, 0xE0B84B, ink: 0x14305C, accent: 0x6FA8DC, .stateOutline),
        // unchanged — matched already
        "RI": .init(0xBFE0F2, 0xDCEBF5, ink: 0x14305C, accent: 0x6FA8DC, .wave),
        // was dark-teal bg / near-white ink: real plate is light (blue-to-white gradient) with a black serial — inverted brightness (colours adjusted from the raw photo to clear WCAG AA)
        "SC": .init(0x6FA8DC, 0xFFFFFF, ink: 0x1C1C1C, accent: 0x1B4A8C, .pine),
        // photographic Rushmore scene; mountains is the closest existing shape
        "SD": .init(0xBFE0F2, 0x8A8580, ink: 0x1C1C1C, accent: 0xE0B84B, .mountains),
        // was white bg / green ink: real current plate is solid navy with a white serial and tri-star emblem
        "TN": .init(0x14305C, 0x0E2A57, ink: 0xFFFFFF, accent: 0xFFFFFF, .star),
        // unchanged shape, ink darkened from grey to true black
        "TX": .init(0xFFFFFF, 0xEDEDED, ink: 0x1C1C1C, accent: 0x1C1C1C, .star),
        // was peach bg / brown ink: real plate is blue-sky-to-tan-desert with a navy serial and Delicate Arch — added an arch motif for it
        "UT": .init(0xBFE0F2, 0xE0C29A, ink: 0x14305C, accent: 0xC8623E, .arch),
        // unchanged — matched already
        "VT": .init(0x1F5C3A, 0x1B5230, ink: 0xFFFFFF, accent: 0xFFFFFF, .pine),
        // unchanged — matched already, small heart accent kept as the red device
        "VA": .init(0xFFFFFF, 0xF2F6FA, ink: 0x14305C, accent: 0xB3282D, .horizon),
        // was light-blue bg / green ink: real plate is warm cream with a navy serial; Rainier silhouette keeps the mountains motif
        "WA": .init(0xF2ECD8, 0xE8E0CC, ink: 0x14305C, accent: 0xBFE0F2, .mountains),
        // state-seal watermark + gold rules, not a mountain graphic — kept the shape as the closest existing fit
        "WV": .init(0xFFFFFF, 0xF2F6FA, ink: 0x14305C, accent: 0xE0B84B, .mountains),
        // was cream/wheat-toned bg / maroon ink: real plate is flat white with a black serial; wheat kept loosely for the farm-scene vignette
        "WI": .init(0xFFFFFF, 0xF2F2F2, ink: 0x1C1C1C, accent: 0xD97B3D, .wheat),
        // no photo yet — WY's agency still only shows the retired 2017 sample
        "WY": .init(0xF7FAFD, 0xDCE9F2, ink: 0x8A3A1E, accent: 0x2B4C7E, .mountains),

        // ---- bonus ----
        // DC flag's three stars — swapped skyline for star, there's no skyline on this plate
        "DC": .init(0xFFFFFF, 0xEDF1F7, ink: 0x14305C, accent: 0xB3282D, .star),
        // unchanged — matched already
        "PR": .init(0xBFE0F2, 0x8FB4D6, ink: 0x1C1C1C, accent: 0x9E1A24, .wave),

        // ---- Canada ----
        // was white bg / navy ink: the 2020 redesign (A Place to Grow) is solid blue with a white serial — the old white/navy values belonged to the previous design (colours adjusted from the raw photo to clear WCAG AA)
        "ON": .init(0x1B4A8C, 0x2E6BB0, ink: 0xFFFFFF, accent: 0xFFFFFF, .maple),
        // was sharing Ontario's maple motif — fleur-de-lis is Quebec's actual mark and now reads distinctly from Ontario at tile size
        "QC": .init(0xFFFFFF, 0xE9EFF7, ink: 0x14305C, accent: 0x4A78C4, .fleurDeLis),
        // Union Jack/sunburst flag; off-white speckled sheeting
        "BC": .init(0xF7F5EE, 0xEDEADF, ink: 0x14305C, accent: 0x6FA8DC, .wave),
        // wild rose + small flag device
        "AB": .init(0xFFFFFF, 0xF2EDE8, ink: 0xB3282D, accent: 0xE0876A, .bloom),
        // prairie-and-forest landscape with a bison; maple kept as the Canada-wide shorthand
        "MB": .init(0xBFE0F2, 0xE0C97A, ink: 0x14305C, accent: 0x6FA88A, .maple),
        // unchanged — matched already
        "SK": .init(0xF2ECD8, 0xE9DFC4, ink: 0x1F5C3A, accent: 0xE0B84B, .wheat),
        // unchanged — matched already
        "NS": .init(0xFFFFFF, 0xF2F6FA, ink: 0x1B4A8C, accent: 0x6FA8DC, .wave),
        // sky-wash arc + sailing-ship logo
        "NB": .init(0xFFFFFF, 0xF2E4D2, ink: 0x9E1A24, accent: 0xE0B84B, .wave),
        // pitcher-plant flower logo — same new bloom shape as Alberta's rose
        "NL": .init(0xFFFFFF, 0xF2F6FA, ink: 0x1B3A8C, accent: 0xB3282D, .bloom),
        // coat of arms crest; no heraldic-shield motif exists, left unset rather than force a poor fit
        "PE": .init(0xFFFFFF, 0xF2F6FA, ink: 0x1F5C3A, accent: 0xB3282D, nil),
        // unchanged — matched already
        "NT": .init(0xBFE0F2, 0xFFFFFF, ink: 0x14305C, accent: 0x6FA8DC, .mountains),
        // no photo yet — the 1990 design has never had a free-licensed photo turn up
        "YT": .init(0xFDF6E0, 0xEDD9A8, ink: 0x6B4A1E, accent: 0xC8A02E, .mountains),
        // aurora-over-snow scene; no aurora motif exists, horizon is the neutral fallback (colours adjusted from the raw photo to clear WCAG AA)
        "NU": .init(0xC2B4DC, 0xBFE0F2, ink: 0x1C1C1C, accent: 0x2E8B8B, .horizon)
    ]
}
