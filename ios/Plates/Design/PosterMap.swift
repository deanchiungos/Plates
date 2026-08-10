import CoreLocation
import MapKit
import SwiftUI

/// The road a trip took, flattened to something a poster can hold.
///
/// A snapshot rather than a `Map`, for the same reason `RouteMap` uses one — and
/// here it is not merely preferable but the only option. `ImageRenderer` draws
/// outside the view hierarchy: it runs no `.task`, waits for nothing async, and a
/// live `Map` inside it renders as a blank rectangle. So the picture has to exist
/// *before* the poster is laid out, which is why this is fetched first and handed in
/// finished.
struct PosterRoute {
    let image: UIImage
    /// Where the two ends landed in the snapshot's own pixel space, so the markers
    /// can be put exactly on them.
    let startPoint: CGPoint
    let endPoint: CGPoint
    /// The road itself, already projected. Empty when MapKit knew no route between
    /// the two places, which is the ordinary answer for anywhere reached by ferry.
    let routePoints: [CGPoint]
    let size: CGSize

    @MainActor
    static func make(start: CLLocationCoordinate2D,
                     end: CLLocationCoordinate2D,
                     size: CGSize) async -> PosterRoute? {
        // Directions first, so the frame can be drawn around the road rather than
        // around its two ends — a route detouring north around a mountain range
        // would otherwise run off the top of a map framed on the endpoints.
        let road = await route(from: start, to: end)
        let framed = road.isEmpty ? [start, end] : road

        let options = MKMapSnapshotter.Options()
        options.region = region(fitting: framed)
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        // Pinned light. The poster is cream and the app is light-only; a dark map
        // dropped into it would read as a rendering fault.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { cont in
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                cont.resume(returning: snapshot)
            }
        }
        guard let snapshot else { return nil }

        return PosterRoute(image: snapshot.image,
                           startPoint: snapshot.point(for: start),
                           endPoint: snapshot.point(for: end),
                           routePoints: road.map { snapshot.point(for: $0) },
                           size: size)
    }

    /// The same asymmetric margin `RouteMap` uses: a strip this shape has MapKit
    /// grow the latitude span to match the aspect ratio, so vertical padding comes
    /// free and only the horizontal has to be asked for.
    private static func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: coords.first ?? .init(),
                                      span: .init(latitudeDelta: 4, longitudeDelta: 4))
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: min(max((maxLat - minLat) * 1.35, 0.6), 120),
                        longitudeDelta: min(max((maxLon - minLon) * 1.25, 0.6), 160)))
    }

    /// Nil-safe by design: no route is a legitimate answer, not a failure, so the
    /// caller draws a dashed line between the ends instead of nothing at all.
    private static func route(from start: CLLocationCoordinate2D,
                              to end: CLLocationCoordinate2D) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        guard let response = try? await MKDirections(request: request).calculate(),
              let line = response.routes.first?.polyline else { return [] }

        var coords = [CLLocationCoordinate2D](repeating: .init(),
                                              count: line.pointCount)
        line.getCoordinates(&coords, range: NSRange(location: 0, length: line.pointCount))
        // Thinned before it is drawn. A cross-country route is thousands of points,
        // and at poster scale every one past a few hundred is sub-pixel work that
        // only slows the render down.
        let stride = max(1, coords.count / 240)
        return coords.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
}

// MARK: - Drawing it

/// The map strip on a trip's poster: the road, and a plate at each end of it.
struct PosterMapStrip: View {
    let route: PosterRoute
    let startLabel: String?
    let endLabel: String?

    var body: some View {
        ZStack {
            Image(uiImage: route.image)
                .resizable()
                .frame(width: route.size.width, height: route.size.height)

            road

            marker(symbol: "flag.fill", at: route.startPoint)
            marker(symbol: "flag.checkered", at: route.endPoint)
        }
        .frame(width: route.size.width, height: route.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    /// White casing under the colour, the trick every map app uses so a line stays
    /// readable where it crosses a motorway or a coast.
    @ViewBuilder
    private var road: some View {
        if route.routePoints.count > 1 {
            let path = Path { p in
                p.move(to: route.routePoints[0])
                for point in route.routePoints.dropFirst() { p.addLine(to: point) }
            }
            path.stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            path.stroke(Theme.route,
                        style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        } else {
            // Dashed, because a solid line would assert a road that does not exist.
            Path { p in
                p.move(to: route.startPoint)
                p.addLine(to: route.endPoint)
            }
            .stroke(Theme.route.opacity(0.6),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 7]))
        }
    }

    /// A marker shaped like a plate, because on this poster everything else is.
    ///
    /// A flag for the start and a chequered one for the end, rather than the place
    /// names: at 34pt across, "Newark" is unreadable and "N" is a riddle. The names
    /// are already printed under the title.
    private func marker(symbol: String, at point: CGPoint) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 34, height: 34 / Theme.tileAspect)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.75), lineWidth: 1.5)
            )
            .shadow(color: Theme.ink.opacity(0.35), radius: 3, y: 1)
            .position(point)
    }
}
