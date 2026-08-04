import SwiftUI

/// A short burst of paper thrown out of a plate you just found.
///
/// Drawn deliberately *outside* its own frame so it looks like it came out of the
/// tile rather than being contained by it — SwiftUI does not clip children unless
/// asked, so the only boundary is the scroll view's edge, which is where you would
/// want it clipped anyway.
///
/// Give the view a fresh `.id()` per burst: the pieces are randomised once per
/// view identity, so a new id means new paper, and the same id means the burst is
/// left alone while the grid re-renders around it.
struct ConfettiBurst: View {

    /// Scales the burst. An ordinary find gets a puff; a legendary one gets thrown
    /// across the screen. Fifty identical full-screen cannons a trip would stop
    /// being a reward and start being an obstacle.
    var tier: RarityTier = .uncommon

    private struct Piece: Identifiable {
        let id: Int
        let dx: CGFloat
        let dy: CGFloat
        let spin: Double
        let width: CGFloat
        let height: CGFloat
        let color: Color
        let isRound: Bool
    }

    @State private var pieces: [Piece] = []

    /// Starts part-way out rather than at zero. A burst that begins at the centre
    /// spends its most opaque frames sitting on the plate's own lettering, which
    /// reads as the confetti covering up the thing you just won.
    @State private var spread: CGFloat = 0.38
    @State private var fade: Double = 1

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Group {
                    if piece.isRound {
                        Circle().fill(piece.color)
                    } else {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(piece.color)
                    }
                }
                .frame(width: piece.width, height: piece.height)
                .rotationEffect(.degrees(piece.spin * Double(spread)))
                .offset(x: piece.dx * spread, y: piece.dy * spread)
            }
        }
        .opacity(fade)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            pieces = Self.make(tier: tier)
            // Bigger bursts fly for longer, or the legendary pieces would have to
            // travel three times as far in the same 0.78s and read as an explosion.
            let travel = 0.72 + Double(tier.rawValue) * 0.09
            withAnimation(.easeOut(duration: travel)) { spread = 1 }
            // Fading on its own, later clock lets the paper actually travel before
            // it disappears. One shared animation would start it dissolving from
            // the first frame.
            withAnimation(.easeIn(duration: 0.36).delay(travel * 0.62)) { fade = 0 }
        }
    }

    private static func make(tier: RarityTier) -> [Piece] {
        let palette: [Color] = [
            Theme.paint,
            Theme.route,
            Color(hex: 0x3DDC84),
            Color(hex: 0xFF7A45),
            Color(hex: 0x4DA3FF),
            Color(hex: 0xFF5D8F)
        ]

        let count = tier.confettiCount
        // Far enough that even the smallest tier clears an 84x50 tile rather than
        // landing back on the lettering.
        let reach = tier.confettiReach

        return (0..<count).map { i in
            // Spread evenly around the circle, then jitter, so the burst never
            // looks like a clock face but never leaves a bald patch either.
            let slice = (Double.pi * 2) / Double(count)
            let angle = slice * Double(i) + Double.random(in: -slice / 2.4...slice / 2.4)
            let distance = CGFloat.random(in: reach)

            return Piece(
                id: i,
                dx: cos(angle) * distance,
                // Constant droop: the pieces end up a little lower than they were
                // thrown, which is enough to read as gravity over 0.8s.
                dy: sin(angle) * distance + 16,
                spin: Double.random(in: -280...280),
                width: CGFloat.random(in: 3...4.5),
                height: CGFloat.random(in: 4.5...8),
                color: palette[i % palette.count],
                isRound: i % 4 == 0
            )
        }
    }
}
