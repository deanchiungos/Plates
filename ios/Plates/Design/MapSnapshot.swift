import CoreLocation
import MapKit
import UIKit

/// Asking MapKit for a still picture of a region.
///
/// Two places need one — the route strip in a trip's editor and the map on a trip's
/// poster — and both had written out the same options block and the same
/// continuation wrapper. The options are the interesting half: two of the four
/// settings are decisions, not defaults, and a third copy of this made somewhere
/// else would most likely be missing them.
enum MapSnapshot {

    /// A still of `region`, or nil if MapKit could not draw one.
    ///
    /// Off the main actor deliberately — `start(with:)` renders tiles, and handing
    /// it `.main` stalls whatever is on screen for the length of a network fetch.
    static func take(of region: MKCoordinateRegion, size: CGSize) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        // Nobody is looking for a coffee shop on a picture of their road trip, and
        // the pins are the only marks that should be on it.
        options.pointOfInterestFilter = .excludingAll
        // Pinned light. The app is light-only and the poster is cream; a dark map
        // dropped into either reads as a rendering fault rather than as a setting.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                continuation.resume(returning: snapshot)
            }
        }
    }
}
