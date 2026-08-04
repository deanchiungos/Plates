import SwiftUI
import SwiftData

@main
struct PlatesApp: App {
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
        }
        .modelContainer(container)
    }
}
