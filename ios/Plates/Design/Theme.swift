import SwiftUI

/// The Mile Marker tokens. One accent (route blue) carries state; one signal
/// (road-paint amber) is reserved for rarity and progress. Neutrals are biased
/// cool toward the blue rather than being pure grey.
enum Theme {

    // MARK: Colour
    static let ground     = Color(hex: 0xF7F8FA)
    static let surface    = Color(hex: 0xFFFFFF)
    static let route      = Color(hex: 0x12395E)
    static let routeEdge  = Color(hex: 0x0D2C4A)
    static let routeRing  = Color(hex: 0x2B5A87)
    static let paint      = Color(hex: 0xF0B429)
    static let ink        = Color(hex: 0x101A2C)
    static let inkMuted   = Color(hex: 0x7E8CA3)
    static let line       = Color(hex: 0xE4E8EE)
    static let plateIdle  = Color(hex: 0x8A97AC)
    static let plateSub   = Color(hex: 0xB4BECC)
    static let plateOnSub = Color(hex: 0x8FB4D6)

    /// Player colours, chosen to stay distinguishable against the route-blue fill
    /// and from each other. Players store an index into this array.
    static let playerColors: [Color] = [
        Color(hex: 0x3DDC84),   // green
        Color(hex: 0xFF7A45),   // orange
        Color(hex: 0x4DA3FF),   // blue
        Color(hex: 0xFFD23F),   // yellow
        Color(hex: 0xC77DFF),   // violet
        Color(hex: 0xFF5D8F)    // pink
    ]

    static func playerColor(_ index: Int) -> Color {
        playerColors[((index % playerColors.count) + playerColors.count) % playerColors.count]
    }

    // MARK: Type
    //
    // DIN is the road-sign face used on real plates and ships with iOS, so it costs
    // nothing and it is the subject's own vernacular. It is restricted to plate
    // glyphs and eyebrows; anything read as a sentence uses the system face.
    enum PlateFont {
        static func condensed(_ size: CGFloat) -> Font {
            // .custom falls back to the system face if the family is ever unavailable.
            .custom("DINCondensed-Bold", size: size)
        }
    }

    // MARK: Metrics
    static let tileAspect: CGFloat = 5.0 / 3.0
    static let tileRadius: CGFloat = 7
    static let cardRadius: CGFloat = 16
    static let gridGap: CGFloat = 8
    static let screenPadding: CGFloat = 16

    /// The grid adapts rather than fixing a column count: 4 across on a phone,
    /// more on an iPad, without the tiles ballooning to fill the width.
    static let tileMinWidth: CGFloat = 78
    static let tileMaxWidth: CGFloat = 104
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}
