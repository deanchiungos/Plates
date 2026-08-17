import SwiftUI

/// The app icon, drawn rather than exported by hand.
///
/// Keeping it as SwiftUI means the icon and the plate tiles are the same drawing at
/// different scales — same route blue, same embossed inner ring, same DIN Condensed.
/// PNGs come out through `ImageRenderer`, so there is no hand-made asset that can
/// drift away from the app it belongs to.
///
/// Every measurement is a fraction of `size`, so the 1024 px export and the 29 pt
/// settings icon are one picture at two scales rather than two drawings that happen
/// to resemble each other.
struct AppIconArt: View {

    /// What stands in the middle of the serial.
    enum Separator: String, CaseIterable, Identifiable {
        case bolt     // a stamped plate bolt
        case dot      // a plain amber dot
        case gap      // empty space
        case none     // no break at all

        var id: String { rawValue }
    }

    /// What sits behind the plate.
    enum Backdrop: String, CaseIterable, Identifiable {
        case navy       // Theme.route — the original, and the heaviest
        case mid        // Theme.routeRing
        case midGrad    // routeRing into route, top to bottom
        case sky        // lighter still

        var id: String { rawValue }

        @ViewBuilder var fill: some View {
            switch self {
            case .navy: Theme.route
            case .mid:  Theme.routeRing
            case .sky:  Color(hex: 0x3A72A8)
            case .midGrad:
                LinearGradient(colors: [Theme.routeRing, Theme.route],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// What is printed on the plate itself.
    enum Face: String, CaseIterable, Identifiable {
        case plain      // flat white
        case sky        // pale sky gradient
        case ridge      // sky gradient with a mountain range along the bottom

        var id: String { rawValue }
    }

    var backdrop: Backdrop = .mid
    var face: Face = .ridge
    var separator: Separator = .bolt
    var showsCaption: Bool = true
    var size: CGFloat = 1024

    /// iOS masks the icon itself, so a shipped asset must be a flat square.
    /// Rounding is for previewing only.
    var rounded: Bool = true

    /// The catalogue carries two drawings. Above 60 pt there is room for the bolt to
    /// register as hardware and for the gap to read as a serial break; below it, both
    /// just eat width the letters need, so the wordmark closes up.
    static func preset(forPointSize points: Double, size: CGFloat, rounded: Bool = false) -> AppIconArt {
        AppIconArt(backdrop: .mid,
                   // The ridgeline is detail, and detail below 60 pt is just noise
                   // on the letters. Small slots keep the plain plate.
                   face: points >= 60 ? .ridge : .sky,
                   separator: points >= 60 ? .bolt : .none,
                   showsCaption: true,
                   size: size,
                   rounded: rounded)
    }

    // MARK: Metrics, all relative to `size`

    private var plateWidth: CGFloat  { size * 0.885 }
    private var plateHeight: CGFloat { plateWidth * 0.6 }   // the 5:3 of a real plate
    private var plateRadius: CGFloat { size * 0.062 }
    private var inset: CGFloat       { size * 0.036 }

    /// Sized against the plate, not the icon. On a real plate the serial stands about
    /// half the plate's height; setting it against the whole canvas first made it look
    /// like fine print, and overcorrecting pushed six characters of DIN Condensed
    /// straight off the plate onto the navy.
    private var glyph: CGFloat { plateHeight * (showsCaption ? 0.44 : 0.52) }

    private var gap: CGFloat { size * 0.048 }

    /// Everything the serial has to live inside.
    private var innerWidth: CGFloat { plateWidth - inset * 3 }

    /// Sky, palest at the top. The same trick the plate tiles use to stop a found
    /// plate reading as a flat swatch.
    private var skyGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xDCEAF6), Color(hex: 0xFFFFFF)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Deliberately pale. The caption sits on top of these mountains, and a ridge
    /// dark enough to look dramatic drags the small text under 4.5:1.
    private let ridgeColor = Color(hex: 0xB9CFE3)

    var body: some View {
        ZStack {
            backdrop.fill

            ZStack {
                switch face {
                case .plain:
                    RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                        .fill(Color.white)
                case .sky, .ridge:
                    RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                        .fill(skyGradient)
                }

                if face == .ridge {
                    Ridgeline()
                        .fill(ridgeColor)
                        .frame(height: plateHeight * 0.42)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                // The embossed rim every stamped plate has. Faint on purpose: at
                // 29 pt it should register as weight, not as a second rectangle.
                RoundedRectangle(cornerRadius: plateRadius * 0.62, style: .continuous)
                    .strokeBorder(Theme.route.opacity(0.20), lineWidth: size * 0.014)
                    .padding(inset)

                // The width cap and scale factor are a backstop, not the plan: the
                // glyph size above should already fit. They mean a font substitution
                // or a longer wordmark can never spill onto the navy again.
                content
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: innerWidth)
            }
            .frame(width: plateWidth, height: plateHeight)
            .clipShape(RoundedRectangle(cornerRadius: plateRadius, style: .continuous))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? size * 0.2237 : 0,
                                    style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if showsCaption {
            VStack(spacing: size * 0.010) {
                serial
                caption
            }
            .offset(y: size * 0.010)
        } else {
            serial
        }
    }

    @ViewBuilder
    private var serial: some View {
        switch separator {
        case .none:
            letters("PLATES")
        case .gap:
            HStack(spacing: gap) { letters("PLA"); letters("TES") }
        case .dot:
            HStack(spacing: gap * 0.62) {
                letters("PLA")
                Circle().fill(Theme.paint)
                    .frame(width: size * 0.040, height: size * 0.040)
                letters("TES")
            }
        case .bolt:
            HStack(spacing: gap * 0.58) { letters("PLA"); bolt; letters("TES") }
        }
    }

    /// 0.8, not the 0.6 used on plain white. Over the ridge, 0.6 measures 3.05:1
    /// against the mountains and 0.75 still only reaches 4.23; 0.8 gets to 4.78 and
    /// clears the 4.5 line.
    private var caption: some View {
        Text("ROAD TRIP")
            .font(Theme.PlateFont.glyph(size * 0.062))
            .tracking(size * 0.016)
            .foregroundStyle(Theme.route.opacity(face == .ridge ? 0.8 : 0.6))
    }

    private func letters(_ text: String) -> some View {
        Text(text)
            .font(Theme.PlateFont.glyph(glyph))
            .tracking(size * 0.008)
            .foregroundStyle(Theme.route)
    }

    /// A stamped bolt head — amber ring, lighter centre, so it reads as hardware
    /// rather than as a full stop.
    private var bolt: some View {
        Circle()
            .fill(Theme.paint)
            .frame(width: size * 0.052, height: size * 0.052)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: size * 0.020, height: size * 0.020)
            )
    }
}

#if DEBUG
/// `-iconLab` opens this instead of the app: both catalogue drawings at the sizes
/// iOS will actually use them, because the only question that decides an icon is
/// whether it survives being shrunk.
struct IconLab: View {
    private let sizes: [CGFloat] = [86, 60, 40, 29]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                row("Navy \u{00B7} ridge") { AppIconArt(backdrop: .navy, face: .ridge, size: $0) }
                row("Mid \u{00B7} ridge") { AppIconArt(backdrop: .mid, face: .ridge, size: $0) }
                row("Mid gradient \u{00B7} ridge") { AppIconArt(backdrop: .midGrad, face: .ridge, size: $0) }
                row("Sky \u{00B7} ridge") { AppIconArt(backdrop: .sky, face: .ridge, size: $0) }
                row("Mid \u{00B7} sky only") { AppIconArt(backdrop: .mid, face: .sky, size: $0) }
                row("As the catalogue ships it") {
                    AppIconArt.preset(forPointSize: Double($0), size: $0, rounded: true)
                }

                Text(verbatim: "86 \u{00B7} 60 \u{00B7} 40 \u{00B7} 29 pt")
                    .font(.plates(size: 10))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(14)
        }
        .background(Theme.ground)
    }

    private func row(_ title: String,
                     art: @escaping (CGFloat) -> AppIconArt) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.plates(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkMuted)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(sizes, id: \.self) { s in
                    art(s).shadow(color: Theme.ink.opacity(0.22), radius: 3, y: 2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
#endif
