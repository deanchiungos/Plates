import CloudKit
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
        // `-partyMergeCheck` verifies that a party's sightings rebuild the same game
        // on a peer. Runs against its own in-memory stores, so it cannot touch
        // anything above; the app carries on launching normally afterwards.
        if PartyMergeCheck.isRequested { PartyMergeCheck.run() }
        // Resolve the speaking voice now rather than when voice mode first opens, so
        // its inventory lands in the console of a plain debug launch — which is the
        // only way to see what `speechVoices()` returns on a physical phone.
        _ = VoiceSpeaker.voice
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Every colour in `Theme` is a fixed light value. Anything the
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
