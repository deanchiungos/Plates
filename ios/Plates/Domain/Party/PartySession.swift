import Foundation
import MultipeerConnectivity
import Observation
import SwiftData

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

        var id: String { peer.displayName }
    }

    // MARK: - State the UI reads

    let role: Role
    /// Known up front when hosting. A guest learns it from the advertisement, before
    /// connecting — which is why it can be non-optional here.
    let tripID: UUID
    /// Four characters, shown by the host and typed by everyone else. Not in the
    /// advertisement: a code anyone browsing could simply read would authorise
    /// nothing. It is sent with the invitation and checked by the host.
    let code: String

    private(set) var members: [String] = []
    private(set) var nearby: [Nearby] = []
    private(set) var isConnected = false
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
    func join(_ party: Nearby, code entered: String) {
        guard role == .guest, let browser else { return }
        let joined = PartySession(role: .guest, tripID: party.tripID,
                                  code: Self.tidy(entered), name: myName, context: context)
        joined.startBrowsing()
        PartySession.shared = joined

        // The invite has to go out on the *new* session, since that is the one whose
        // peers will end up connected.
        joined.invite(party)
        self.stop()
    }

    private func invite(_ party: Nearby) {
        guard let browser, let context = code.data(using: .utf8) else { return }
        browser.invitePeer(party.peer, to: session, withContext: context, timeout: 20)
    }

    // MARK: - Leaving

    func leave() {
        send(.bye)
        stop()
        if PartySession.shared === self { PartySession.shared = nil }
    }

    private func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session.disconnect()
        isConnected = false
        members = []
        nearby = []
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
    private func greet(_ peer: MCPeerID) {
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        if let trip = localTrip() {
            send(.hello(PartyMerge.snapshot(of: trip, players: players,
                                            hostPlayerID: role == .host ? players.first?.id : nil,
                                            tombstones: tombstones)),
                 to: [peer])
        } else {
            send(.roster(players.map(PartyMerge.event(for:))), to: [peer])
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

        let wasThere = localTrip() != nil
        PartyMerge.apply(envelope, into: context, tombstones: tombstones)

        // A guest that has just been handed the trip should be *looking* at it.
        // Joining a party and still seeing your own unrelated trip would make the
        // whole thing look broken.
        if role == .guest, !wasThere, let trip = localTrip() {
            PlaySelection.select(.trip(trip))
        }
    }

    fileprivate func connected(_ peer: MCPeerID) {
        if !members.contains(peer.displayName) { members.append(peer.displayName) }
        isConnected = !session.connectedPeers.isEmpty
        trouble = nil
        greet(peer)
    }

    fileprivate func disconnected(_ peer: MCPeerID) {
        members.removeAll { $0 == peer.displayName }
        isConnected = !session.connectedPeers.isEmpty
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard role == .guest,
              let raw = info?["id"], let id = UUID(uuidString: raw),
              !nearby.contains(where: { $0.peer == peer }) else { return }
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
