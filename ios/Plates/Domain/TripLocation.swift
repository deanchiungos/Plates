import CoreLocation
import Foundation
import Observation

/// Where the car is, while a trip is being played.
///
/// This exists for two jobs and nothing else: moving the car along the road rail,
/// and re-anchoring the rarity of plates you have *not* yet claimed. It never
/// stores a location history and never sends one anywhere — the only thing written
/// down is the single most recent position, on the trip, so the rail is still right
/// when you reopen the app.
///
/// **When-in-use, not always.** Tracking stops the moment the app is backgrounded.
/// That is enough for the feature as described — you are looking at the screen when
/// you spot a plate — and it avoids asking for the far more invasive Always
/// permission, the background-location entitlement, and the battery cost of keeping
/// the GPS awake for the whole drive. The cost is that distance-remaining goes stale
/// while the phone is in a pocket, and catches up the next time you open the app.
@MainActor
@Observable
final class TripLocation: NSObject, CLLocationManagerDelegate {
    static let shared = TripLocation()

    private(set) var coordinate: CLLocationCoordinate2D?

    /// Bumped on every accepted fix. `CLLocationCoordinate2D` is not `Equatable`, so
    /// this is what views watch with `onChange` — and it is honest about the thing
    /// that actually happened, which is "a new fix arrived".
    private(set) var updatedAt: Date?
    private(set) var authorization: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var isTracking = false

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        // Off, not on. Auto-pause is built for walking apps: it suspends updates
        // when the device looks stationary and can stay suspended for minutes after
        // you move again. Tracking here only runs while the Drive screen is open, so
        // the battery argument for it is weak and the cost — a car frozen on the rail
        // while you are plainly driving — is exactly the bug it would cause.
        manager.pausesLocationUpdatesAutomatically = false
        tune(forRouteLength: nil)
    }

    /// Matches the update granularity to the length of the drive.
    ///
    /// A fixed filter cannot serve both ends of the range. At the 2 km it used to
    /// use, a coast-to-coast trip got a smooth crawl — 0.05% of the journey per
    /// update — while a twenty-mile run got a car that lurched in 6% jumps and spent
    /// most of the drive standing still. Kilometre accuracy could not resolve the
    /// short one either.
    ///
    /// So the filter is derived from the route: roughly 120 updates end to end,
    /// whatever the distance, with accuracy stepped to match. Short drives get fine
    /// fixes because they need them and cost little; long ones stay coarse because
    /// nothing is gained by waking the GPS every ninety seconds for four days.
    func tune(forRouteLength metres: Double?) {
        let step: CLLocationDistance
        if let metres, metres > 0 {
            step = min(max(metres / 120, 30), 1_500)
        } else {
            step = 500
        }

        manager.distanceFilter = step
        manager.desiredAccuracy = step < 100  ? kCLLocationAccuracyNearestTenMeters
                                : step < 500  ? kCLLocationAccuracyHundredMeters
                                              : kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// True once the user has been asked, whatever they answered. Used to decide
    /// whether to offer the prompt rather than to nag.
    var hasBeenAsked: Bool { authorization != .notDetermined }

    func requestAccess() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Safe to call repeatedly — starting an already-running manager is a no-op here
    /// rather than in CoreLocation, which would happily re-arm it.
    func start() {
        guard isAuthorized, !isTracking else { return }
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        // A stale fix served from cache can be hours and hundreds of miles old, which
        // would drag the car backwards down the rail on launch.
        guard last.timestamp.timeIntervalSinceNow > -300 else { return }
        let c = last.coordinate
        Task { @MainActor in
            self.coordinate = c
            self.updatedAt = Date()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Nothing to show the user: a failed fix simply leaves the rail where it was.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAuthorized { self.start() } else { self.stop() }
        }
    }
}

// MARK: - Geometry

enum GreatCircle {
    /// Metres between two points. Haversine rather than the equirectangular
    /// approximation `PlateRarity` uses — that one is tuned for ranking regions at
    /// continental scale, while this number is shown to the user as "412 mi to go"
    /// and should not be visibly wrong.
    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let earth = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earth * asin(min(1, sqrt(h)))
    }
}


// MARK: - Journey progress

extension Trip {

    var originCoordinate: CLLocationCoordinate2D? {
        guard let originLat, let originLon else { return nil }
        return .init(latitude: originLat, longitude: originLon)
    }

    var destinationCoordinate: CLLocationCoordinate2D? {
        guard let destinationLat, let destinationLon else { return nil }
        return .init(latitude: destinationLat, longitude: destinationLon)
    }

    var currentCoordinate: CLLocationCoordinate2D? {
        guard let currentLat, let currentLon else { return nil }
        return .init(latitude: currentLat, longitude: currentLon)
    }

    /// How far along the drive, 0...1. Nil unless both ends are pinned and a fix has
    /// been taken — the car cannot honestly be drawn anywhere without all three.
    ///
    /// Measured straight-line rather than along the road. The road distance is known
    /// only for as long as the map preview holds it, and a progress bar that
    /// disagreed with itself between launches would be worse than one that is
    /// consistently a few percent optimistic.
    var journeyProgress: Double? {
        guard let origin = originCoordinate,
              let destination = destinationCoordinate,
              let here = currentCoordinate else { return nil }

        let total = GreatCircle.metres(origin, destination)
        // Two pins in the same town have no meaningful progress to report, and
        // dividing by a few metres would swing the car end to end on GPS noise.
        guard total > 2_000 else { return nil }

        let left = GreatCircle.metres(here, destination)
        return min(max(1 - left / total, 0), 1)
    }

    /// "412 mi to go", in whichever units the reader's locale uses. Nil when there is
    /// no destination or no fix.
    var remainingLabel: String? {
        guard let destination = destinationCoordinate,
              let here = currentCoordinate else { return nil }

        let metres = GreatCircle.metres(here, destination)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = metres < 10_000 ? 1 : 0

        let distance = Measurement(value: metres, unit: UnitLength.meters)
        return metres < 500
            ? "Arrived"
            : "\(formatter.string(from: distance)) to go"
    }
}
