import CloudKit
import Observation
import SwiftUI
import SwiftData
import UIKit

/// Exists for exactly one callback.
///
/// Accepting a shared book happens outside the app's own UI: somebody taps a link
/// in Messages, iOS launches us, and hands the invitation to the *application*
/// delegate. There is no SwiftUI equivalent — `onOpenURL` never sees it, because a
/// CloudKit share is not delivered as a URL — so this is the one thing the app
/// still needs a `UIApplicationDelegate` for.
final class PlatesAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await SharedBookSync.shared.accept(metadata, into: PlatesStore.context)
        }
    }

    /// The widget's `plates://collect`, and now the second thing this delegate is
    /// for. SwiftUI's `onOpenURL` is the obvious home for it and simply never fired
    /// — with a `UIApplicationDelegateAdaptor` in place the URL arrives here instead,
    /// and a modifier that is never called is worse than no modifier, because it
    /// looks like the feature exists.
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        DeepLink.shared.receive(url)
    }
}

/// Where a URL waits for the view that can act on it.
///
/// The delegate is outside the view hierarchy and the tab selection lives inside it,
/// so the two need somewhere to meet. One-shot: `RootView` takes the destination and
/// clears it, so coming back from the background does not silently re-navigate.
@MainActor
@Observable
final class DeepLink {
    static let shared = DeepLink()

    enum Destination { case collect }

    private(set) var pending: Destination?

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard url.scheme == "plates", url.host == "collect" else { return false }
        pending = .collect
        return true
    }

    func take() -> Destination? {
        defer { pending = nil }
        return pending
    }
}

@main
struct PlatesApp: App {
    @UIApplicationDelegateAdaptor(PlatesAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    @MainActor
    init() {
        // Shared with the Siri intents — see `PlatesStore`.
        container = PlatesStore.container
        PlatesStore.seedIfNeeded()
        Theme.applyToSystemControls()
        #if DEBUG
        // Before `beginSession`, not after it. `-coachReset` clears the launch
        // counter, and `beginSession` reads that counter into a static and keeps it
        // for the rest of the process — so run the other way round, the flag wiped
        // the stored value while `Coach.launchCount` stayed at whatever this phone
        // had reached, `isReturningSession` stayed true, and the one tip gated on a
        // second launch still fired on the launch that asked for a first one. The
        // reset only landed on the *next* run, which is the launch nobody was
        // watching. Both flags still run before any screen can ask.
        Coach.applyLaunchArguments()
        Tour.applyLaunchArguments()
        #endif
        Coach.beginSession()
        // Rebuilt at launch: trips may have been finished on another device, or the
        // permission revoked in Settings while the app was away.
        TripReminders.shared.refresh(in: PlatesStore.context)
        WidgetData.write(from: PlatesStore.context)

        #if DEBUG
        // `-partyMergeCheck` verifies that a party's sightings rebuild the same game
        // on a peer. Runs against its own in-memory stores, so it cannot touch
        // anything above; the app carries on launching normally afterwards.
        if PartyMergeCheck.isRequested { PartyMergeCheck.run() }
        // `-poster` renders the share image and writes it out, so it can be looked
        // at without driving a share sheet.
        if LaunchFlags.isSet("-remindersTest") {
            Task { @MainActor in await TripReminders.shared.test(in: PlatesStore.context) }
        }
        if LaunchFlags.isSet("-poster") {
            Task { @MainActor in print(await ShareablePoster.exportForInspection()) }
        }
        // `-layoutStress` draws the app's crowded rows — the trips list, the book
        // header, the drive header, the compare list — at every width and text size
        // they can be asked for, with names and parties long enough to break them.
        // See `LayoutStress`; it uses its own in-memory stores and cannot touch
        // anything.
        if LayoutStress.isRequested { print(LayoutStress.run()) }
        // Resolve the speaking voice now rather than when voice mode first opens, so
        // its inventory lands in the console of a plain debug launch — which is the
        // only way to see what `speechVoices()` returns on a physical phone.
        _ = VoiceSpeaker.voice

        // `-rarityDump lat,lon[,winter]` prints the full table from that point, so a
        // change to the model can be verified against the Python prototype it was
        // ported from instead of against a screenshot of some tiles.
        if let point = LaunchFlags.value(after: "-rarityDump") {
            let f = point.split(separator: ",")
            if f.count >= 2, let lat = Double(f[0]), let lon = Double(f[1]) {
                // "current" makes the point a live tracking fix, which is what arms
                // the corridor term; bare coordinates are a parked route origin.
                let live = f.contains("current")
                let route = PlateRarity.Route(oLat: lat, oLon: lon,
                                              currentLat: live ? lat : nil,
                                              currentLon: live ? lon : nil,
                                              isWinter: f.contains("winter"))
                let table = PlateRarity.table(for: route)
                for (code, band) in table.sorted(by: { $0.key < $1.key }) {
                    print("RARITY: \(code) \(band)")
                }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Every color in `Theme` is a fixed light value. Anything the
                // system draws for us — navigation titles, segmented controls, tab
                // bar labels — follows the device appearance instead, so on a phone
                // in dark mode they turned white and vanished into our light
                // backgrounds. Locking the scheme is the honest fix until there is a
                // real dark palette; half a theme is worse than one.
                .preferredColorScheme(.light)
                // Shared books are filled over weeks, not seconds, so this pulls on
                // arrival rather than polling. Anything a friend added while the app
                // was closed lands the moment it is opened.
                .task { await SharedBookSync.shared.pullAll(into: PlatesStore.context) }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await SharedBookSync.shared.pullAll(into: PlatesStore.context) }
        }
    }
}
