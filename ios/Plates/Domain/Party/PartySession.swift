import Foundation
import MultipeerConnectivity
import Observation
import SwiftData
import UIKit

/// A party: the phones in one car, sharing one trip.
///
/// MultipeerConnectivity rather than anything server-shaped, because this is a car
/// game. The party is the people within arm's reach, the drive goes through dead
/// zones, and the moments the game is most alive are exactly the moments there is
/// no signal. Peer-to-peer needs no account, no network and no CloudKit sharing —
/// which SwiftData does not support anyway.
///
/// One object for the whole lifecycle, including the browse that happens before
/// there is a party to be in. Splitting "looking for a party" from "in a party"
/// into two types reads tidier and is a lie: MultipeerConnectivity requires the
/// `MCSession` to exist *before* the invitation is sent, so the thing that browses
/// and the thing that joins have to be the same thing holding the same session.
///
/// Everything here is `@MainActor`. The delegate callbacks are not — they arrive on
/// whichever queue the framework feels like — so they land on `PartyTransport`
/// below and hop across before touching any state.
@MainActor
@Observable
final class PartySession {

    /// `nil` means "no party", which is the state the app is in essentially always.
    /// Every hook into the rest of the app is a one-line optional call on this, so
    /// the whole feature costs nothing when it is not running.
    static private(set) var shared: PartySession?

    enum Role { case host, guest }

    /// A party someone nearby is advertising.
    struct Nearby: Identifiable, Equatable {
        let peer: MCPeerID
        let tripID: UUID
        let tripName: String
        let hostName: String

        /// The trip is part of the identity, not just the peer. Two phones can easily
        /// advertise the same display name — the name comes off the roster, and a car
        /// full of installs seeded with "Me" is the normal case — and a `ForEach` fed
        /// duplicate ids draws one row where there were two parties.
        var id: String { "\(peer.displayName)#\(tripID.uuidString)" }
    }

    // MARK: - State the UI reads

    let role: Role
    /// Known up front when hosting. A guest carries a placeholder while it browses
    /// and adopts the real one from the advertisement at the moment it joins — which
    /// is before it connects, so nothing ever has to cope with not knowing it.
    private(set) var tripID: UUID
    /// Four characters, shown by the host and typed by everyone else. Not in the
    /// advertisement: a code anyone browsing could simply read would authorise
    /// nothing. It is sent with the invitation and checked by the host.
    private(set) var code: String

    private(set) var members: [String] = []
    private(set) var nearby: [Nearby] = []
    private(set) var isConnected = false

    /// The last plate somebody else called, for the Game screen to mention.
    ///
    /// A peer's find deliberately does *not* fire the find card, the confetti or the
    /// haptic. Those are the reward for spotting something, and firing them on five
    /// phones for one plate turns the reward into noise — worse, it would go off in
    /// the pocket of someone who was not even looking. A line that slides in and
    /// leaves is the honest weight for "Mia got Montana".
    private(set) var latestFromPeer: PeerFind?

    struct PeerFind: Equatable, Identifiable {
        let id = UUID()
        let plateName: String
        let finder: String
        let tier: RarityTier
    }
    /// Surfaced verbatim rather than swallowed — "could not join" with no reason is
    /// unactionable in a moving car.
    private(set) var trouble: String?

    // MARK: - Machinery

    private let context: ModelContext
    private let tombstones: PartyTombstones
    private let myName: String
    private let peerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var transport: PartyTransport!
    private var foregroundWatch: NSObjectProtocol?

    /// The host this guest joined, so it can find its way back.
    ///
    /// A party spends a lot of its life disconnected: a phone that locks, goes in a
    /// pocket, or loses the screen for a minute drops out of the session entirely.
    /// Remembering who we were with is what turns that from "the party is over" into
    /// a gap.
    private var hostPeer: MCPeerID?

    /// Past browsing: a party has been picked, a code entered, **and the host let us
    /// in**. What separates "reconnect me" from "show me what is nearby".
    ///
    /// Set on the connection rather than on the invitation, which is the whole
    /// difference between a retryable failure and a dead end. Set on the invitation,
    /// a wrong code left this true forever: `found` then short-circuited every
    /// sighting of the host into a silent re-invite, the party could never go back
    /// into `nearby`, and one lost/found cycle emptied the list for good — leaving a
    /// "looking for parties" spinner over a party sitting two feet away.
    private var hasJoined = false

    /// The party we have asked to join and are still waiting on.
    ///
    /// Held rather than merely remembered, because a refusal has to put it back in
    /// the list to be tapped again — and because until this existed, the twenty
    /// seconds between tapping Join and finding out looked exactly like the app
    /// doing nothing.
    private(set) var joining: Nearby?

    /// Fires if the invitation is neither accepted nor refused in time.
    ///
    /// MultipeerConnectivity does not promise a callback for an invitation the
    /// advertiser declines — `invitationHandler(false, nil)` can simply produce
    /// silence — so the only reliable way to tell somebody their code was wrong is
    /// to give up waiting ourselves.
    private var joinWatch: Task<Void, Never>?

    /// Long enough for a phone to answer over a car's worth of Bluetooth, short
    /// enough that a wrong code is a mistake rather than an outage.
    private static let inviteTimeout: TimeInterval = 12

    /// The host said goodbye. Distinct from merely being disconnected — one is
    /// waiting to reconnect, the other is over, and re-inviting after the second
    /// would be chasing somebody who has gone home.
    private(set) var hasEnded = false

    /// Every player this party has told us about.
    ///
    /// Kept so the standings strip can show somebody the moment they join rather
    /// than the moment they first call a plate — and, more importantly, so it can
    /// show *only* them. See `PlateCollection.participants`.
    private(set) var knownPlayerIDs: Set<UUID> = []

    /// The party's roster, but only if the party is actually on this collection.
    /// Empty for every other trip and every book, which is the whole point.
    static func roster(for collection: UUID) -> Set<UUID> {
        guard let party = shared, party.tripID == collection, !party.hasEnded else { return [] }
        return party.knownPlayerIDs
    }

    /// How this party plays. Host-set, sent to everyone, enforced by everyone.
    private(set) var rules: PartyRules = .standard

    /// The rules in force for a collection right now.
    ///
    /// Only while a party is actually running on it. Once the party ends, the trip
    /// on your phone is *your copy* and the ordinary rules resume — protecting the
    /// claims of somebody who is no longer in the car would be guarding a scoreboard
    /// against its only remaining player. Deliberately keyed on the session rather
    /// than on being connected, so a phone that drops out for a minute does not
    /// briefly get permission to strip the board.
    static func rules(for collection: UUID) -> PartyRules {
        guard let party = shared, party.tripID == collection, !party.hasEnded else {
            return .standard
        }
        return party.rules
    }

    /// Host only. Persists, then tells everyone.
    func setRules(_ new: PartyRules) {
        guard role == .host, rules != new else { return }
        rules = new
        PartyLedger.shared.setRules(new, for: tripID)
        if let trip = localTrip() { send(.tripUpdate(PartyMerge.event(for: trip, rules: new))) }
    }

    /// 12 characters, lower-case, one hyphen: inside the 15-character limit and the
    /// character set Bonjour actually allows. Must match `NSBonjourServices` in
    /// Info.plist exactly or discovery silently finds nothing.
    private static let service = "plates-party"

    // MARK: - Starting

    @discardableResult
    static func host(trip: Trip, as name: String, context: ModelContext) -> PartySession {
        shared?.leave()
        let party = PartySession(role: .host, tripID: trip.id, code: Self.freshCode(),
                                 name: name, context: context)
        // Whatever this trip was played by last time, if it has been a party before.
        party.rules = PartyLedger.shared.rules(for: trip.id)
        PartyLedger.shared.note(trip: trip.id, role: "host", rules: party.rules)
        party.startAdvertising(tripName: trip.name)
        shared = party
        return party
    }

    /// Browsing is a party in every respect except that it has not found anyone yet,
    /// so it uses the same object. `tripID` is a placeholder until `join` replaces
    /// this session with a real one — nothing broadcasts while browsing, because
    /// `broadcast` requires a connected peer.
    @discardableResult
    static func browse(as name: String, context: ModelContext) -> PartySession {
        shared?.leave()
        let party = PartySession(role: .guest, tripID: UUID(), code: "",
                                 name: name, context: context)
        party.startBrowsing()
        shared = party
        return party
    }

    private init(role: Role, tripID: UUID, code: String,
                 name: String, context: ModelContext,
                 tombstones: PartyTombstones = .shared) {
        self.role = role
        self.tripID = tripID
        self.code = code
        self.context = context
        self.tombstones = tombstones
        // Trimmed to what `MCPeerID` accepts: non-empty, and 63 bytes at the outside.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.myName = trimmed.isEmpty ? "Someone" : String(trimmed.prefix(30))
        self.peerID = MCPeerID(displayName: self.myName)

        transport = PartyTransport(owner: self)

        // iOS suspends the radios along with the app, and does not start them again
        // on its own — so without this a party survives exactly until the first
        // person locks their phone, which on a long drive is about four minutes.
        foregroundWatch = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.wakeUp() }
        }

        // Encryption is not the default and should be. Two phones on a motorway
        // services wifi are on a network with strangers on it.
        session = MCSession(peer: peerID, securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = transport
    }

    private func startAdvertising(tripName: String) {
        // The trip id rides along so a joiner knows which trip it is about to fill
        // before it has connected to anything — which is what lets `tripID` be
        // settled at construction rather than discovered halfway through a merge.
        let info = ["trip": String(tripName.prefix(40)),
                    "host": myName,
                    "id": tripID.uuidString]
        let ad = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info,
                                           serviceType: Self.service)
        ad.delegate = transport
        ad.startAdvertisingPeer()
        advertiser = ad
    }

    private func startBrowsing() {
        let finder = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.service)
        finder.delegate = transport
        finder.startBrowsingForPeers()
        browser = finder
    }

    /// Invites the host, with the typed code as the invitation's context. The host
    /// checks it and refuses if it is wrong, so a wrong code fails on the phone that
    /// knows the right one rather than on the phone guessing.
    ///
    /// This mutates the browsing session rather than building a fresh one, and it has
    /// to. `invitePeer` is only meaningful on the browser that actually discovered
    /// that peer — hand it an `MCPeerID` some *other* browser found and it fails
    /// silently, no error, no connection, forever. Browsing and joining are one
    /// object because MultipeerConnectivity requires them to be.
    func join(_ party: Nearby, code entered: String) {
        guard role == .guest, let browser else { return }
        tripID = party.tripID
        code = Self.tidy(entered)
        hostPeer = party.peer
        joining = party
        // A previous attempt's complaint, cleared by the act of trying again. Leaving
        // it up would put "your code was wrong" above a join that is going fine.
        trouble = nil
        // Provisional until the host's snapshot says otherwise, which is a moment
        // later. Starting from the protective default rather than the permissive one
        // means the gap cannot be used to clear somebody's plates.
        rules = PartyLedger.shared.rules(for: party.tripID)
        PartyLedger.shared.note(trip: party.tripID, role: "guest", rules: rules,
                                hostName: party.hostName)
        guard let payload = code.data(using: .utf8) else { return }
        browser.invitePeer(party.peer, to: session, withContext: payload,
                           timeout: Self.inviteTimeout)

        joinWatch?.cancel()
        joinWatch = Task { @MainActor [weak self] in
            // A second past the invitation's own deadline, so the framework gets to
            // report the failure itself where it can, and this only covers the case
            // where it says nothing at all.
            try? await Task.sleep(for: .seconds(Self.inviteTimeout + 1))
            guard !Task.isCancelled else { return }
            self?.joinFailed()
        }
    }

    /// The host never let us in — wrong code, or out of range, and nothing in the
    /// transport can tell us which.
    ///
    /// Both are worth saying out loud and both are worth retrying, so the party goes
    /// back in the list and the message leads with the cause that is actually somebody
    /// in the car's to fix.
    private func joinFailed() {
        guard let target = joining else { return }
        settleJoin()
        hostPeer = nil
        if !nearby.contains(where: { $0.peer == target.peer }) { nearby.append(target) }
        trouble = "Could not join \(target.tripName). Check the four characters on "
                + "\(target.hostName)'s phone and tap the trip again."
    }

    /// The invitation is no longer outstanding, however it ended.
    private func settleJoin() {
        joinWatch?.cancel()
        joinWatch = nil
        joining = nil
    }

    /// Back again after a drop.
    ///
    /// Silent and automatic, because the thing that caused it was almost certainly
    /// somebody's phone locking itself, and asking them to re-enter a code for that
    /// would be the app blaming them for its own transport. The code is still held
    /// from the first join, so the host's check is satisfied exactly as before.
    private func rejoin(_ peer: MCPeerID) {
        guard role == .guest, hasJoined, !hasEnded, !isConnected,
              let browser, let payload = code.data(using: .utf8) else { return }
        browser.invitePeer(peer, to: session, withContext: payload, timeout: 20)
    }

    /// Back from the background: start the radios again, and catch up anyone still
    /// attached.
    ///
    /// Stopped and restarted rather than simply started, because calling
    /// `startAdvertisingPeer` on an advertiser that never actually stopped is not
    /// something the framework promises anything about.
    ///
    /// The re-greet is free insurance: a snapshot is idempotent, so sending one to a
    /// peer that never went anywhere costs a few kilobytes and closes the window
    /// where something was logged while this phone was asleep.
    private func wakeUp() {
        guard !hasEnded else { return }

        if let advertiser {
            advertiser.stopAdvertisingPeer()
            advertiser.startAdvertisingPeer()
        }
        if let browser {
            browser.stopBrowsingForPeers()
            browser.startBrowsingForPeers()
        }
        for peer in session.connectedPeers { greet(peer) }
    }

    // MARK: - Leaving

    func leave() {
        send(.bye)
        // The goodbye needs a moment to actually leave the device. `send` hands the
        // data off asynchronously and `disconnect()` tears the connection down, so
        // going straight from one to the other drops it — and a peer that never hears
        // it cannot tell a deliberate exit from a dropout, so it spends the rest of
        // the drive politely trying to reconnect to somebody who has gone home.
        stop(gracePeriod: 0.4)
        if PartySession.shared === self { PartySession.shared = nil }
    }

    private func stop(gracePeriod: TimeInterval = 0) {
        // Before the radios go, or a watchdog left running reports a failed join
        // against a party the user has already walked away from.
        settleJoin()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        if gracePeriod > 0, let live = session {
            DispatchQueue.main.asyncAfter(deadline: .now() + gracePeriod) { live.disconnect() }
        } else {
            session.disconnect()
        }
        isConnected = false
        members = []
        nearby = []
        if let foregroundWatch {
            NotificationCenter.default.removeObserver(foregroundWatch)
            self.foregroundWatch = nil
        }
    }

    /// Whether this trip is currently the subject of a live party — which is the one
    /// thing that has to be true before it can be deleted or finished out from under
    /// four other phones. See `TripsScreen`.
    static func isPartying(_ trip: Trip) -> Bool {
        guard let party = shared else { return false }
        return party.tripID == trip.id && !party.hasEnded
    }

    // MARK: - Talking

    /// Called from `PlateLogger`, the one place a sighting is ever created.
    ///
    /// Only what this device authored travels this way. Received sightings are
    /// applied by `PartyMerge`, which never calls `PlateLogger` — so nothing that
    /// arrives is ever re-broadcast, and the party cannot echo. That is structural,
    /// not a flag somebody has to remember to check.
    func broadcast(_ sighting: Sighting) {
        guard sighting.trip?.id == tripID,
              let event = PartyMerge.event(for: sighting) else { return }
        send(.sighting(event))
    }

    /// An un-tap on the grid, or a voice undo.
    ///
    /// The tombstone is recorded locally as well as sent, and that is the load
    /// bearing half: without it, the next snapshot from any peer who has not caught
    /// up yet would hand the plate straight back.
    func broadcastRemoval(_ ids: [UUID], in trip: UUID) {
        guard trip == tripID, !ids.isEmpty else { return }
        tombstones.add(ids, to: trip)
        send(.remove(RemovalEvent(tripID: trip, sightingIDs: ids)))
    }

    /// The trip's shared settings changed. Host only — a guest's editor does not
    /// offer the controls, and this is the second half of that rule so a guest cannot
    /// push a change some other way.
    func broadcastTrip(_ trip: Trip) {
        guard role == .host, trip.id == tripID else { return }
        send(.tripUpdate(PartyMerge.event(for: trip, rules: rules)))
    }

    private func send(_ payload: PartyEnvelope.Payload, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty, let data = try? PartyEnvelope(payload).encoded() else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    /// Everything this device knows about the party trip, or just who is here if it
    /// does not have the trip yet.
    ///
    /// Sent by *both* sides on every connection, which is what makes a guest that
    /// logged plates while disconnected able to give them back. The merge is
    /// idempotent, so the two snapshots crossing in flight converge rather than
    /// fight.
    /// Who travels, and it is emphatically not everybody.
    ///
    /// This used to send every `Player` row on the device. An install that has been
    /// played on for a while carries rows a party has no business knowing: the
    /// shared-device roster from before `DevicePlayer`, contributors to a shared
    /// book, people from last summer's trip. Sending the lot meant one person joining
    /// pushed their whole address book into everyone else's standings — "when Dean
    /// joined my party all his previous people came with it".
    ///
    /// The party's business is the people the party is about: whoever has a plate on
    /// this trip, whoever the party has already introduced, and this phone. That is
    /// exactly `participants`, which the standings strip already uses — so the roster
    /// that travels and the roster that is drawn cannot disagree.
    private func greet(_ peer: MCPeerID) {
        let everyone = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        let me = DevicePlayer.resolve(from: everyone)

        if let trip = localTrip() {
            let roster = trip.participants(from: everyone, me: me,
                                           alsoPlaying: knownPlayerIDs)
            send(.hello(PartyMerge.snapshot(of: trip, players: roster,
                                            hostPlayerID: role == .host ? me?.id : nil,
                                            rules: rules,
                                            tombstones: tombstones)),
                 to: [peer])
        } else {
            // No trip yet, so there is nothing to say but "this is who I am". A guest
            // still browsing has no roster worth sending and never did.
            send(.roster([me].compactMap { $0 }.map(PartyMerge.event(for:))), to: [peer])
        }
    }

    // MARK: - Listening

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        let envelope: PartyEnvelope?
        do {
            envelope = try PartyEnvelope.decoded(from: data)
        } catch {
            trouble = "Could not read a message from \(peer.displayName)."
            return
        }
        guard let envelope else {
            trouble = "\(peer.displayName) is running a different version of Plates."
            return
        }

        // Handled here rather than in the merge, because it is about the party and
        // not about the data — there is nothing in a goodbye to write down.
        if case .bye = envelope.payload { return saidGoodbye(peer) }

        let knownBefore = knownPlayerIDs
        switch envelope.payload {
        case .hello(let snapshot):
            knownPlayerIDs.formUnion(snapshot.players.map(\.id))
            adoptRules(snapshot.trip)
        case .roster(let events):
            knownPlayerIDs.formUnion(events.map(\.id))
        case .tripUpdate(let event):
            adoptRules(event)
        default:
            break
        }

        let wasThere = localTrip() != nil
        let outcome = PartyMerge.apply(envelope, into: context, tombstones: tombstones)

        // A guest that has just been handed the trip should be *looking* at it.
        // Joining a party and still seeing your own unrelated trip would make the
        // whole thing look broken.
        if role == .guest, !wasThere, let trip = localTrip() {
            PlaySelection.select(.trip(trip))
        }

        // Only a live find is worth mentioning. A snapshot lands dozens of plates at
        // once and is not news — it is the party catching you up.
        if case .sighting(let event) = envelope.payload, outcome.sightingsAdded > 0 {
            announce(event, from: peer)
        }

        // Somebody new, so introduce them around.
        //
        // Guests are connected to the host and to nobody else, so the host is the
        // only device that can tell one guest about another. It used to happen by
        // accident, as a side effect of every greeting carrying the whole address
        // book; now that a greeting carries only the party, the introduction has to
        // be deliberate. After the merge, not before — the new player's row has to
        // exist locally before `participants` will include it.
        //
        // Cannot loop: only the host relays, only when its own set actually grew, and
        // a snapshot is idempotent, so a guest that already knows everyone in it has
        // nothing to pass on.
        if role == .host, knownPlayerIDs != knownBefore {
            for other in session.connectedPeers where other != peer { greet(other) }
        }
    }

    /// Somebody left on purpose, which is a different thing from dropping out.
    ///
    /// The host leaving ends the party for everyone: there is no handoff in this
    /// version, and a guest left hunting for a host that has deliberately gone would
    /// sit there re-inviting a phone that will never answer. Nothing is lost by it —
    /// every device keeps its full copy of the trip and carries on collecting alone,
    /// and if the host starts the party again it is the same trip id, so everyone
    /// merges straight back together.
    private func saidGoodbye(_ peer: MCPeerID) {
        if role == .guest, peer == hostPeer {
            hasEnded = true
            trouble = "The host ended the party. Your plates are all still here."
            stop()
        } else {
            disconnected(peer)
        }
    }

    /// The host's word on how the party plays. Guests only — a host that adopted
    /// rules from an incoming message could have its own settings overwritten by
    /// somebody else's stale snapshot.
    private func adoptRules(_ event: TripEvent) {
        guard role == .guest, event.id == tripID, let sent = event.rules else { return }
        rules = sent
        PartyLedger.shared.setRules(sent, for: tripID)
    }

    private func announce(_ event: SightingEvent, from peer: MCPeerID) {
        guard let plate = Plate.plate(for: event.plateCode) else { return }
        let finder = event.playerID
            .flatMap { id in
                try? context.fetch(
                    FetchDescriptor<Player>(predicate: #Predicate { $0.id == id })).first
            }?
            .name ?? peer.displayName
        latestFromPeer = PeerFind(
            plateName: plate.name,
            finder: finder,
            tier: RarityTier.forRarity(event.rarityWhenSpotted ?? plate.points))
    }

    fileprivate func connected(_ peer: MCPeerID) {
        if !members.contains(peer.displayName) { members.append(peer.displayName) }
        isConnected = !session.connectedPeers.isEmpty
        trouble = nil
        // We are in. Only now is this a party worth silently reconnecting to.
        if role == .guest, peer == hostPeer {
            hasJoined = true
            settleJoin()
        }
        greet(peer)
    }

    fileprivate func disconnected(_ peer: MCPeerID) {
        members.removeAll { $0 == peer.displayName }
        isConnected = !session.connectedPeers.isEmpty

        // A refused invitation arrives here rather than as an error, and it is the
        // one disconnection that is not a dropout: we were never in. Checked first,
        // because the two want opposite things said and opposite things done.
        if let target = joining, peer == target.peer, !hasJoined { return joinFailed() }

        // Not an error, and deliberately not reported as one. Dropping out is the
        // normal state of a phone in a pocket; the browser is still running and
        // `found` puts it straight back the moment the host is in range again.
        if role == .guest, peer == hostPeer, hasJoined, !hasEnded {
            trouble = "Lost the party \u{2014} looking for it again\u{2026}"
        }
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard role == .guest,
              let raw = info?["id"], let id = UUID(uuidString: raw) else { return }

        // The party we are already in, back in range. Straight back in, no tapping.
        //
        // Matched on the advertised *trip*, not on the peer. An `MCPeerID` is only
        // meaningful for as long as the process that made it lives, so a host whose
        // app restarted comes back as a different peer with the same name — and
        // comparing peers would leave us hunting a phone that no longer exists while
        // the actual party advertised beside us. The trip id is the party's identity;
        // the peer is just where it happens to be answering from.
        if hasJoined, id == tripID {
            hostPeer = peer
            return rejoin(peer)
        }

        guard !nearby.contains(where: { $0.peer == peer }) else { return }
        nearby.append(Nearby(peer: peer, tripID: id,
                             tripName: info?["trip"] ?? "A trip",
                             hostName: info?["host"] ?? peer.displayName))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        nearby.removeAll { $0.peer == peer }
    }

    /// The host is the only side that can answer this, because it is the only side
    /// that knows the code.
    fileprivate func shouldAdmit(_ peer: MCPeerID, offering context: Data?) -> Bool {
        guard role == .host else { return false }
        let offered = context.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return Self.tidy(offered) == code
    }

    fileprivate func failed(_ what: String) { trouble = what }

    // MARK: - Bits

    private func localTrip() -> Trip? {
        let id = tripID
        return try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first
    }

    /// No `O`/`0` or `I`/`1`: the code is read off one screen and typed into another,
    /// usually by a passenger, usually in a moving car.
    private static func freshCode() -> String {
        #if DEBUG
        // `-partyCode ABCD` pins it, which is what makes a two-device test possible
        // without a human reading one screen and typing into the other.
        let args = ProcessInfo.processInfo.arguments
        if let at = args.firstIndex(of: "-partyCode"), at + 1 < args.count {
            return tidy(args[at + 1])
        }
        #endif
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }

    private static func tidy(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// The delegate callbacks, and nothing else.
///
/// A separate object because every method here is called on one of the framework's
/// own queues, and `PartySession` is `@MainActor`. Keeping the hop in one place
/// means no piece of party state is ever touched from the wrong thread, and the
/// session itself never has to think about it.
private final class PartyTransport: NSObject, MCSessionDelegate,
                                    MCNearbyServiceAdvertiserDelegate,
                                    MCNearbyServiceBrowserDelegate {
    private weak var owner: PartySession?

    init(owner: PartySession) { self.owner = owner }

    // MARK: Session

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak owner] in
            switch state {
            case .connected:    owner?.connected(peerID)
            case .notConnected: owner?.disconnected(peerID)
            default:            break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak owner] in owner?.received(data, from: peerID) }
    }

    // Unused, and required. The party sends small messages and nothing else.
    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: Advertising

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak owner] in
            guard let owner, owner.shouldAdmit(peerID, offering: context) else {
                return invitationHandler(false, nil)
            }
            invitationHandler(true, owner.mcSession)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak owner] in
            owner?.failed("Could not start the party. \(error.localizedDescription)")
        }
    }

    // MARK: Browsing

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak owner] in owner?.found(peerID, info: info) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak owner] in owner?.lost(peerID) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak owner] in
            owner?.failed("Could not look for parties. \(error.localizedDescription)")
        }
    }
}

extension PartySession {
    /// Handed to the invitation handler, which needs the real `MCSession`.
    fileprivate var mcSession: MCSession { session }
}
