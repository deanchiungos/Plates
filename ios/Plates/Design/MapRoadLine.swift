import SwiftUI

/// The road drawn over a map snapshot.
///
/// White casing under the color, which is the trick every map app uses so a line
/// stays readable where it crosses a motorway or a coast. Both maps in this app draw
/// it — the trip editor's preview and the poster's strip — and both wrote out the
/// same two-stroke path and the same dashed fallback, differing only in how thick
/// the strokes were.
///
/// The fallback is the part worth keeping honest: with no route, a *solid* line
/// would assert a road that does not exist. Honolulu to anywhere has no driving
/// directions, and that is the normal answer rather than a failure, so the two ends
/// are joined by a dash that reads as "these are the ends" instead of "this is the
/// way".
///
/// Takes points already projected into the snapshot's space rather than
/// coordinates, because the two callers project at different moments: the editor has
/// a live `MKMapSnapshotter.Snapshot` in hand, and the poster baked its points at
/// render time and no longer has one.
struct MapRoadLine: View {
    /// The road, projected. Fewer than two points means there is no road.
    let points: [CGPoint]
    /// The two ends, for the dashed fallback.
    let start: CGPoint
    let end: CGPoint

    /// The colored line's width. The casing under it is drawn proportionally, so one
    /// number sets the pair and they cannot drift apart.
    var width: CGFloat = 2.6
    var dashWidth: CGFloat = 2.4
    var dash: [CGFloat] = [5, 5]

    private var casing: CGFloat { width * 1.92 }

    var body: some View {
        if points.count > 1 {
            let path = Path { p in
                p.move(to: points[0])
                for point in points.dropFirst() { p.addLine(to: point) }
            }
            path.stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: casing, lineCap: .round, lineJoin: .round))
            path.stroke(Theme.route,
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        } else {
            Path { p in
                p.move(to: start)
                p.addLine(to: end)
            }
            .stroke(Theme.route.opacity(0.55),
                    style: StrokeStyle(lineWidth: dashWidth, lineCap: .round, dash: dash))
        }
    }
}
