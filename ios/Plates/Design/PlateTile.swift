import SwiftUI

/// The core component. 5:3 plate proportions, an inner light ring standing in for
/// the embossed edge, and — when several people are playing — a colour bar along
/// the bottom showing who called it. The bar rather than a full tint, so the tile
/// still reads as a plate.
struct PlateTile: View {
    let plate: Plate
    let isFound: Bool
    var spotterColor: Color? = nil
    var spotterInitial: String? = nil
    var repeatCount: Int = 0          // shown only in unlimited scoring
    var showsRepeats: Bool = false

    /// Spotting a plate reveals its own colours. Unfound stays paper, so the
    /// found/unfound read is still instant even once every state is styled.
    private var style: PlateStyle? {
        isFound ? (PlateStyle.style(for: plate.code) ?? .fallback) : nil
    }

    var body: some View {
        ZStack {
            if let style {
                PlateArtLayer(style: style)
            } else {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.surface)
            }

            // embossed edge
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(isFound ? Color.white.opacity(0.35) : Color.white, lineWidth: 1.5)
                .padding(1)

            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(isFound ? Color.black.opacity(0.22) : Theme.line, lineWidth: 1)

            VStack(spacing: 2) {
                Text(plate.code)
                    .font(Theme.PlateFont.condensed(19))
                    .tracking(0.6)
                    .foregroundStyle(style?.ink ?? Theme.plateIdle)

                Text(plate.short.uppercased())
                    .font(Theme.PlateFont.condensed(8))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    .foregroundStyle((style?.ink ?? Theme.plateSub).opacity(isFound ? 0.72 : 1))
            }

            // rarity pip — top right, off the fill so found-state owns the colour
            if plate.isRare {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Theme.paint)
                            .frame(width: 4.5, height: 4.5)
                    }
                    Spacer()
                }
                .padding(5)
            }

            // Who spotted it: a chip in the top-left, opposite the rarity pip.
            // Tried a bottom bar and a coloured border first — the bar sat exactly
            // where every motif's horizon is, and the border read as "selected"
            // rather than "Mia got this one". The chip also shows *who*, not just
            // a colour, so it works without the player strip in view.
            if isFound, let spotterColor, let spotterInitial {
                VStack {
                    HStack {
                        Text(spotterInitial)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 12, height: 12)
                            .background(Circle().fill(spotterColor))
                            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(4)
            }

            // bottom-left, so it never collides with the spotter chip above it
            if showsRepeats, repeatCount > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(repeatCount)")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle((style?.ink ?? Theme.plateSub).opacity(0.75))
                        Spacer()
                    }
                }
                .padding(5)
            }
        }
        .aspectRatio(Theme.tileAspect, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plate.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        var parts: [String] = [isFound ? "Spotted" : "Not yet spotted"]
        if plate.isRare { parts.append("rare") }
        if isFound, showsRepeats, repeatCount > 1 { parts.append("seen \(repeatCount) times") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    return LazyVGrid(columns: cols, spacing: 8) {
        PlateTile(plate: Plate.plate(for: "OH")!, isFound: false)
        PlateTile(plate: Plate.plate(for: "CO")!, isFound: true)
        PlateTile(plate: Plate.plate(for: "AK")!, isFound: false)
        PlateTile(plate: Plate.plate(for: "MT")!, isFound: true,
                  spotterColor: Theme.playerColor(1))
    }
    .padding()
    .background(Theme.ground)
}
