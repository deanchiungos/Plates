#if DEBUG
import SwiftUI

/// Launch with `-bench` to time what a screenful of plates actually costs.
///
/// Scrolling performance is the thing everyone guesses at and nobody measures.
/// `ImageRenderer` forces a real synchronous render — body evaluation, layout,
/// and rasterisation of every layer, mask and blur — so it exercises the same
/// work a scroll frame does, on demand and without needing to drive the UI.
///
/// It is not a frame-rate figure: no GPU compositing, no cell recycling. It is
/// a comparable number, which is what an optimisation pass needs. Run it before
/// and after a change; the ratio is the honest part.
struct PlateBench: View {
    @State private var report = "running…"

    var body: some View {
        ScrollView {
            Text(report)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task { report = Self.run() }
    }

    /// A screenful: the adaptive grid fits 4 across on a phone, and about six
    /// rows are on screen at once. Timing 24 tiles matches what one scroll
    /// frame is actually asked to produce.
    private static let visible = 24
    private static let reps = 30

    @MainActor
    static func run() -> String {
        var lines = ["tiles: \(visible)   reps: \(reps)", ""]

        lines.append(measure("found (artwork)") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
        })
        lines.append(measure("unfound (paper)") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: false)
        })
        // The four haloed plates are the only ones still paying for a blur.
        lines.append(measure("haloed only") { _ in
            PlateTile(plate: Plate.plate(for: "NM")!, isFound: true)
        })
        lines.append(measure("background only") { i in
            let p = Plate.all[i % Plate.all.count]
            return PlateBackground(code: p.code,
                                   style: PlateStyle.style(for: p.code) ?? .fallback)
                .aspectRatio(Theme.tileAspect, contentMode: .fit)
        })
        lines.append(measure("lettering only") { i in
            let p = Plate.all[i % Plate.all.count]
            return PlateLettering(code: p.code,
                                  style: PlateStyle.style(for: p.code) ?? .fallback,
                                  name: p.short)
                .aspectRatio(Theme.tileAspect, contentMode: .fit)
        })

        // What GameScreen actually puts in the grid. The search highlight is
        // wrapped round every cell whether or not a search is running, so these
        // isolate what an idle, non-matching, non-celebrating tile still pays.
        lines.append("")
        lines.append(measure("+ bg shadow") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
                .background(
                    RoundedRectangle(cornerRadius: Theme.tileRadius + 3, style: .continuous)
                        .fill(Theme.paint.opacity(0))
                        .shadow(color: Theme.paint.opacity(0), radius: 4)
                        .padding(-3)
                )
        })
        lines.append(measure("+ saturation") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
                .saturation(1)
        })
        lines.append(measure("+ opacity") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
                .opacity(1)
        })
        lines.append(measure("+ scaleEffect") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
                .scaleEffect(1)
        })
        lines.append(measure("full grid cell") { i in
            PlateTile(plate: Plate.all[i % Plate.all.count], isFound: true)
                .background(
                    RoundedRectangle(cornerRadius: Theme.tileRadius + 3, style: .continuous)
                        .fill(Theme.paint.opacity(0))
                        .shadow(color: Theme.paint.opacity(0), radius: 4)
                        .padding(-3)
                )
                .scaleEffect(1)
                .opacity(1)
                .saturation(1)
        })
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func measure<V: View>(_ label: String,
                                         @ViewBuilder _ make: @escaping (Int) -> V) -> String {
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(Theme.tileMinWidth), spacing: 8),
                          count: 4),
            spacing: 8
        ) {
            ForEach(0..<visible, id: \.self) { make($0) }
        }
        .frame(width: (Theme.tileMinWidth + 8) * 4)

        var samples: [Double] = []
        for _ in 0..<reps {
            let renderer = ImageRenderer(content: grid)
            renderer.scale = 3
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = renderer.uiImage
            samples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let best = samples.first ?? 0
        let out = String(format: "%-18@  median %6.1f ms   best %6.1f ms   (%.2f ms/tile)",
                        label as NSString, median, best, median / Double(visible))
        print("BENCH  " + out)
        return out
    }
}
#endif
