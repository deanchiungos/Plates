import SwiftUI

/// Who is here, in the smallest space that can say it: overlapping circles of
/// initials, with a "+N" when there are more than fit.
///
/// The overlap is the point. A row of separate dots reads as a list and takes the
/// width of one, and at four or five people a list is what you get. Overlapping
/// them says "a group" at a glance and costs about half the space — which is why
/// every app that has to show a team in a table row ends up here.
///
/// The ring is what makes it work. Two circles in similar colours, or two dark
/// avatars on a dark row, merge into one blob without a stroke between them; the
/// ring is drawn in the *background* colour so it reads as a gap rather than as a
/// border, and each circle stays a circle whatever it is sitting on.
struct AvatarStack: View {
    let players: [Player]

    /// Total circles drawn, including the overflow one. Past this, the last circle
    /// becomes "+N" — so a limit of 4 shows three faces and a count.
    var limit: Int = 4
    var size: CGFloat = 24
    /// The colour the ring is cut out of. Whatever the stack is sitting on.
    var background: Color = Theme.surface

    private var shown: [Player] {
        players.count > limit ? Array(players.prefix(limit - 1)) : players
    }

    private var overflow: Int { players.count - shown.count }

    var body: some View {
        // Negative spacing is the overlap. A third of the diameter is enough to
        // read as a group and still leaves both initials legible.
        HStack(spacing: -size * 0.32) {
            ForEach(shown) { player in
                circle(fill: Theme.playerColor(player.colorIndex),
                       text: player.face,
                       ink: Theme.ink,
                       isEmoji: player.usesEmoji)
            }
            if overflow > 0 {
                circle(fill: background,
                       text: "+\(overflow)",
                       ink: Theme.inkMuted,
                       isEmoji: false)
                // A neutral circle with no ring would vanish into the background it
                // is cut from, so it keeps a hairline of its own.
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func circle(fill: Color, text: String, ink: Color, isEmoji: Bool) -> some View {
        Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                Text(text)
                    // Emoji get the system face at a slightly larger size: the
                    // condensed plate font does not carry them, and a glyph drawn
                    // from a fallback at letter-size sits small in the circle.
                    .font(isEmoji ? .system(size: size * 0.55)
                                  : Theme.PlateFont.glyph(size * 0.42))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            )
            .overlay(Circle().strokeBorder(background, lineWidth: size * 0.08))
    }

    private var label: String {
        switch players.count {
        case 0:  return ""
        case 1:  return players[0].name
        default: return players.map(\.name).formatted(.list(type: .and))
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        AvatarStack(players: [])
        AvatarStack(players: previewPlayers(1))
        AvatarStack(players: previewPlayers(3))
        AvatarStack(players: previewPlayers(5))
        AvatarStack(players: previewPlayers(5), size: 12)
    }
    .padding()
    .background(Theme.surface)
}

@MainActor
private func previewPlayers(_ n: Int) -> [Player] {
    let names = ["Aunt Deb", "Alex Shaw", "Cal Dunn", "Gus West", "Eve Park"]
    return (0..<n).map { Player(name: names[$0], colorIndex: $0) }
}
