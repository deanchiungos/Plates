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
                // The same bar Finished and Archived use. This one had its own type
                // size, its own chevron on the far right and padding the others did
                // not have — three treatments of one control, within a thumb's width
                // of each other.
                DisclosureBar(symbol: "chart.bar.fill",
                              title: "Compare trips",
                              isOpen: expanded) { expanded.toggle() }

                if expanded {
                    ForEach(summaries) { summary in
                        TripSummaryRow(summary: summary,
                                       isCurrent: summary.id == currentTripID,
                                       best: best)
                    }

                    Text("Newest trip first. The longer the bar, the more states you found.")
                        .font(.plates(size: 11.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            // The same 18 the Finished and Archived sections carry. Those two and
            // this one are siblings in a `VStack(spacing: 10)`, so a section's own
            // top padding is the whole difference between the gaps — 4 here put this
            // bar 14pt below Archived while Archived sat 28pt below Finished, and
            // three evenly-weighted headers at two different spacings read as
            // Compare belonging to Archived rather than standing beside it.
            .padding(.top, 18)
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
                    // The best find wears its tier dot, not a sparkle. The dot is
                    // how rarity is drawn everywhere else in the app, and its
                    // colour already says how good the find was.
                    HStack(spacing: 4) {
                        Circle()
                            .fill(RarityTier.forRarity(bf.rarity).color)
                            .frame(width: 6, height: 6)
                        Text(p.code)
                    }
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
