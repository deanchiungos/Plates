import SwiftUI

/// The road rail: a filled route-blue bed, a dashed road-paint centre line, and a
/// mile-marker pin that travels with progress.
struct RoadRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                    .frame(height: 10)

                Capsule().fill(Theme.route)
                    .frame(width: max(10, w * clamped), height: 10)

                // dashed centre line
                Path { p in
                    p.move(to: CGPoint(x: 8, y: 5))
                    p.addLine(to: CGPoint(x: w - 8, y: 5))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [9, 9]))
                .foregroundStyle(Theme.paint)
                .frame(height: 10)

                Circle()
                    .fill(Theme.paint)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 3, y: 2)
                    .offset(x: (w * clamped) - 10)
            }
            .frame(height: geo.size.height, alignment: .center)
        }
        .frame(height: 26)
        .animation(.snappy(duration: 0.32), value: progress)
        .accessibilityHidden(true)
    }
}

struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIVE TRIP \u{00B7} DAY \(trip.dayNumber)")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Theme.inkMuted)

            Text(trip.name)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)
                .padding(.top, 2)

            Text(trip.scoringMode.label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 1)

            RoadRail(progress: trip.progress)
                .padding(.top, 14)

            HStack {
                Text("Start")
                Spacer()
                Text("\(trip.statesFound) of \(Plate.stateTotal)")
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkMuted)
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
                .shadow(color: Theme.ink.opacity(0.10), radius: 9, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Compact standings, sitting between the trip card and the grid. Hidden entirely
/// when only one person is playing — solo play should not pay for multiplayer chrome.
struct PlayerStrip: View {
    let standings: [(player: Player, score: Int)]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(standings.enumerated()), id: \.element.player.id) { index, entry in
                let color = Theme.playerColor(entry.player.colorIndex)
                let isLeader = index == 0 && entry.score > 0

                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Text(entry.player.initial)
                                    .font(Theme.PlateFont.condensed(10))
                                    .foregroundStyle(Theme.ink)
                            )
                        Text(entry.player.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                    Text("\(entry.score)")
                        .font(Theme.PlateFont.condensed(19))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(isLeader ? color : Theme.line,
                                              lineWidth: isLeader ? 1.5 : 1)
                        )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.player.name), \(entry.score) points\(isLeader ? ", leading" : "")")
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.inkMuted)
        }
    }
}
