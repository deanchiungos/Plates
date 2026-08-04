import SwiftUI

// Original shapes, drawn to read at ~84x50pt. Each is deliberately generic —
// a ridgeline, not a named peak; a skyline, not an identifiable building.

struct Ridgeline: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.62))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.30))
        p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.58))
        p.addLine(to: CGPoint(x: w * 0.60, y: h * 0.22))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.56))
        p.addLine(to: CGPoint(x: w, y: h * 0.40))
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }
}

struct FivePointStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        var p = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = (Double(i) * .pi / 5) - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct SkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let heights: [CGFloat] = [0.45, 0.72, 0.55, 0.88, 0.60, 0.78, 0.40]
        var p = Path()
        let w = rect.width / CGFloat(heights.count)
        for (i, f) in heights.enumerated() {
            let bh = rect.height * f
            p.addRect(CGRect(x: CGFloat(i) * w, y: rect.maxY - bh, width: w * 0.78, height: bh))
        }
        return p
    }
}

/// Two stacked swells, filled to the bottom edge.
struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.55))
        p.addCurve(to: CGPoint(x: w, y: h * 0.55),
                   control1: CGPoint(x: w * 0.30, y: h * 0.05),
                   control2: CGPoint(x: w * 0.70, y: h * 1.05))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

/// A simple conifer triangle-stack, repeated.
struct PineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let trees = 3
        let tw = w / CGFloat(trees)
        for i in 0..<trees {
            let cx = tw * (CGFloat(i) + 0.5)
            let base = h
            let top = h * (i == 1 ? 0.05 : 0.24)
            p.move(to: CGPoint(x: cx, y: top))
            p.addLine(to: CGPoint(x: cx + tw * 0.38, y: base))
            p.addLine(to: CGPoint(x: cx - tw * 0.38, y: base))
            p.closeSubpath()
        }
        return p
    }
}

/// Stalk-and-ear strokes suggesting a field, not a botanical drawing.
struct WheatShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let stalks = 5
        for i in 0..<stalks {
            let x = w * (CGFloat(i) + 0.5) / CGFloat(stalks)
            let top = h * (i.isMultiple(of: 2) ? 0.18 : 0.36)
            p.move(to: CGPoint(x: x, y: h))
            p.addLine(to: CGPoint(x: x, y: top))
            // two short ears
            p.move(to: CGPoint(x: x, y: top + h * 0.16))
            p.addLine(to: CGPoint(x: x + w * 0.05, y: top + h * 0.04))
            p.move(to: CGPoint(x: x, y: top + h * 0.16))
            p.addLine(to: CGPoint(x: x - w * 0.05, y: top + h * 0.04))
        }
        return p
    }
}

/// A stylised maple — five lobes off a centre stem, not the flag's geometry.
struct MapleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = w / 2
        p.move(to: CGPoint(x: cx, y: h))
        p.addLine(to: CGPoint(x: cx, y: h * 0.62))
        p.move(to: CGPoint(x: cx, y: h * 0.66))
        p.addLine(to: CGPoint(x: cx - w * 0.34, y: h * 0.46))
        p.move(to: CGPoint(x: cx, y: h * 0.66))
        p.addLine(to: CGPoint(x: cx + w * 0.34, y: h * 0.46))
        p.move(to: CGPoint(x: cx, y: h * 0.62))
        p.addLine(to: CGPoint(x: cx - w * 0.24, y: h * 0.18))
        p.move(to: CGPoint(x: cx, y: h * 0.62))
        p.addLine(to: CGPoint(x: cx + w * 0.24, y: h * 0.18))
        p.move(to: CGPoint(x: cx, y: h * 0.60))
        p.addLine(to: CGPoint(x: cx, y: h * 0.06))
        return p
    }
}

/// Three simple lobes off a central spike — a fleur-de-lis, not the state
/// achievement's exact geometry.
struct FleurDeLisShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = w / 2
        p.move(to: CGPoint(x: cx, y: h))
        p.addLine(to: CGPoint(x: cx, y: h * 0.30))
        p.move(to: CGPoint(x: cx, y: h * 0.34))
        p.addQuadCurve(to: CGPoint(x: cx - w * 0.30, y: h * 0.50),
                        control: CGPoint(x: cx - w * 0.10, y: h * 0.10))
        p.move(to: CGPoint(x: cx, y: h * 0.34))
        p.addQuadCurve(to: CGPoint(x: cx + w * 0.30, y: h * 0.50),
                        control: CGPoint(x: cx + w * 0.10, y: h * 0.10))
        p.move(to: CGPoint(x: cx - w * 0.22, y: h * 0.78))
        p.addLine(to: CGPoint(x: cx + w * 0.22, y: h * 0.78))
        return p
    }
}

/// A generic irregular place-mark — evokes "a small outlined region on a map"
/// without tracing any actual jurisdiction's boundary.
struct PlaceMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.30, y: h * 0.05))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.16))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.60))
        p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.95))
        p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.06, y: h * 0.44))
        p.closeSubpath()
        return p
    }
}

/// A rounded doorway — a natural arch, not Delicate Arch's specific silhouette.
struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let legW = w * 0.22
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.42))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.42),
                        control: CGPoint(x: w / 2, y: -h * 0.20))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w - legW, y: h))
        p.addLine(to: CGPoint(x: w - legW, y: h * 0.56))
        p.addQuadCurve(to: CGPoint(x: legW, y: h * 0.56),
                        control: CGPoint(x: w / 2, y: h * 0.06))
        p.addLine(to: CGPoint(x: legW, y: h))
        p.closeSubpath()
        return p
    }
}

/// A column with two symmetric arms — a saguaro, not a botanical study.
struct CactusShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let cx = w / 2, armW = w * 0.20
        p.addRect(CGRect(x: cx - armW * 0.35, y: 0, width: armW * 0.7, height: h))
        p.addRect(CGRect(x: cx - w * 0.32, y: h * 0.34, width: armW * 0.6, height: h * 0.5))
        p.addRect(CGRect(x: cx - w * 0.32, y: h * 0.30, width: armW * 0.6, height: armW * 0.6))
        p.addRect(CGRect(x: cx + w * 0.14, y: h * 0.20, width: armW * 0.6, height: h * 0.62))
        p.addRect(CGRect(x: cx + w * 0.14, y: h * 0.16, width: armW * 0.6, height: armW * 0.6))
        return p
    }
}

/// Five petals around a centre — one stylised bloom, not any particular species.
struct BloomShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.42
        for i in 0..<5 {
            let a = Double(i) * .pi * 2 / 5 - .pi / 2
            let petal = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            let ctrlA = Double(i) * .pi * 2 / 5 - .pi / 2 - 0.5
            let ctrlB = Double(i) * .pi * 2 / 5 - .pi / 2 + 0.5
            let c1 = CGPoint(x: c.x + CGFloat(cos(ctrlA)) * r * 0.55,
                              y: c.y + CGFloat(sin(ctrlA)) * r * 0.55)
            let c2 = CGPoint(x: c.x + CGFloat(cos(ctrlB)) * r * 0.55,
                              y: c.y + CGFloat(sin(ctrlB)) * r * 0.55)
            p.move(to: c)
            p.addCurve(to: petal, control1: c1, control2: c)
            p.addCurve(to: c, control1: petal, control2: c2)
        }
        return p
    }
}

// MARK: - Renderer

/// Draws the motif behind the lettering, always dialled back so the state code
/// stays the most legible thing on the tile.
struct PlateArtLayer: View {
    let style: PlateStyle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let accent = style.accent ?? .white

            ZStack {
                LinearGradient(colors: style.background, startPoint: .top, endPoint: .bottom)

                switch style.motif {
                case .mountains:
                    Ridgeline()
                        .fill(accent.opacity(0.55))
                        .frame(width: w, height: h * 0.46)
                        .position(x: w / 2, y: h - (h * 0.23))

                case .star:
                    FivePointStar()
                        .fill(accent.opacity(0.30))
                        .frame(width: h * 0.42, height: h * 0.42)
                        .position(x: w * 0.16, y: h * 0.30)

                case .sunDisc:
                    Circle()
                        .fill(accent.opacity(0.42))
                        .frame(width: h * 0.70, height: h * 0.70)
                        .position(x: w * 0.82, y: h * 0.86)

                case .rainbow:
                    // A 50pt tile has no clear band left once two lines of type
                    // are in it, so the arc passes BEHIND the lettering.
                    ZStack {
                        ForEach(Array(rainbowColors.enumerated()), id: \.offset) { i, c in
                            let d = w * (1.30 - Double(i) * 0.11)
                            Circle()
                                .strokeBorder(c.opacity(0.30), lineWidth: 2.5)
                                .frame(width: d, height: d)
                        }
                    }
                    .position(x: w / 2, y: h * 1.40)

                case .scriptBar:
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: w * 0.32, height: 2.5)
                        .position(x: w / 2, y: h * 0.11)

                case .skyline:
                    SkylineShape()
                        .fill(accent.opacity(0.22))
                        .frame(width: w * 0.78, height: h * 0.34)
                        .position(x: w / 2, y: h - (h * 0.17))

                case .wave:
                    WaveShape()
                        .fill(accent.opacity(0.38))
                        .frame(width: w, height: h * 0.42)
                        .position(x: w / 2, y: h - (h * 0.21))

                case .pine:
                    PineShape()
                        .fill(accent.opacity(0.42))
                        .frame(width: w * 0.42, height: h * 0.44)
                        .position(x: w * 0.20, y: h - (h * 0.22))

                case .wheat:
                    WheatShape()
                        .stroke(accent.opacity(0.45), lineWidth: 1.2)
                        .frame(width: w * 0.46, height: h * 0.42)
                        .position(x: w * 0.78, y: h - (h * 0.21))

                case .maple:
                    MapleShape()
                        .stroke(accent.opacity(0.45), lineWidth: 1.6)
                        .frame(width: h * 0.44, height: h * 0.44)
                        .position(x: w * 0.16, y: h * 0.68)

                case .horizon:
                    // the quiet default: a soft band across the lower third
                    Ellipse()
                        .fill(accent.opacity(0.20))
                        .frame(width: w * 1.6, height: h * 0.9)
                        .position(x: w / 2, y: h * 1.28)

                case .fleurDeLis:
                    FleurDeLisShape()
                        .fill(accent.opacity(0.40))
                        .frame(width: h * 0.36, height: h * 0.46)
                        .position(x: w * 0.16, y: h * 0.62)

                case .stateOutline:
                    PlaceMarkShape()
                        .stroke(accent.opacity(0.50), lineWidth: 1.4)
                        .frame(width: h * 0.50, height: h * 0.50)
                        .position(x: w * 0.82, y: h * 0.30)

                case .arch:
                    ArchShape()
                        .fill(accent.opacity(0.42))
                        .frame(width: w * 0.40, height: h * 0.48)
                        .position(x: w * 0.80, y: h - (h * 0.24))

                case .cactus:
                    CactusShape()
                        .fill(accent.opacity(0.42))
                        .frame(width: w * 0.20, height: h * 0.60)
                        .position(x: w * 0.16, y: h - (h * 0.30))

                case .bloom:
                    BloomShape()
                        .fill(accent.opacity(0.38))
                        .frame(width: h * 0.40, height: h * 0.40)
                        .position(x: w * 0.84, y: h * 0.26)

                case .none:
                    EmptyView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
    }

    private var rainbowColors: [Color] {
        [Color(hex: 0xE04A3F), Color(hex: 0xF0A32E),
         Color(hex: 0x3FA85B), Color(hex: 0x2F7FC4)]
    }
}
