import Observation

/// Which party is running, in a box SwiftUI can watch.
///
/// `PartySession.shared` was a bare `static var` on an `@Observable` class, which
/// makes the session's *properties* observable and its *identity* invisible: a body
/// that reads `PartySession.shared?.latestFromPeer` registers an observation on
/// whichever object the static happened to hold at that moment, and nothing at all
/// if it held nil. Starting a party from the More tab therefore did not redraw the
/// Game screen, which had last evaluated when there was no party; the peer-find
/// toast appeared only because some unrelated `@Query` change happened to re-read
/// the expression.
///
/// `PartyScreen` had worked around it with a hand-mirrored `@State` copy, which
/// bought correct redraws and cost something worse: the mirror was never re-synced,
/// so a party ended from anywhere else — finishing the trip on the Trips tab,
/// deleting it, `TripClosing` — left the Party screen drawing a live host card, code
/// and all, for a session that was over. Flipping a rule on it wrote a ledger entry
/// for a finished trip and sent on a disconnected socket.
///
/// One observable box fixes both. `PartySession.shared` still reads the same at
/// every call site; it is a passthrough now, so assigning to it notifies, and every
/// screen that reads it is observing.
@MainActor
@Observable
final class PartyHost {
    static let shared = PartyHost()
    var session: PartySession?
    private init() {}
}
