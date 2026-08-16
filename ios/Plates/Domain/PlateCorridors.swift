import Foundation

/// The interstate backbone, and who drives in on it.
///
/// A licence plate arrives on a road, and the roads are not isotropic: I-80 runs
/// the full width of Wyoming and ends in Teaneck, New Jersey, while North Dakota's
/// traffic leaves on I-94 and I-29 and touches nothing in the northeast at any
/// distance. Standing on a rural interstate, much of what passes is through-traffic
/// funnelled from every state that road serves — which is why Wyoming plates are
/// ordinary on I-80 in Nebraska and Dakota plates are not, even though South
/// Dakota's population centre is the nearer of the two.
///
/// HAND-BUILT, and meant to be read. Each road is an ordered run of junction-city
/// coordinates — straight legs between junctions, which can sit tens of kilometres
/// off the real alignment on curved stretches; the 45 km detection tolerance below
/// absorbs most of that. `serves` lists the interstates a state's outbound traffic
/// actually leaves on, by the road map rather than by any dataset, because no free
/// dataset carries this. Anyone who knows the road system can check every line.
enum PlateCorridors {

    /// Which interstates pass within `tolerance` of a point.
    ///
    /// A point in town is "on" every road threading the city — that is not a bug:
    /// urban fixes drown the corridor term in local traffic anyway, which is the
    /// behaviour the additive formulation in `PlateRarity` relies on.
    static func roads(nearLat lat: Double, lon: Double) -> Set<String> {
        let p = project(lat, lon)
        var out = Set<String>()
        for (road, pts) in polylines {
            var i = 1
            while i < pts.count {
                if distance(p, toSegment: pts[i - 1], pts[i]) < tolerance {
                    out.insert(road); break
                }
                i += 1
            }
        }
        return out
    }

    /// The interstates a state's traffic leaves home on.
    static let serves: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]
        for line in packedServes.split(separator: "\n") {
            let f = line.split(separator: " ")
            guard f.count > 1 else { continue }
            out[String(f[0])] = Set(f.dropFirst().map(String.init))
        }
        return out
    }()

    private static let tolerance = 45.0

    // The same plane `PlateRarity` scores on, and deliberately not a second copy of
    // it: `tolerance` above is 45 km *on this map*, so the two cannot be allowed to
    // drift apart. See `GroundPlane`.
    private static func project(_ lat: Double, _ lon: Double) -> GroundPlane.Point {
        GroundPlane.project(lat, lon)
    }

    private static func distance(_ p: GroundPlane.Point,
                                 toSegment a: GroundPlane.Point,
                                 _ b: GroundPlane.Point) -> Double {
        GroundPlane.distance(from: p, toSegment: a, b)
    }

    private static let polylines: [String: [GroundPlane.Point]] = {
        var out: [String: [GroundPlane.Point]] = [:]
        for line in packedRoads.split(separator: "\n") {
            let f = line.split(separator: " ")
            guard f.count > 2 else { continue }
            out[String(f[0])] = f.dropFirst().compactMap { pair in
                let c = pair.split(separator: ",")
                guard c.count == 2, let la = Double(c[0]), let lo = Double(c[1])
                else { return nil }
                return project(la, lo)
            }
        }
        return out
    }()

    /// road lat,lon lat,lon … — junction cities in driving order.
    private static let packedRoads = """
I-10 34.05,-118.24 33.45,-112.07 32.22,-110.97 32.31,-106.78 31.76,-106.49 29.42,-98.49 29.76,-95.37 30.45,-91.19 29.95,-90.07 30.69,-88.04 30.42,-87.22 30.44,-84.28 30.33,-81.66
I-15 32.72,-117.16 36.17,-115.14 37.10,-113.58 40.76,-111.89 43.49,-112.03 46.00,-112.50 47.50,-111.30
I-20 31.42,-103.49 32.76,-97.33 32.78,-96.80 32.52,-93.75 32.30,-90.18 33.52,-86.80 33.75,-84.39 33.47,-81.97 34.20,-79.76
I-24 36.16,-86.78 35.05,-85.31
I-25 32.31,-106.78 35.08,-106.65 35.69,-105.94 37.17,-104.50 38.25,-104.61 39.74,-104.99 41.14,-104.82 42.85,-106.32 44.35,-106.70
I-26 35.60,-82.55 34.85,-82.40 34.00,-81.03 32.78,-79.93
I-27 35.22,-101.83 33.58,-101.86
I-29 39.10,-94.58 41.26,-95.94 43.55,-96.70 46.88,-96.79 47.93,-97.03 48.97,-97.24
I-30 32.78,-96.80 34.75,-92.29
I-35 27.51,-99.51 29.42,-98.49 30.27,-97.74 32.76,-97.33 32.78,-96.80 35.47,-97.52 37.69,-97.34 39.05,-95.68 39.10,-94.58 41.59,-93.62 43.65,-93.37 44.98,-93.27 46.79,-92.10
I-39 43.07,-89.40 40.12,-88.24
I-40 34.90,-117.02 34.85,-114.61 35.19,-114.05 35.20,-111.65 35.08,-106.65 35.22,-101.83 35.47,-97.52 35.39,-94.40 34.75,-92.29 35.15,-90.05 36.16,-86.78 35.96,-83.92 35.60,-82.55 36.10,-80.24 35.78,-78.64 34.23,-77.94
I-43 43.04,-87.91 44.51,-87.99
I-44 37.69,-97.34 35.47,-97.52 36.15,-95.99 37.21,-93.29 38.63,-90.20
I-45 32.78,-96.80 29.76,-95.37
I-49 32.52,-93.75 35.39,-94.40
I-5 32.72,-117.16 34.05,-118.24 37.34,-121.89 38.58,-121.49 40.59,-122.39 44.05,-123.09 45.52,-122.68 47.60,-122.30 48.75,-122.48
I-55 29.95,-90.07 32.30,-90.18 35.15,-90.05 38.63,-90.20 39.80,-89.64 41.88,-87.63
I-57 41.88,-87.63 40.12,-88.24 39.12,-88.55 37.08,-88.60
I-59 29.95,-90.07 33.52,-86.80 35.05,-85.31
I-64 38.63,-90.20 37.97,-87.56 38.25,-85.76 38.04,-84.50 38.35,-81.63 37.54,-77.44 36.85,-76.29
I-65 30.69,-88.04 32.37,-86.30 33.52,-86.80 36.16,-86.78 38.25,-85.76 39.77,-86.16 41.59,-87.35
I-69 39.77,-86.16 42.73,-84.56 42.96,-85.67
I-70 38.60,-112.58 38.99,-110.16 39.06,-108.55 39.74,-104.99 38.84,-97.61 39.05,-95.68 39.10,-94.58 38.95,-92.33 38.63,-90.20 39.12,-88.55 39.77,-86.16 39.96,-83.00 40.06,-80.72 40.17,-80.25 39.99,-78.24 39.64,-77.72 39.29,-76.61
I-71 38.25,-85.76 39.10,-84.51 39.96,-83.00 41.50,-81.69
I-72 39.80,-89.64 40.12,-88.24
I-74 41.52,-90.58 40.12,-88.24 39.77,-86.16
I-75 25.76,-80.19 27.95,-82.46 32.84,-83.63 33.75,-84.39 35.05,-85.31 35.96,-83.92 38.04,-84.50 39.10,-84.51 39.76,-84.19 41.65,-83.54 42.33,-83.05 46.50,-84.35
I-76 39.74,-104.99 41.12,-100.77
I-76e 39.95,-75.17 40.27,-76.88 40.44,-79.99 41.10,-80.65
I-77 34.00,-81.03 35.23,-80.84 36.10,-80.24 37.78,-81.19 38.35,-81.63 39.63,-79.96 41.50,-81.69
I-78 40.73,-74.17 40.27,-76.88
I-79 38.35,-81.63 39.63,-79.96 40.44,-79.99 42.13,-80.09
I-80 37.77,-122.42 38.58,-121.49 39.53,-119.81 40.76,-111.89 41.59,-109.20 41.79,-107.24 41.31,-105.59 41.14,-104.82 41.12,-100.77 40.81,-96.70 41.26,-95.94 41.59,-93.62 41.52,-90.58 41.88,-87.63 41.65,-83.54 41.50,-81.69 41.10,-80.65 41.20,-79.38 40.99,-75.19 40.73,-74.17
I-81 35.96,-83.92 37.27,-79.94 38.45,-78.87 39.64,-77.72 40.27,-76.88 41.41,-75.66 42.10,-75.91 43.05,-76.15
I-82 46.23,-119.09 46.60,-120.51
I-84 45.52,-122.68 43.60,-116.20 41.22,-111.97
I-84e 41.41,-75.66 41.76,-72.68
I-85 32.37,-86.30 33.75,-84.39 34.85,-82.40 35.23,-80.84 35.99,-78.90 37.54,-77.44
I-86 42.10,-75.91 42.13,-80.09
I-87 40.71,-74.01 42.65,-73.76
I-88 42.65,-73.76 42.10,-75.91
I-89 43.21,-71.54 43.65,-72.32 44.48,-73.21
I-90 47.60,-122.30 46.60,-120.51 47.66,-117.40 46.87,-113.99 46.00,-112.50 45.78,-108.50 44.80,-106.96 44.41,-103.51 44.08,-103.23 43.55,-96.70 43.65,-93.37 44.02,-92.47 43.07,-89.40 41.88,-87.63 41.65,-83.54 41.50,-81.69 42.13,-80.09 42.89,-78.88 43.05,-76.15 42.65,-73.76 42.10,-72.59 42.36,-71.06
I-91 41.31,-72.93 41.76,-72.68 42.10,-72.59 43.65,-72.32 44.42,-72.02
I-93 42.36,-71.06 43.21,-71.54
I-94 45.78,-108.50 46.81,-100.78 46.88,-96.79 44.98,-93.27 44.81,-91.50 43.07,-89.40 43.04,-87.91 41.88,-87.63 42.33,-83.05
I-95 25.76,-80.19 28.54,-81.38 30.33,-81.66 32.08,-81.09 34.20,-79.76 37.54,-77.44 38.90,-77.03 39.29,-76.61 39.95,-75.17 40.73,-74.17 40.71,-74.01 41.31,-72.93 41.82,-71.41 42.36,-71.06 43.66,-70.26 46.13,-67.84
"""

    /// state road road … — the interstates that state's traffic leaves on.
    private static let packedServes = """
AL I-65 I-20 I-10 I-59 I-85
AR I-40 I-30 I-49
AZ I-10 I-40
CA I-5 I-80 I-10 I-15 I-40
CO I-70 I-25 I-76
CT I-95 I-91 I-84e
DC I-95
DE I-95
FL I-95 I-75 I-10
GA I-75 I-20 I-85 I-95
IA I-80 I-35
ID I-84 I-15 I-90
IL I-80 I-55 I-57 I-70 I-74 I-39
IN I-70 I-65 I-80 I-69 I-74
KS I-70 I-35 I-44
KY I-65 I-64 I-75
LA I-10 I-20 I-55 I-49
MA I-90 I-95 I-91 I-93
MD I-95 I-70
ME I-95
MI I-94 I-75 I-69
MN I-94 I-35 I-90
MO I-70 I-44 I-55 I-35 I-64
MS I-55 I-20 I-10 I-59
MT I-90 I-94 I-15
NC I-40 I-95 I-85 I-77 I-26
ND I-94 I-29
NE I-80 I-29 I-76
NH I-93 I-89 I-95
NJ I-95 I-80 I-78
NM I-40 I-25 I-10
NV I-80 I-15
NY I-90 I-95 I-87 I-81 I-86 I-88
OH I-70 I-75 I-80 I-71 I-77
OK I-40 I-35 I-44
OR I-5 I-84
PA I-80 I-76e I-81 I-95 I-79 I-78
RI I-95
SC I-95 I-26 I-85 I-20 I-77
SD I-90 I-29
TN I-40 I-65 I-75 I-24 I-59
TX I-10 I-35 I-20 I-45 I-40 I-27 I-30
UT I-15 I-80 I-70 I-84
VA I-95 I-81 I-64 I-85 I-77
VT I-89 I-91
WA I-5 I-90 I-82
WI I-94 I-90 I-43 I-39
WV I-64 I-77 I-79 I-70
WY I-80 I-25 I-90
"""
}
