import SwiftUI

/// Whatever goes behind a plate's lettering.
///
/// Two sources, and the split is permanent rather than a migration half-done.
/// 63 jurisdictions have artwork built from an actual photograph of the design
/// currently on the road — see `ios/tools/plate_art_assets.py`. Wyoming and
/// Yukon have no freely usable photograph to work from, so they keep the
/// hand-built vector motif, which is also the fallback if an asset ever fails
/// to resolve.
///
/// The artwork is deliberately empty through the middle: every piece of it was
/// generated with the graphics pushed to the edges precisely so the code and
/// state name could sit in a clear band, the way a serial does on a real plate.
struct PlateBackground: View {
    let code: String
    let style: PlateStyle

    var body: some View {
        Group {
            // One lookup, not three. This body runs for every visible tile on
            // every scroll frame, so has/imageName/scrim as separate calls was
            // three dictionary hits and a string interpolation each time.
            if let art = PlateArtwork.table[code] {
                ZStack {
                    Image(art.asset)
                        .resizable()
                        // No .interpolation(.high): the asset now ships at 3x the
                        // tile's own size, so it draws at roughly 1:1 and the extra
                        // quality buys nothing while costing a resample per draw.
                        //
                        // The asset is already 5:3, so scaledToFill only matters if
                        // a caller frames it at some other ratio — fill rather than
                        // letterbox, since a plate with bars down the side stops
                        // being a plate.
                        .scaledToFill()

                    // Set by hand per plate in the review tool, for the busy
                    // designs where moving the text wasn't enough on its own —
                    // Rushmore, an aurora. Same opposite-luminance color as the
                    // halo, so dialling it up just deepens the same effect rather
                    // than introducing a second treatment.
                    if art.scrim > 0 {
                        Color(hex: art.embossHex).opacity(art.scrim)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius,
                                            style: .continuous))
            } else {
                PlateArtLayer(style: style)
            }
        }
    }
}

/// The lettering, in the color the real plate paints its serial.
///
/// Split out of PlateTile because the trail map draws the same thing at a third
/// of the size, and the two were already drifting: the map had lost the state
/// name and was still painting the code with the vector catalogue's ink after
/// the artwork underneath it had changed.
struct PlateLettering: View {
    let code: String
    let style: PlateStyle
    var codeSize: CGFloat = 19
    var showsName: Bool = true
    var name: String = ""

    /// The artwork's ink where there is artwork, the vector catalogue's where
    /// there is not. Never a blend of the two — that is how the map ended up
    /// with navy type on a plate that had become white.
    private var ink: Color { PlateArtwork.ink(code) ?? style.ink }

    var body: some View {
        // The offset is a fraction of the tile's own size, not points — set by
        // hand in the review tool — so the same (x, y) holds for a 78pt Game
        // tile and a 48pt trail pin.
        //
        // `visualEffect` rather than GeometryReader. Both can read the size, but
        // GeometryReader is a layout container: 65 of them in a scrolling grid
        // means 65 extra layout passes, re-run as cells recycle. visualEffect
        // hands you the same proxy at *render* time and can only do things that
        // don't affect layout — offset being exactly one of them. Filling the
        // tile first is what makes proxy.size the tile rather than the glyphs.
        //
        // Read out here rather than inside the closure: `visualEffect` takes a
        // `@Sendable` closure and `offset` is a property of this main-actor view,
        // so reaching for it at render time is exactly what that annotation
        // forbids. Two Doubles cross the boundary instead.
        let shift = offset
        return block
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .visualEffect { content, proxy in
                content.offset(x: proxy.size.width * shift.x,
                              y: proxy.size.height * shift.y)
            }
    }

    private var offset: (x: Double, y: Double) { PlateArtwork.offset(code) }

    // Tight. The artwork's clear band is a little over a third of the plate and
    // two lines of type do not fit inside it at 50pt, so every point saved
    // between them is a point the state name is not sitting on a bottom border.
    private var block: some View {
        VStack(spacing: 1) {
            Text(code)
                .font(Theme.PlateFont.glyph(codeSize))
                .tracking(0.6)
                .foregroundStyle(ink)

            if showsName {
                Text(name.uppercased())
                    .font(Theme.PlateFont.glyph(codeSize * 7.5 / 19))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    // The fade lives in the color, not in .opacity(). A view-level
                    // opacity below 1 makes SwiftUI composite that view through its
                    // own layer; folding it into the paint is the same pixels for
                    // free.
                    .foregroundStyle(ink.opacity(0.72))
            }
        }
        .modifier(Emboss(code: code))
    }
}

/// A soft ring behind the type, on the four plates whose own two colors do not
/// clear WCAG AA: New Mexico is genuinely yellow on turquoise, Ontario genuinely
/// white on blue. Repainting them into colors they do not have would be the
/// worse lie, so they get a ring instead.
///
/// It used to be two rings on every plate with artwork. That is 130 offscreen
/// blur passes across a full grid, recomputed on every scroll frame, and it was
/// the single biggest reason the grid stuttered. It was also mostly redundant by
/// then: the review pass moved the lettering by hand on 60 of the 63, which is
/// the real fix for type landing on Maryland's flag. Four plates still need it,
/// and four blurs is free.
private struct Emboss: ViewModifier {
    let code: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if let halo = PlateArtwork.halo(code) {
            content
                .shadow(color: halo.opacity(0.9), radius: 1.1)
                .shadow(color: halo.opacity(0.6), radius: 2.2)
        } else {
            content
        }
    }
}
