import Foundation

/// Location-aware rarity.
///
/// A plate's rarity is not a property of the plate — it is a property of the plate
/// *and where you are standing*. New Jersey plates are wallpaper in Newark and a
/// find in Sacramento. The static `Plate.points` values could only ever encode one
/// vantage point, and they encoded the Northeast (NJ 1, NY 1, CA 2), so a player in
/// California was scoring against someone else's road trip.
///
/// The model is a standard gravity formulation:
///
///     weight(region | route) = fleet^0.85 x reach x exp(-distance_km / 600)
///
/// The regions are then ranked by that weight and dealt into ten fixed-size bands,
/// so rarity is a *position* in the ordering rather than a raw log-likelihood. The
/// model decides the order, which is the part the data supports; the bands decide
/// how many plates land in each tier, which is a game-design decision and is stated
/// as one in `buckets`.
///
/// **Sources.** Registrations are 2024, private only. United States: FHWA Highway
/// Statistics table MV-1, via `data.transportation.gov` resource `4dra-vxq7` — a US
/// government work, public domain, no attribution owed. Canada: Statistics Canada
/// table 23-10-0308-01, all fuel types.
///
/// **The Canadian half carries a licence obligation and it is not discharged in this
/// repository.** The Statistics Canada Open Licence requires an acknowledgement of
/// source in anything built on the data, in a prescribed form. This app is a
/// value-added product — it turns registrations into a ranking rather than
/// republishing the table — so the wording it owes is:
///
///     Adapted from Statistics Canada, Vehicle registrations, by type of vehicle
///     and fuel type, Table 23-10-0308-01, 2024. This does not constitute an
///     endorsement by Statistics Canada of this product.
///
/// That notice lives in the **App Store description**, which is not in version
/// control — so it can be deleted by anyone rewriting the listing without ever
/// touching this repository, and nothing here will fail. If you are editing the
/// description, the paragraph above has to survive. It used to sit in a Settings card
/// and was removed when Settings became controls-only; the licence does not care
/// where it appears, only that it does.
///
/// **Registrations are not journeys.** This is the model's load-bearing assumption
/// and it should be stated plainly: MV-1 counts where a car is garaged, not where it
/// drives. No free dataset of interstate passenger-vehicle flows exists — the freight
/// framework is freight, the national travel survey coarsens geography past
/// usefulness, the mobility datasets are discontinued, and the commercial ones cannot
/// be redistributed. So the distance term is doing all the work of turning "cars that
/// exist" into "cars you might see", and there is no measurement of vehicles moving
/// behind it.
///
/// **Which means the decay scale is tuned, not derived**, and `decayScale` says so.
/// An earlier draft cited a distance-decay elasticity from a tourism-flow
/// meta-analysis, but those flows include flying and that formulation — a softened
/// power law — is not the one in the code any more. Nothing published measures the
/// quantity this actually needs.
///
/// **What this is not.** It is a defensible *ordering*, not a probability. Turning
/// it into "3.2% chance you will see a Montana plate" would require calibration
/// against observed sightings, and no such dataset has ever been published. The
/// number would be invented. So this ranks; it never claims a percentage.
enum PlateRarity {

    struct Origin {
        /// Private automobiles. The default fleet, and the conservative one.
        let autos: Int

        /// Private light trucks — which in FHWA's classification means pickups,
        /// SUVs, vans and minivans, not just haulage. Nationally there are 187M of
        /// these against 96M autos, so on the road they are the majority of what you
        /// actually see.
        ///
        /// Off by default all the same, because the category is inflated by
        /// registration-domicile schemes in exactly the states where the distortion
        /// hurts most: counting them puts Montana at 1.77 registered vehicles per
        /// capita, against 0.46 for autos alone. Neither choice is right for
        /// everyone, which is why it is a per-trip switch rather than a decision
        /// made on the player's behalf.
        let trucks: Int

        let lat: Double
        let lon: Double
        /// Share of that fleet that can plausibly reach a continental road trip.
        ///
        /// The one hand-set term in the model, and it exists because great-circle
        /// distance cannot see water or borders. Hawaii is 3,800 km from California
        /// and Puerto Rico 1,600 km from Florida, but neither can be driven from
        /// anywhere. Canadian plates carry a flat 0.30 crossing factor: most
        /// Canadian cars never enter the US, and those that do stay near the border
        /// — without any penalty the model ranked Ontario the second-commonest plate
        /// on a Newark-to-San Diego drive, which is plainly false.
        ///
        /// It started at 0.10, which overcorrected: it buried all thirteen provinces
        /// so deep that they took eleven of the fifteen legendary slots and crowded
        /// the American states a player is actually driving past out of the top
        /// tiers. At 0.30 the far west reaches legendary on its own merits.
        let reach: Double
    }

    /// 2024 registrations, approximate population-weighted centres, reach factors.
    ///
    /// Centres are population-weighted rather than geographic on purpose: New York's
    /// geographic centre is 380 km from Newark but its population centre is 60 km,
    /// and proximity to where the cars actually are is the entire model. They are
    /// approximate — Nevada's sits at Las Vegas, so Reno traffic reads a little
    /// rarer from Sacramento than it should.
    static let origins: [String: Origin] = [
        "AB": .init(autos: 834819, trucks: 2371800, lat: 52.3, lon: -113.8, reach: 0.3),
        "AK": .init(autos: 120421, trucks: 514116, lat: 61.37, lon: -149.5, reach: 0.12),
        "AL": .init(autos: 1932886, trucks: 3572635, lat: 32.79, lon: -86.83, reach: 1),
        "AR": .init(autos: 892704, trucks: 2292346, lat: 34.85, lon: -92.4, reach: 1),
        "AZ": .init(autos: 2254643, trucks: 4024184, lat: 33.35, lon: -112, reach: 1),
        "BC": .init(autos: 1167996, trucks: 2248538, lat: 49.4, lon: -123, reach: 0.3),
        "CA": .init(autos: 12737763, trucks: 16752902, lat: 35.46, lon: -119.3, reach: 1),
        "CO": .init(autos: 1341494, trucks: 3684600, lat: 39.35, lon: -104.9, reach: 1),
        "CT": .init(autos: 1028325, trucks: 1684267, lat: 41.6, lon: -72.75, reach: 1),
        "DC": .init(autos: 138559, trucks: 129193, lat: 38.9, lon: -77.03, reach: 1),
        "DE": .init(autos: 146701, trucks: 266034, lat: 39.35, lon: -75.55, reach: 1),
        "FL": .init(autos: 7113843, trucks: 11617475, lat: 28.3, lon: -81.6, reach: 1),
        "GA": .init(autos: 3154970, trucks: 5738067, lat: 33.6, lon: -84.1, reach: 1),
        "HI": .init(autos: 415330, trucks: 804155, lat: 21.3, lon: -157.85, reach: 0.02),
        "IA": .init(autos: 998101, trucks: 2621876, lat: 41.7, lon: -93.4, reach: 1),
        "ID": .init(autos: 504204, trucks: 1419807, lat: 43.8, lon: -115.4, reach: 1),
        "IL": .init(autos: 3443638, trucks: 6580751, lat: 41.35, lon: -88.4, reach: 1),
        "IN": .init(autos: 1752726, trucks: 3981452, lat: 39.9, lon: -86.3, reach: 1),
        "KS": .init(autos: 592793, trucks: 1309881, lat: 38.5, lon: -97, reach: 1),
        "KY": .init(autos: 1431848, trucks: 2914155, lat: 37.8, lon: -85.3, reach: 1),
        "LA": .init(autos: 1337616, trucks: 2969301, lat: 30.8, lon: -91.6, reach: 1),
        "MA": .init(autos: 1690199, trucks: 3194932, lat: 42.35, lon: -71.5, reach: 1),
        "MB": .init(autos: 245719, trucks: 625467, lat: 49.9, lon: -97.2, reach: 0.3),
        "MD": .init(autos: 1882459, trucks: 2893645, lat: 39.2, lon: -76.8, reach: 1),
        "ME": .init(autos: 305020, trucks: 823735, lat: 44.4, lon: -69.7, reach: 1),
        "MI": .init(autos: 2493266, trucks: 6850142, lat: 43.1, lon: -84.5, reach: 1),
        "MN": .init(autos: 1592071, trucks: 4040621, lat: 45.1, lon: -93.5, reach: 1),
        "MO": .init(autos: 1644583, trucks: 3611893, lat: 38.5, lon: -92.4, reach: 1),
        "MS": .init(autos: 754721, trucks: 1411201, lat: 32.7, lon: -89.8, reach: 1),
        "MT": .init(autos: 524624, trucks: 1490120, lat: 46.9, lon: -111, reach: 1),
        "NB": .init(autos: 192945, trucks: 375079, lat: 46, lon: -66.2, reach: 0.3),
        "NC": .init(autos: 2963141, trucks: 5546131, lat: 35.5, lon: -79.6, reach: 1),
        "ND": .init(autos: 211559, trucks: 798031, lat: 47.4, lon: -99.9, reach: 1),
        "NE": .init(autos: 551466, trucks: 1343041, lat: 41.1, lon: -97.2, reach: 1),
        "NH": .init(autos: 387846, trucks: 902330, lat: 43.1, lon: -71.5, reach: 1),
        "NJ": .init(autos: 2251730, trucks: 3762020, lat: 40.5, lon: -74.4, reach: 1),
        "NL": .init(autos: 98333, trucks: 258660, lat: 47.8, lon: -55, reach: 0.165),
        "NM": .init(autos: 571192, trucks: 1230750, lat: 34.8, lon: -106.3, reach: 1),
        "NS": .init(autos: 251174, trucks: 414569, lat: 44.9, lon: -63.3, reach: 0.3),
        "NT": .init(autos: 3355, trucks: 20174, lat: 62.5, lon: -114.4, reach: 0.15),
        "NU": .init(autos: 182, trucks: 4321, lat: 63.7, lon: -68.5, reach: 0.015),
        "NV": .init(autos: 832098, trucks: 1427942, lat: 36.5, lon: -115.4, reach: 1),
        "NY": .init(autos: 6452828, trucks: 13469243, lat: 41.2, lon: -74.1, reach: 1),
        "OH": .init(autos: 3767531, trucks: 7022748, lat: 40.2, lon: -82.8, reach: 1),
        "OK": .init(autos: 1055607, trucks: 2488103, lat: 35.4, lon: -97.3, reach: 1),
        "ON": .init(autos: 3188997, trucks: 5616959, lat: 43.9, lon: -79.5, reach: 0.3),
        "OR": .init(autos: 1291044, trucks: 2741416, lat: 44.9, lon: -122.9, reach: 1),
        "PA": .init(autos: 3331835, trucks: 6753528, lat: 40.4, lon: -77, reach: 1),
        "PE": .init(autos: 40285, trucks: 69414, lat: 46.3, lon: -63.2, reach: 0.255),
        "PR": .init(autos: 1300000, trucks: 900000, lat: 18.22, lon: -66.4, reach: 0.008),
        "QC": .init(autos: 2367995, trucks: 3265933, lat: 45.8, lon: -73.3, reach: 0.3),
        "RI": .init(autos: 304190, trucks: 494038, lat: 41.7, lon: -71.5, reach: 1),
        "SC": .init(autos: 1659552, trucks: 3086803, lat: 34, lon: -80.7, reach: 1),
        "SD": .init(autos: 275993, trucks: 931133, lat: 44.2, lon: -98.6, reach: 1),
        "SK": .init(autos: 191946, trucks: 656116, lat: 51.5, lon: -105.5, reach: 0.3),
        "TN": .init(autos: 2211560, trucks: 4604748, lat: 35.8, lon: -86.4, reach: 1),
        "TX": .init(autos: 7184055, trucks: 15701836, lat: 31.1, lon: -97.4, reach: 1),
        "UT": .init(autos: 952444, trucks: 1930442, lat: 40.4, lon: -111.9, reach: 1),
        "VA": .init(autos: 2794568, trucks: 4844718, lat: 37.9, lon: -77.6, reach: 1),
        "VT": .init(autos: 162650, trucks: 468644, lat: 44.1, lon: -72.8, reach: 1),
        "WA": .init(autos: 2476547, trucks: 4637317, lat: 47.4, lon: -122.1, reach: 1),
        "WI": .init(autos: 1594530, trucks: 3836626, lat: 43.6, lon: -89, reach: 1),
        "WV": .init(autos: 391085, trucks: 1011669, lat: 38.8, lon: -80.6, reach: 1),
        "WY": .init(autos: 157686, trucks: 644502, lat: 42.9, lon: -106.5, reach: 1),
        "YT": .init(autos: 7804, trucks: 27751, lat: 60.8, lon: -135, reach: 0.15),
    ]

    // MARK: - Model constants

    /// Fleet size enters slightly sub-linearly. Damping the mass term is standard in
    /// gravity models: a pure count lets California's 12.7 million cars — one in
    /// every seven and a half in the country — pull hard on every route in the
    /// catalogue at once.
    ///
    /// It is a light hand, and it should stay one. This was doing far more work than
    /// it looked like while `project` was mismeasuring distance, because it was the
    /// only thing standing between a big fleet and the top of every ranking. With the
    /// ruler fixed, moving it to a neutral 1.0 changes two regions from Newark and
    /// neither of them meaningfully — which is the sign that the mass term is now
    /// carrying its own weight and not covering for anything else.
    private static let fleetExponent = 0.85

    /// Exponential decay, not a power law, with an e-fold every 600 km.
    ///
    /// The 0.8 power law used before came from tourism-flow studies — and those
    /// flows include flying. A licence plate can only arrive by road, where the
    /// cost of another thousand miles is real and does not flatten out. Negative
    /// exponential is one of the standard friction-factor forms in trip
    /// distribution, and it bites far harder at continental range.
    ///
    /// **600, down from 900.** The scale length is a design choice rather than a
    /// measurement — nobody has published how passenger-car sightings decay with
    /// distance — so the honest way to set it is by what it produces, and at 900 km
    /// it produced a specific, visible wrong answer: from Newark, Washington State
    /// came out *rare*, the same tier as Delaware, DC, Maine and Vermont, none of
    /// them more than a day's drive from the start. A parameter that cannot tell a
    /// neighbour from the far coast is not describing road distance at all.
    ///
    /// 600 km is still a day's driving, and it costs a plate roughly 600x over the
    /// 3,900 km to Seattle where 900 km cost it 75x.
    ///
    /// Worth knowing that this was only ever half the story. The other half was that
    /// `project` had the distances themselves wrong by up to 45%, so some of what
    /// this parameter was tuned against was never real. It survived the fix — 600 and
    /// 700 now produce the same tiers for every region that prompted the change — but
    /// it was set for partly the wrong reason, and should be re-derived rather than
    /// defended if it ever needs to move again.
    private static let decayScale = 600.0

    /// How many regions land on each rarity value, 1 through 10.
    ///
    /// The old scale was a fixed multiple of the log-likelihood, and it was anchored
    /// by Nunavut — 182 cars behind a 0.005 reach factor, nearly eight decades below
    /// the commonest plate. That one absurd outlier stretched the scale so far that
    /// all fifty states were squashed into 1 through 6: the entire Mountain West
    /// came out "rare", Washington came out "uncommon", and nothing but Alaska and
    /// Hawaii could ever reach the top.
    ///
    /// Assigning by rank instead fixes the distribution by construction. The model
    /// still decides the *order* — that part is data — but the ten steps are spread
    /// across the plates that actually exist rather than across a range defined by
    /// the emptiest territory in North America.
    /// Top-heavy on purpose, and deliberately not a pyramid — an inverted one.
    ///
    /// A collecting game is not a loot table. Almost every plate a player *wants* is
    /// one they do not have, so weighting the bands toward the top is what makes the
    /// grid feel worth working through — a strict pyramid left the entire middle of
    /// the country reading "uncommon", which is true and boring.
    ///
    /// So the bottom two bands hold 16 plates between them where they once held 22,
    /// and most of what leaves them lands in rare or legendary. From Newark: 6
    /// common, 10 uncommon, 15 rare, 14 epic, 20 legendary.
    ///
    /// **Epic is the one band that is deliberately not fattened.** A strictly
    /// ascending ramp — every step one wider than the last — was tried, and it put
    /// 17 regions in epic, which on the rarity map is a slab of violet across the
    /// whole middle of the country and on the grid is a tier that stops meaning
    /// anything. The four that came back out of it from Newark are Vermont, Iowa,
    /// Missouri and Alabama, none of which is an epic find from New Jersey. Epic
    /// should be the far half of the continent and nothing nearer.
    ///
    /// Twenty legendary plates sounds like a lot until you read the list from a
    /// New Jersey driveway — Hawaii, Alaska, Nunavut, Yukon, Newfoundland, P.E.I.,
    /// Nevada, Arizona, New Mexico, British Columbia, Idaho, Wyoming. None of those
    /// is going past the window this afternoon.
    ///
    /// Nothing here changes the *order*, which is the part the data supports. The
    /// bands are a game-design decision and are stated as one.
    private static let buckets = [2, 4, 5, 5, 7, 8, 7, 7, 10, 10]   // sums to 65

    // MARK: - Route

    /// Everything the model needs from a trip. A trip with both ends set scores
    /// against the whole line between them, so a Newark-to-San Diego drive treats
    /// New Jersey *and* California as home turf rather than picking Kansas — the
    /// midpoint — as the centre of the world.
    ///
    /// `includeTrucks` rides along here rather than being a separate argument so
    /// that it is part of the memoisation key: flipping the switch has to produce a
    /// different table, not a stale cached one.
    struct Route: Hashable {
        let oLat: Double
        let oLon: Double
        let dLat: Double?
        let dLon: Double?

        /// Where the car is now, if the trip is tracking. Quantised on the way in.
        var currentLat: Double?
        var currentLon: Double?

        var includeTrucks: Bool = false

        /// Rounded to a quarter of a degree — roughly 25 km — before it is stored.
        ///
        /// Two reasons, both necessary. `table(for:)` memoises against this struct,
        /// so an unrounded coordinate would mint a fresh cache entry on every GPS
        /// tick and recompute 65 weights each time. And rarity that changed every
        /// few hundred metres would flicker between tiers while you sat at a set of
        /// lights. Nothing about a continental-scale ranking is meaningful at
        /// finer resolution than this.
        static func quantise(_ value: Double) -> Double {
            (value * 4).rounded() / 4
        }

        init(oLat: Double, oLon: Double,
             dLat: Double? = nil, dLon: Double? = nil,
             currentLat: Double? = nil, currentLon: Double? = nil,
             includeTrucks: Bool = false) {
            self.oLat = oLat
            self.oLon = oLon
            self.dLat = dLat
            self.dLon = dLon
            self.currentLat = currentLat.map(Self.quantise)
            self.currentLon = currentLon.map(Self.quantise)
            self.includeTrucks = includeTrucks
        }
    }

    // MARK: - Scoring

    /// Rarity 1 (wallpaper) to 10 (you will tell people about it), for every region
    /// at once. Computed as a set because the scale is relative: a region's rarity
    /// only means anything against the commonest plate on the same route.
    static func table(for route: Route) -> [String: Int] {
        if let cached = cache[route] { return cached }

        var weights: [String: Double] = [:]
        for (code, origin) in origins {
            let fleet = Double(origin.autos + (route.includeTrucks ? origin.trucks : 0))
            let d = distance(from: origin, to: route)
            weights[code] = pow(fleet, fleetExponent) * origin.reach
                * exp(-d / decayScale)
        }

        let result = ranked(by: weights)
        // Driving across a continent mints a new quantised position every ~25 km, so
        // the memo has to be bounded or it grows for the length of the trip.
        if cache.count > 40 { cache.removeAll() }
        cache[route] = result
        return result
    }

    // MARK: - Mythic

    /// The rarity value nothing can reach by ranking. See `RarityTier.mythic`.
    static let mythicValue = buckets.count + 1

    /// Mythic wherever you are standing.
    ///
    /// Not a slice of the ranking, which is the point. Every other tier is "whatever
    /// happens to land in these positions from here", so its membership changes with
    /// the route — and a top tier that means something different in Denver than in
    /// Boston cannot be a thing anybody brags about. These six are the regions the
    /// model puts at the top from *everywhere*: run it from twelve cities spread
    /// across the country and rank all 65 regions from each, and these never leave
    /// the top eight. They are also, not coincidentally, the six you cannot drive to.
    ///
    /// Deliberately two US states and not three. Hawaii sits at median rank 2 and
    /// Alaska at 4; the next state is Vermont at 15, which is two hours from Boston.
    /// Everything below Alaska is rare for being *small* rather than unreachable,
    /// which is a different thing and is what legendary already says.
    static let mythicAlways: Set<String> = ["NU", "NT", "YT", "AK", "HI", "PR"]

    /// The seventh slot: the rarest US state from wherever you actually are.
    ///
    /// The fixed six are unreachable for everybody, which makes them fair and also
    /// makes them the same for everybody. This one is not — it is whichever state the
    /// model ranks rarest from your position, once the two permanent ones are set
    /// aside, so a player in New Jersey and a player in Los Angeles are chasing
    /// different plates for the same tier.
    ///
    /// States only. Provinces and territories already hold five of the six permanent
    /// slots, and letting the roaming one land on another would make the tier read as
    /// "Canada" rather than as "the far edge of your own map".
    private static let stateCodes: Set<String> = Set(
        Plate.all.filter { $0.region == .state }.map(\.code))

    /// Promotes the mythic regions out of the bands they were dealt into.
    ///
    /// After the ranking rather than inside it, because mythic is not a share of the
    /// scale — `buckets` still deals all 65 regions into 1...10 exactly as before, and
    /// this lifts seven of them above it. Legendary is correspondingly smaller, which
    /// is intended: the plates that left it are the ones that made it feel cheap.
    private static func promotingMythic(_ bands: [String: Int],
                                        order: [String]) -> [String: Int] {
        var out = bands
        for code in mythicAlways where out[code] != nil { out[code] = mythicValue }

        // `order` is commonest first, so the last match is the rarest one.
        if let roaming = order.last(where: {
            stateCodes.contains($0) && !mythicAlways.contains($0)
        }) {
            out[roaming] = mythicValue
        }
        return out
    }

    /// Which state is currently wearing the roaming slot, for anything that needs to
    /// say so out loud rather than just colour it.
    static func roamingMythic(on route: Route?) -> String? {
        let table = self.table(on: route)
        return table.first { $0.value == mythicValue && stateCodes.contains($0.key)
            && !mythicAlways.contains($0.key) }?.key
    }

    /// Commonest first, then dealt into the buckets. Ties break on the code so the
    /// same route always produces the same table.
    private static func ranked(by weights: [String: Double]) -> [String: Int] {
        let order = weights.keys.sorted {
            weights[$0]! == weights[$1]! ? $0 < $1 : weights[$0]! > weights[$1]!
        }

        var result: [String: Int] = [:]
        var index = 0
        for (step, count) in buckets.enumerated() {
            for code in order[index..<min(index + count, order.count)] {
                result[code] = step + 1
            }
            index += count
        }
        // Anything past the last bucket — if the catalogue grows — is top rarity.
        for code in order.dropFirst(index) { result[code] = buckets.count }
        return promotingMythic(result, order: order)
    }

    /// Rarity for one plate. Falls back to the hand-assigned `Plate.points` when the
    /// trip has no route yet — a national average is a better answer than pretending
    /// to know where you are.
    static func rarity(_ code: String, on route: Route?) -> Int {
        guard let route else { return nationalTable[code] ?? 5 }
        return table(for: route)[code] ?? nationalTable[code] ?? 5
    }

    /// The whole table for a collection, route or no route.
    ///
    /// **Use this, not `table(for:)`, from anything holding an optional route.** The
    /// screens that wanted a whole table each wrote `route.map { table(for: $0) } ??
    /// [:]` and then fell back to `Plate.points` per lookup, which is wrong twice
    /// over: `points` is the old squashed hand-assigned scale, and it stops at 10, so
    /// a collection with nothing pinned had no mythic in it at all — the Map drew
    /// Alaska legendary gold and the crimson swatch in its own key matched nothing on
    /// the map. `rarity(_:on:)` had the fallback right all along; this is the same
    /// answer for callers that need every code at once.
    static func table(on route: Route?) -> [String: Int] {
        route.map { table(for: $0) } ?? nationalTable
    }

    /// The no-route fallback, put through the same buckets as a real route.
    ///
    /// The hand-assigned `Plate.points` are on the old squashed scale, so using them
    /// raw would give a player without a pinned route the exact lopsided spread this
    /// change exists to fix. Ranking them means the shape of the game is the same
    /// before and after you pin a destination; only the order changes.
    private static let nationalTable: [String: Int] = ranked(
        by: Dictionary(uniqueKeysWithValues: Plate.all.map { ($0.code, -Double($0.points)) })
    )

    /// Recomputing 65 weights per tile per render would be 4,225 pow() calls a frame.
    /// Routes change roughly never, so the whole table is memoised against one.
    private static var cache: [Route: [String: Int]] = [:]

    // MARK: - Geometry

    /// Kilometres from a region's centre to the nearest point on the route.
    ///
    /// Equirectangular rather than great-circle, so the point-to-segment projection
    /// is ordinary plane geometry instead of spherical trigonometry. See `project`
    /// for what that costs and what it used to cost.
    private static func distance(from origin: Origin, to route: Route) -> Double {
        let p = project(origin.lat, origin.lon)

        // Once the trip knows where the car actually is, that point *is* the route
        // as far as rarity is concerned — measured from here, not from the whole
        // line between the two ends.
        //
        // This is the entire point of tracking. Scored against the full segment, a
        // Kentucky plate is worth the same in Nevada as it is in Louisville, because
        // the segment passes through Kentucky either way. Scored from where you are,
        // it starts as a find and becomes wallpaper as you approach — which is what
        // is actually true out of the window.
        if let cLat = route.currentLat, let cLon = route.currentLon {
            let here = project(cLat, cLon)
            return hypot(p.x - here.x, p.y - here.y)
        }

        let a = project(route.oLat, route.oLon)

        guard let dLat = route.dLat, let dLon = route.dLon else {
            return hypot(p.x - a.x, p.y - a.y)
        }

        let b = project(dLat, dLon)
        let vx = b.x - a.x, vy = b.y - a.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }

        // Clamped so a region beyond either end measures from that end, not from
        // an imaginary extension of the road.
        let t = min(max(((p.x - a.x) * vx + (p.y - a.y) * vy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + t * vx), p.y - (a.y + t * vy))
    }

    /// Kilometres per degree of longitude, taken at one fixed reference latitude.
    ///
    /// 40°N — Philadelphia, Denver, Salt Lake City — is the middle of the band this
    /// game is actually played in.
    private static let kmPerLon = cos(40 * Double.pi / 180) * 111.0

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
    /// not notice. It stays plane geometry, so the point-to-segment projection in
    /// `distance(from:to:)` is unchanged.
    private static func project(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
        (x: lon * kmPerLon, y: lat * 111.0)
    }
}
