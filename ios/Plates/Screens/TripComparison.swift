import SwiftUI

/// Every trip side by side, ranked by states found.
///
/// This used to be a segmented "History" page inside the Book tab, which was two
/// mistakes at once: it listed trips and no books at all, and it sat behind a picker
/// on a screen about an album. A tester put it plainly — the Book tab should be about
/// books. So the list moved to where trips already live, and what survived the move
/// is the only thing the Trips tab did not already have: the bar.
///
/// Collapsed by default and absent below two trips, for the same reason the archived
/// section works that way. Comparing one trip to itself is not a comparison, and a
/// permanently expanded second copy of the trip list is exactly the clutter that made
/// the old page confusing.
struct TripComparison: View {
    let summaries: [TripSummary]
    let currentTripID: UUID?

    @State private var expanded = false

    private var best: Int { summaries.map(\.statesFound).max() ?? 0 }

    var body: some View {
        if summaries.count > 1 {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Compare trips")
                            .font(.plates(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    ForEach(summaries) { summary in
                        TripSummaryRow(summary: summary,
                                       isCurrent: summary.id == currentTripID,
                                       best: best)
                    }

                    Text("Newest first. The bar compares states found.")
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - One row

struct TripSummaryRow: View {
    let summary: TripSummary
    let isCurrent: Bool
    let best: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.name)
                    .font(.plates(size: 15.5, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.route : Theme.ink)
                    .lineLimit(1)
                if isCurrent {
                    Image(systemName: "car.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.route)
                }
                Spacer()
                Text("\(summary.statesFound)")
                    .font(Theme.PlateFont.condensed(21))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("states")
                    .font(.plates(size: 10))
                    .foregroundStyle(Theme.inkMuted)
            }

            // Length relative to the best trip, so the comparison is visual before
            // anyone reads a number.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line).frame(height: 5)
                    Capsule().fill(isCurrent ? Theme.route : Theme.found)
                        .frame(width: best > 0
                               ? max(4, geo.size.width * CGFloat(summary.statesFound) / CGFloat(best))
                               : 4,
                               height: 5)
                }
            }
            .frame(height: 5)

            HStack(spacing: 10) {
                if let route = summary.route {
                    Label(route, systemImage: "arrow.triangle.turn.up.right.diamond")
                        .lineLimit(1)
                }
                Label("\(summary.platesFound) plates", systemImage: "square.grid.2x2")
                Label("\(summary.days)d", systemImage: "calendar")
                if let bf = summary.bestFind, let p = Plate.plate(for: bf.code) {
                    Label(p.code, systemImage: "sparkles")
                        .foregroundStyle(RarityTier.forRarity(bf.rarity).color)
                }
                Spacer(minLength: 0)
            }
            .font(.plates(size: 11))
            .foregroundStyle(Theme.inkMuted)
            .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.route : Theme.line,
                                  lineWidth: isCurrent ? 1.5 : 1))
        )
    }
}
