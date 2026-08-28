import Foundation

/// The flat map everything in this app measures on.
///
/// Two files need to turn latitude and longitude into kilometres and then ask how far
/// a point is from a road: `PlateRarity`, which scores a plate against the route being
/// driven, and `PlateCorridors`, which decides whether a state's traffic uses a given
/// interstate. They had a copy each — the same projection, the same reference
/// latitude, the same clamped point-to-segment distance — with a comment on the second
/// one saying it was restated so the file could stand alone.
///
/// Standing alone is not worth it here. The corridor tolerance is 45 km, and that
/// number is calibrated against *this* plane: retune the reference latitude in one
/// copy and corridor detection silently starts measuring on a different map from the
/// one its threshold was chosen for. Nothing would fail; some states would quietly
/// stop being served by roads they are on.
enum GroundPlane {

    typealias Point = (x: Double, y: Double)

    /// 40°N — Philadelphia, Denver, Salt Lake City — the middle of the band this game
    /// is actually played in.
    static let referenceLatitude = 40.0

    /// Kilometres per degree of longitude, taken at that one fixed latitude.
    private static let kmPerLon = cos(referenceLatitude * Double.pi / 180) * 111.0

    /// Latitude and longitude onto a flat plane, in kilometres.
    ///
    /// **The longitude scale has to be a constant.** It used to be `cos(lat)` of each
    /// point's *own* latitude, which is not a projection at all: it gives every point
    /// its own x-axis. Because the whole continent sits at negative longitude, that
    /// dragged northern regions east — toward the Atlantic seaboard — and pushed
    /// southern ones west, and the error grew with the longitude itself. Measured
    /// from Newark it made North Dakota 1,467 km away instead of 2,181, Manitoba
    /// 1,241 instead of 2,065, Saskatchewan 1,592 instead of 2,690, Washington 3,027
    /// instead of 3,893 — while Texas came out 3,203 instead of 2,346 and Florida
    /// 2,218 instead of 1,538. Errors of 30 to 45 per cent, systematically signed by
    /// latitude.
    ///
    /// The model then did exactly what it was told. The empty northern states looked
    /// close and scored common — North Dakota, with 211,000 cars, outranked
    /// Washington's 2.5 million — while Texas and Florida looked far and scored rare.
    /// It read as the fleet term being broken. It was the ruler.
    ///
    /// One reference latitude makes this a real equirectangular projection: distances
    /// are uniformly scaled rather than individually distorted, and the residual
    /// error over the populated band runs to about ±9%, which a ten-step ranking does
    /// not notice. It stays plane geometry, so the point-to-segment distance below is
    /// ordinary algebra.
    static func project(_ lat: Double, _ lon: Double) -> Point {
        (x: lon * kmPerLon, y: lat * 111.0)
    }

    /// Nearest approach from a point to one leg, in kilometres.
    ///
    /// Clamped to the leg, so a region beyond either end measures from that end
    /// rather than from an imaginary extension of the road.
    static func distance(from p: Point, toSegment a: Point, _ b: Point) -> Double {
        let vx = b.x - a.x, vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
    }
}
