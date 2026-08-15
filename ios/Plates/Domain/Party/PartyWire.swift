import Foundation

// What one device says to another during a party.
//
// Pure data. Nothing in this file imports SwiftData or MultipeerConnectivity, and
// nothing in it touches the store — `PartyMerge` does that, and the transport does
// the sending. Keeping the vocabulary separate from both is what makes the merge
// testable without a radio and the radio replaceable without touching the merge.
//
// Every payload mirrors fields that already exist on the models. There is no new
// stored property anywhere in the app, and therefore no CloudKit schema deploy —
// see the warning at the top of `PlatesStore`.

// MARK: - The envelope

/// One message, with the protocol version it was written by.
///
/// The version is checked at `hello` and a mismatch refuses the join outright. A
/// party where one phone silently misunderstands half the messages is worse than a
/// party that will not start: the first looks like a bug in the game, the second
/// looks like what it is, and says which phone needs updating.
struct PartyEnvelope: Codable {
    /// Bump whenever a payload's meaning changes. Adding an optional field does not
    /// count — decoding tolerates those — but removing or repurposing one does.
    ///
    /// v2 added `TripEvent.rules`. It is an optional field and would have decoded
    /// against v1 without complaint, which is exactly the problem: a v1 phone would
    /// have ignored the rules and happily un-tapped plates the rest of the party had
    /// agreed were protected. A rule everybody does not enforce is not a rule. The
    /// app is unreleased so there is no v1 population to strand; after release,
    /// prefer optional fields over bumps wherever the old behaviour stays *safe*.
    static let currentVersion = 2

    var v: Int
    var payload: Payload

    /// Which player the *sending device* is playing as.
    ///
    /// An `MCPeerID`'s display name is fixed for the life of the process — the
    /// framework has no way to rename one — so a party that identified people by it
    /// was showing a name from whenever the session started, and no amount of fixing
    /// the roster underneath could move it. This is the identity that does not go
    /// stale: a player id resolves to a live `Player` row, and the row is what a
    /// rename changes.
    ///
    /// Optional, and therefore not a version bump — the rule at `currentVersion`.
    /// A message without one falls back to the peer's display name, which is what
    /// every message did before, so an older phone in the car degrades to exactly
    /// the old behaviour instead of breaking.
    var from: UUID?

    init(_ payload: Payload, from: UUID? = nil,
         v: Int = PartyEnvelope.currentVersion) {
        self.v = v
        self.payload = payload
        self.from = from
    }

    enum Payload: Codable {
        /// Everything the sender knows about this party's trip. Sent on every
        /// connection, not only the first.
        case hello(PartySnapshot)
        /// One plate, just logged.
        case sighting(SightingEvent)
        /// Sightings taken back — an un-tap on the grid, or a voice undo.
        case remove(RemovalEvent)
        /// Players this device owns, or has learned about.
        case roster([PlayerEvent])
        /// Host-only: the trip's shared settings changed.
        case tripUpdate(TripEvent)
        /// A clean goodbye, so peers can distinguish leaving from dropping out.
        case bye
    }
}

// MARK: - Payloads

/// The whole of a party's state, as one message.
///
/// Sent on every connect rather than diffed, and that is a deliberate refusal to
/// optimise. A trip is at most 65 distinct plates and a few hundred sightings if
/// somebody is playing unlimited hard — call it 12 KB of JSON over a link that is
/// two metres of air. What the money buys is that first join, rejoin after a
/// locked phone, and recovery from a dropped session are all *the same code path*,
/// exercised on every single connection instead of only in the rare case a delta
/// protocol would get wrong.
struct PartySnapshot: Codable {
    var trip: TripEvent
    var players: [PlayerEvent]
    var sightings: [SightingEvent]
    /// Sightings this party has already taken back. Carried so a late joiner does
    /// not re-add a plate somebody un-tapped before they arrived — without these,
    /// their copy would resurrect it and broadcast it back.
    var tombstones: [UUID]
    /// Which player id belongs to the device hosting. Used for the "hosted by"
    /// line, and to decide who is allowed to change the trip's settings.
    var hostPlayerID: UUID?
}

/// One plate, seen once, by one player. Mirrors `Sighting` exactly.
struct SightingEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var plateCode: String
    var spottedAt: Date
    var tripID: UUID
    /// Optional because an unowned sighting is already legal — a player can be
    /// removed without un-collecting what they spotted.
    var playerID: UUID?
    /// Travels as data, and must. Rarity is a function of where the car was, so a
    /// peer recomputing it from *their* fix would bank a different number for the
    /// same find and the two phones would disagree about the score.
    var rarityWhenSpotted: Int?
    var spottedLat: Double?
    var spottedLon: Double?
}

/// Sightings withdrawn, and which trip they belonged to.
///
/// The trip id rides along because the receiver has to record the tombstone
/// against something, and the sightings themselves may already be gone locally —
/// in which case there is no row left to ask.
struct RemovalEvent: Codable, Equatable {
    var tripID: UUID
    var sightingIDs: [UUID]
}

/// Someone in the car. Mirrors `Player`.
struct PlayerEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var colorIndex: Int
    /// Their emoji, if they picked one. Optional and additive: a build that does
    /// not know about it falls back to initials, which is a real face rather than
    /// a broken one — so this needed no version bump, unlike `PartyRules`.
    var avatar: String?
    /// Kept because it is the stable tie-break for standings order, and for the
    /// color de-collision rule: both need every device to sort players the same
    /// way, and join order is the only ordering that is a fact rather than a
    /// preference.
    var joinedAt: Date
}

/// The trip's *shared* columns, and only those.
///
/// Conspicuously absent: `currentLat` / `currentLon` / `locatedAt`, which are this
/// phone's own fix and feed its live rarity; and `pinnedAt` / `archivedAt`, which
/// are statements about your own lists. Overwriting any of them from a peer would
/// mean the host's GPS deciding what a passenger's unclaimed plates are worth, or
/// the host tidying their trip list tidying yours. `PartyMerge` writes exactly the
/// fields present here and no others.
struct TripEvent: Codable, Equatable {
    var id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var origin: String?
    var destination: String?
    var originLat: Double?
    var originLon: Double?
    var destinationLat: Double?
    var destinationLon: Double?
    /// Raw rather than `ScoringMode`, so a future mode from a newer build arrives
    /// as an unknown string and falls back through `Trip.scoringMode`'s existing
    /// guard instead of failing the whole decode.
    var scoringModeRaw: String
    var includesTrucks: Bool
    /// How the party plays. Optional so a `TripEvent` built outside a party (or by
    /// a future build that drops them) still decodes; `nil` means the defaults.
    var rules: PartyRules?
}

/// What the host has decided about how the game is played.
///
/// Both of these are about the same underlying awkwardness: the grid was designed
/// for one phone, where every plate on it was yours and a tap that took one back
/// could only ever be undoing your own mistake. With five phones on one trip, the
/// same tap can undo somebody else's afternoon.
struct PartyRules: Codable, Equatable {

    /// You can only take back plates you claimed yourself. On by default.
    ///
    /// Off is the old behaviour, and it is a real choice rather than a legacy
    /// setting: a couple playing together may well want either of them to fix a
    /// mistap without passing a phone around. On is the default because the failure
    /// it prevents — one bored passenger clearing the board — is worse than the
    /// inconvenience it causes.
    var protectsClaims: Bool = true

    /// Everybody who calls a plate gets it, instead of the first person taking it
    /// off the board for the rest of the car. Off by default.
    ///
    /// Off, the game is a race: the plate is spotted, it is on the board, and the
    /// next person to tap it is trying to take it back. On, it is a shared hunt —
    /// four people can each bank Montana, each at what it was worth from where they
    /// were sitting, and the trip still counts it once. Which of those two games a
    /// car wants is genuinely a matter of who is in it.
    var sharedClaims: Bool = false

    static let standard = PartyRules()
}

// MARK: - Coding

extension PartyEnvelope {

    /// JSON, with dates as `Double`s.
    ///
    /// The date strategy is load-bearing, not a default nobody thought about.
    /// `spottedAt` is half of `SightingOrder`, which decides who is credited with a
    /// plate and what it was first claimed at — so a strategy that rounds, like
    /// `.iso8601` dropping sub-second precision, would hand the sender and the
    /// receiver *different* timestamps for the same sighting and quietly desync the
    /// two devices' answers. `.deferredToDate` writes the raw interval and round
    /// trips exactly, which is the only property that matters here.
    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return (encoder, decoder)
    }

    func encoded() throws -> Data {
        try Self.coder().0.encode(self)
    }

    /// Returns nil rather than throwing on a version we cannot read, so the caller
    /// can tell "someone needs to update" apart from "that was not one of ours".
    static func decoded(from data: Data) throws -> PartyEnvelope? {
        let envelope = try coder().1.decode(PartyEnvelope.self, from: data)
        guard envelope.v == currentVersion else { return nil }
        return envelope
    }
}
