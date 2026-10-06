import Foundation
import MultipeerConnectivity
import Network
import Observation
import os
import SwiftData
import UIKit
import dnssd

/// Every transport event a party goes through, for reading off a real phone.
///
/// Parties fail on real networks in ways two simulators on one Mac cannot show — a
/// car hotspot that walls phones off from each other, a phone that drops out of a
/// session the other one still believes in — and the only witness is the phone. In
/// Console.app, filter on `subsystem:com.tagsmedia.tags category:party`.
private let partyLog = Logger(subsystem: "com.tagsmedia.tags", category: "party")

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
    static var shared: PartySession? { PartyHost.shared.session }

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

    /// Who else is connected right now.
    ///
    /// Presence still comes from the session — connect adds, disconnect removes —
    /// but each one carries a player id where the sender has told us one, so the
    /// screen can show the name they go by *now* rather than the one their peer id
    /// was minted with. See `PartyEnvelope.from`.
    private(set) var members: [Member] = []

    struct Member: Identifiable, Equatable {
        let peer: MCPeerID
        /// The name their `MCPeerID` was created with. A fallback, and a frozen one.
        let peerName: String
        /// Nil until they have said something. See `PartyEnvelope.from`.
        var playerID: UUID?

        /// The peer itself, not its name. A guest that drops out and comes back does
        /// so under a new peer id with the same name (see `restartDiscovery`), and
        /// for the moment both are in the session the two rows shared an id — so the
        /// `ForEach` drew one of them, and not reliably the live one.
        var id: MCPeerID { peer }
    }
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
    /// Who this phone is to the others. Fixed for a host; a guest takes a new one
    /// every time it has to knock again. See `restartDiscovery`.
    private var peerID: MCPeerID
    /// TEMPORARY — counts fresh identities, for the party log. See `PartyDiagnostics`.
    private var identityGeneration = 0
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var transport: PartyTransport!
    private var foregroundWatch: NSObjectProtocol?

    /// Whether the host's session has ever held this phone's current `peerID`.
    ///
    /// From the moment the host accepts an invitation, its `MCSession` keeps a record
    /// of that peer id, and nothing on the guest's side can clear it: if the link then
    /// dies quietly — a locked phone, a frozen app, a radio that gave up — the host
    /// goes on believing the guest is there until its own keepalive times out. Knock
    /// again under the same id inside that window and the host accepts an invitation
    /// from a peer it thinks is already connected, which fails. That was "Dean can't
    /// get back in, and Anna's phone still shows him". Once spent, an id is never
    /// used to knock again.
    private var identitySpent = false

    /// The host a reconnect invitation has gone to and not come back from, so a
    /// second sighting of the same host does not tear down the attempt in flight.
    private var rejoinPending: MCPeerID?

    /// The loop that keeps trying to get back in after a drop. See `scheduleReconnect`.
    private var reconnectWatch: Task<Void, Never>?
    private var reconnectTries = 0

    /// Seconds before each successive reconnect attempt, then the last one forever.
    /// Quick at first, because most drops are a phone waking up from the pocket;
    /// never so slow that a car pulling back into range waits long.
    private static let reconnectBackoff: [Double] = [1, 2, 4, 8, 15]

    /// A join the host accepted and the radio then lost, waiting for the fresh
    /// browser to find the host again so it can knock under a new id. See
    /// `knock(_:)`.
    private var awaitingRediscovery = false

    /// Whether this phone is joined to a Wi-Fi network, for the failure messages.
    ///
    /// The field report was exact: no connection on Wi-Fi, a connection on cellular.
    /// MultipeerConnectivity prefers the Wi-Fi network when both phones are on one,
    /// and plenty of networks — car hotspots, hotels, guest Wi-Fi — keep the phones
    /// on them from reaching each other. Off the network the same two phones talk
    /// directly over peer-to-peer Wi-Fi and Bluetooth, which is why cellular worked.
    /// The transport cannot report which of those it tried, so the advice has to be
    /// conditional on the one thing the phone can see.
    private var onWiFi = false
    private var pathWatch: NWPathMonitor?

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
    private(set) var hasJoined = false

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

    /// When the current invitation left, so a failure can be dated against the
    /// deadline. See `disconnected` for why the date matters.
    private var invitedAt: Date?

    /// How many times a join is tried before the guest is told it failed.
    ///
    /// Three, and each on a session of its own. One attempt was never enough for the
    /// case that actually happens: a connection accepted and then lost leaves state
    /// behind that only a new session clears, so the first failure used to guarantee
    /// every subsequent one.
    private static let joinAttempts = 3
    private var attemptsLeft = 0

    /// Peers that have reached `.connecting`.
    ///
    /// The one thing that tells a declined invitation apart from an accepted one
    /// whose connection then failed, and it was being thrown away. See
    /// `disconnected`.
    private var handshaking: Set<MCPeerID> = []

    /// Takes a passing complaint back down. See `sayBriefly`.
    private var troubleFade: Task<Void, Never>?

    /// How long to wait for the host's phone to answer at all.
    ///
    /// Thirty seconds, which is Apple's own default on `invitePeer`, and it used to
    /// be twelve. Twelve is generous between two simulators — they talk over the
    /// Mac's loopback and connect almost instantly — and every party test this
    /// feature has had was simulator to simulator. On real phones the first
    /// connection has to bring up peer-to-peer Wi-Fi, which routinely takes ten to
    /// twenty seconds, so twelve was a coin toss that the app reported as a wrong
    /// code. Waiting is cheap and the guest is watching a spinner either way;
    /// telling somebody their code is wrong when it is not costs them the drive.
    private static let inviteTimeout: TimeInterval = 30

    /// Why a join did not happen. The three are genuinely different situations with
    /// genuinely different fixes, and the app used to say the same sentence for all
    /// of them — the one about checking the code, which is the right advice for
    /// exactly one.
    enum JoinFailure: Equatable {
        /// The host's phone answered, and said no. It is the only phone that knows
        /// the code, so this is as close to "wrong code" as the transport can get.
        case refused
        /// Nothing came back before the deadline. The host may be out of range, may
        /// have closed the party, or may never have heard the invitation.
        case silence
        /// The host stopped advertising while we were waiting.
        case vanished
        /// The host let us in and the connection did not survive being made. Nothing
        /// to do with the code — it was accepted.
        case dropped
    }

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

    /// iOS is refusing this app the local network, so nothing nearby can be seen.
    ///
    /// The one failure that looks exactly like an empty car. With Local Network off
    /// for the app, MultipeerConnectivity neither finds anybody nor says why: the
    /// browser starts, the advertiser publishes, and both stay silent. The first field
    /// logs from real phones were precisely that, seventy seconds of two phones on
    /// the same seat with nothing in either list. MultipeerConnectivity cannot report
    /// it, but a Bonjour browser of our own can — iOS parks it in `waiting` with a
    /// policy-denied error until the permission is granted. See `watchAccess`.
    private(set) var localNetworkBlocked = false
    private var accessProbe: NWBrowser?

    /// A guest has been looking for a while and found nothing, with no refusal to
    /// explain it. Usually Wi-Fi or Bluetooth switched off outright, or the host's
    /// screen is locked. See `quietWatch`.
    private(set) var searchingQuietly = false
    private var quietWatch: Task<Void, Never>?

    /// The rules in force for a collection right now.
    ///
    /// Only while a party is actually running on it. Once the party ends, the trip
    /// on your phone is *your copy* and the ordinary rules resume — protecting the
    /// claims of somebody who is no longer in the car would be guarding a scoreboard
    /// against its only remaining player. Deliberately keyed on the session rather
    /// than on being connected, so a phone that drops out for a minute does not
    /// briefly get permission to strip the board.
    ///
    /// The fallback is `.solo`, not `.standard`. They differ in exactly the way that
    /// matters here: `.standard` protects claims, and returning it off a party meant
    /// every collection with no live session — every book, every finished trip, every
    /// launch before anybody hosts anything — quietly enforced party protection, so a
    /// plate anybody else had ever claimed could never be taken back again.
    ///
    /// A guest also has to have actually got in. `join` writes `tripID` and `rules`
    /// before the invitation goes out, and a refusal leaves both set — so without
    /// `hasJoined` a mistyped code would put a party's rules in force on a party
    /// that never formed. The host has no equivalent test and needs none: hosting
    /// is live from the moment it starts.
    static func rules(for collection: UUID) -> PartyRules {
        guard let party = shared, party.tripID == collection, !party.hasEnded,
              party.role == .host || party.hasJoined else {
            return .solo
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
        let code = Self.code(for: trip.id)
        let party = PartySession(role: .host, tripID: trip.id, code: code,
                                 name: name, context: context)
        // Whatever this trip was played by last time, if it has been a party before.
        party.rules = PartyLedger.shared.rules(for: trip.id)
        PartyLedger.shared.note(trip: trip.id, role: "host", rules: party.rules, code: code)
        party.startAdvertising(tripName: trip.name)
        PartyHost.shared.session = party
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
        PartyHost.shared.session = party
        return party
    }

    // `tombstones` is resolved in the body rather than defaulted in the signature.
    // A default argument expression is evaluated in the *caller's* isolation, which
    // for a `@MainActor` singleton means the compiler cannot prove it is safe —
    // Swift 6 rejects it outright. The body is main-actor by construction. No
    // caller ever passed one, so the parameter is gone with it; the harness injects
    // its memory-only ledger into `PartyMerge.apply`, not into a session.
    private init(role: Role, tripID: UUID, code: String,
                 name: String, context: ModelContext) {
        self.role = role
        self.tripID = tripID
        self.code = code
        self.context = context
        self.tombstones = .shared
        // Trimmed to what `MCPeerID` accepts: non-empty, and 63 bytes at the outside.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trimmed by *bytes*, not characters. `MCPeerID` rejects a display name over
        // 63 UTF-8 bytes by throwing, and thirty characters of emoji is comfortably
        // past that — a name like "Dean🗡️🍫" is fifteen bytes for eight characters.
        // A crash on entering the party screen is not a thing to leave to taste in
        // nicknames.
        self.myName = trimmed.isEmpty ? "Someone" : Self.fitting(trimmed)
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

        let watch = NWPathMonitor(requiredInterfaceType: .wifi)
        watch.pathUpdateHandler = { [weak self] path in
            let joined = path.status == .satisfied
            Task { @MainActor in self?.onWiFi = joined }
        }
        watch.start(queue: .global(qos: .utility))
        pathWatch = watch
        watchAccess()

        partyLog.notice("\(role == .host ? "hosting" : "browsing", privacy: .public) as \(self.myName, privacy: .public)")
        diag("session.start", ["name": myName, "trip": tripID.uuidString])
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
        diag("advertise.start", ["trip": tripName, "code": code])
    }

    private func startBrowsing() {
        let finder = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.service)
        finder.delegate = transport
        finder.startBrowsingForPeers()
        browser = finder
        if !hasJoined { watchForQuiet() }
        diag("browse.start")
    }

    /// Whether a delegate callback came from the browser in use, rather than one
    /// `restartDiscovery` has already thrown away. Same reason as `isCurrent(_:)` for
    /// sessions: `invitePeer` on a peer some other browser found fails silently.
    func isCurrent(_ candidate: MCNearbyServiceBrowser) -> Bool { candidate === browser }

    /// Looks for the party again from scratch, as a peer the host has never seen.
    ///
    /// A new `MCPeerID`, a new session and a new browser, all three — they are bound
    /// to each other, so none can be replaced alone. Two problems are solved at once:
    ///
    /// - **The host may still be holding the old id.** See `identitySpent`. A new id
    ///   is somebody the host's session has no record of, so it cannot collide with
    ///   the ghost of the connection that just died.
    /// - **A browser does not repeat itself.** `foundPeer` fires once per peer, and a
    ///   browser that has already reported the host stays silent about it for as
    ///   long as it thinks the host never left — which, for a host that only
    ///   blinked, is the whole time. Reconnecting was driven by that callback alone,
    ///   so one failed attempt left the guest on "Looking for it again" for the rest
    ///   of the drive with the party sitting two feet away. A brand new browser
    ///   reports everything it can see, at once.
    ///
    /// The old browser's delegate is cut first, so nothing it was about to say lands
    /// on the new one. `nearby` is emptied with it: the dead browser will never
    /// report those rows lost, and the new one refills the list within a second.
    private func restartDiscovery() {
        guard role == .guest, !hostLinked else { return }
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        session.disconnect()

        peerID = MCPeerID(displayName: myName)
        identityGeneration += 1
        diag("identity.new")
        identitySpent = false
        rejoinPending = nil
        session = MCSession(peer: peerID, securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = transport
        handshaking.removeAll()
        members = []
        isConnected = false
        nearby = []
        startBrowsing()
        partyLog.notice("rediscovering under a fresh peer id")
    }

    /// Whether this guest's link to the host is up. Not `isConnected`: in a party of
    /// three the guests also link to each other, so a guest that has lost the host
    /// can still be "connected" — to someone who cannot relay the host's word.
    private var hostLinked: Bool {
        guard let hostPeer else { return false }
        return session.connectedPeers.contains(hostPeer)
    }

    private var needsReconnect: Bool {
        role == .guest && hasJoined && !hasEnded && !hostLinked
    }

    /// Keeps trying to get back into the party until it works or the party ends.
    ///
    /// Each round starts discovery over under a fresh identity and gives the knock
    /// that follows as long as an invitation is allowed to take; a round that comes
    /// to nothing schedules the next. A failed knock ends its round early through
    /// `disconnected`. Nothing here depends on a callback the framework might not
    /// send, which is the property the old single-shot `rejoin` lacked.
    private func scheduleReconnect(immediately: Bool = false) {
        guard needsReconnect else { return }
        reconnectWatch?.cancel()
        let backoff = Self.reconnectBackoff
        let wait = immediately ? 0 : backoff[min(reconnectTries, backoff.count - 1)]
        reconnectTries += 1
        diag("reconnect.schedule", ["try": "\(reconnectTries)", "wait": "\(wait)"])
        partyLog.notice("reconnect attempt \(self.reconnectTries) in \(wait)s, wifi=\(self.onWiFi)")
        reconnectWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.needsReconnect else { return }
            // Unless a sighting has already started one: `found` knocks the moment
            // the host reappears, and starting over now would kill that knock.
            self.diag("reconnect.round", ["rejoinPending": "\(self.rejoinPending != nil)"])
            if self.rejoinPending == nil { self.restartDiscovery() }
            try? await Task.sleep(for: .seconds(Self.inviteTimeout + 2))
            guard !Task.isCancelled, self.needsReconnect else { return }
            self.scheduleReconnect()
        }
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
        guard role == .guest, browser != nil else { return }

        // Everything a fresh session used to get for free. Joining once built a new
        // `PartySession`, so every per-attempt flag started clear by construction;
        // mutating the live one instead means each has to be cleared by hand, and the
        // ones missed here are not cosmetic. `hasJoined` is what tells a refusal from
        // a dropout, so carrying it over from a previous party makes a mistyped code
        // report as "Lost the party" and then time out saying nothing answered.
        // `knownPlayerIDs` is the roster: carried over, the last party's people appear
        // in this trip's standings on zero, and `greet` pushes them to this host, who
        // relays them to everybody. `hasEnded` would leave the new party looking over
        // before it started. `members` is rebuilt by `invite`, and `latestFromPeer` is
        // cleared so a stale find cannot be read as this party's first.
        hasJoined = false
        hasEnded = false
        knownPlayerIDs = []
        latestFromPeer = nil

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
        //
        // Read from the ledger, but no longer written to it here. Writing on the
        // attempt meant a wrong code, a mistyped tap or a host out of range left a
        // permanent record that this device had been a guest of a trip it never
        // reached — `wasParty` true, a party badge, and rules for a party that
        // never happened. The record is written in `connected`, which is the moment
        // it becomes a fact.
        rules = PartyLedger.shared.rules(for: party.tripID)
        attemptsLeft = Self.joinAttempts
        diag("join.tap", ["host": Self.tag(party.peer), "trip": party.tripName, "code": code])
        knock(party)
    }

    /// Invites the host — under an identity it has never seen, rediscovering first if
    /// the one in hand is spent.
    ///
    /// Retrying a join used to rebuild the session and knock again under the same
    /// peer id. The guest's half was clean; the host's was not. An invitation the
    /// host accepted and the radio then lost leaves that id in the host's session
    /// until its keepalive gives up, so the second and third attempts landed on a
    /// connection the host still believed in — and failed the same way, for a
    /// reason nothing on the guest's side could see. "It didn't connect over
    /// either" is what three doomed retries look like from the back seat.
    ///
    /// A fresh id needs a fresh browser, because `invitePeer` only works on the
    /// browser that found the peer — so the knock waits for the new browser to
    /// report the host, in `found`. The watchdog covers the host not turning up.
    private func knock(_ target: Nearby) {
        diag("join.knock", ["host": Self.tag(target.peer), "attemptsLeft": "\(attemptsLeft)"])
        guard identitySpent else { return invite(target) }
        awaitingRediscovery = true
        restartDiscovery()
        joinWatch?.cancel()
        joinWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.inviteTimeout + 1))
            guard !Task.isCancelled, let self, self.awaitingRediscovery else { return }
            self.awaitingRediscovery = false
            self.joinFailed(.silence)
        }
    }

    /// Sends the invitation, on a session that has never failed.
    ///
    /// The rebuild is the point. `MCSession` does not recover from a connection that
    /// was accepted and then collapsed: every later `invitePeer` into the same
    /// session collapses the same way, which is why the report was "it kept failing
    /// every time they tried it" rather than "it was flaky". Tapping the party again
    /// looked like a fresh attempt and was not one. The browser is deliberately left
    /// alone: `invitePeer` only works on the browser that discovered the peer, so
    /// rebuilding that would throw away the discovery this is about to use.
    private func invite(_ target: Nearby) {
        guard role == .guest, let browser,
              let payload = code.data(using: .utf8) else { return }
        rebuildSession()
        invitedAt = Date()
        partyLog.notice("inviting \(target.hostName, privacy: .public), \(self.attemptsLeft) attempt(s) left, wifi=\(self.onWiFi)")
        diag("invite.send", ["host": Self.tag(target.peer), "attemptsLeft": "\(attemptsLeft)"])
        browser.invitePeer(target.peer, to: session, withContext: payload,
                           timeout: Self.inviteTimeout)

        joinWatch?.cancel()
        joinWatch = Task { @MainActor [weak self] in
            // A second past the invitation's own deadline, so the framework gets to
            // report the failure itself where it can, and this only covers the case
            // where it says nothing at all.
            try? await Task.sleep(for: .seconds(Self.inviteTimeout + 1))
            guard !Task.isCancelled else { return }
            self?.joinFailed(.silence)
        }
    }

    /// A brand new `MCSession`, because the old one cannot be trusted to connect.
    ///
    /// Guest only, and only while nothing is connected. On a host the session holds
    /// everybody in the car, and throwing it away to fix one joiner would drop them
    /// all.
    /// Whether a delegate callback belongs to the session in use, rather than one
    /// `rebuildSession` has already discarded. See `PartyTransport`.
    func isCurrent(_ candidate: MCSession) -> Bool { candidate === session }

    private func rebuildSession() {
        guard role == .guest, !hostLinked else { return }
        diag("session.rebuild")
        session.disconnect()
        session = MCSession(peer: peerID, securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = transport
        handshaking.removeAll()
        members = []
        // The discarded session's goodbyes are filtered out as stale, so nothing
        // else will clear this — and a guest that still had a link to another guest
        // when it lost the host would go on reading as connected to nobody.
        isConnected = false
    }

    /// The host never let us in, and *why* is the whole of what the guest needs.
    ///
    /// This used to say one sentence — check the four characters — no matter what
    /// had happened. That is correct advice for a refusal and actively misleading
    /// for the other two: somebody whose phone simply never heard the invitation
    /// spent the drive retyping a code that was right all along. The transport
    /// cannot hand us a reason, but the *call site* is the reason: a refusal comes
    /// back as a disconnection, silence comes from our own watchdog, and a host that
    /// stops advertising comes from the browser. See `JoinFailure`.
    ///
    /// The party goes back in the list either way, because all three are worth
    /// trying again.
    private func joinFailed(_ why: JoinFailure) {
        guard let target = joining else { return }
        diag("join.failed", ["why": "\(why)", "host": Self.tag(target.peer)])
        settleJoin()
        // `hostPeer` deliberately survives. Clearing it here looked like tidying up
        // and was the opposite: `connected` gates every join side effect on
        // `peer == hostPeer`, so an invitation that lands a second after the watchdog
        // gave up — which peer-to-peer Wi-Fi does routinely — produced a guest who was
        // genuinely in the party and receiving plates, but never *joined*: no ledger
        // record, no rules adopted, no badge, no automatic rejoin after the first
        // pocket-drop, and offered "Start a Party" for a trip somebody else is already
        // hosting. Nothing needs it nil. Everything that could misread a stale
        // `hostPeer` is already gated on `hasJoined`, which is false until a
        // connection actually arrives.
        //
        // Back in the list to be tapped again — except when the host has stopped
        // advertising, where re-adding it would put a row on screen that cannot
        // work. `lost` has just taken it out, and `found` puts it straight back if
        // the party returns; listing a phone that is not there is how this screen
        // got its reputation.
        //
        // Matched on the trip, not the peer, for the same reason `found` is: a host
        // whose app restarted comes back under a new `MCPeerID` with the same name,
        // and `found` has already swapped the row. Asking whether this dead *peer* is
        // listed then says no, and appending it puts two rows on screen whose
        // `Identifiable` id — name and trip — is byte-identical.
        if why != .vanished, !nearby.contains(where: { $0.tripID == target.tripID }) {
            nearby.append(target)
        }

        partyLog.error("join failed: \(String(describing: why), privacy: .public), wifi=\(self.onWiFi)")
        switch why {
        case .refused:
            trouble = String(localized: "\(target.hostName)'s phone turned you away, which almost always means the four characters did not match. Check the code showing on it and tap \(target.tripName) again.")
        case .silence where onWiFi:
            trouble = String(localized: "No answer from \(target.hostName)'s phone. Some Wi-Fi networks, like car and hotel hotspots, stop phones reaching each other. On both phones, tap Wi-Fi in Control Center to disconnect from the network, but leave Wi-Fi on in Settings: the phones use it to reach each other directly. Then tap \(target.tripName) again.")
        case .silence:
            trouble = String(localized: "No answer from \(target.hostName)'s phone. Make sure the party is still open on it, keep the phones in the same car, and tap \(target.tripName) again.")
        case .vanished:
            trouble = String(localized: "\(target.hostName)'s phone stopped advertising \(target.tripName). If the party is still running, wait a moment and tap it again.")
        case .dropped where onWiFi:
            // The reported failure exactly: no connection on Wi-Fi, a connection on
            // cellular. Off the network the phones talk to each other directly, so
            // the network is the first thing to take out of the way. See `onWiFi`.
            trouble = String(localized: "Your code was right and \(target.hostName)'s phone accepted it, but the connection would not hold. Some Wi-Fi networks, like car and hotel hotspots, stop phones reaching each other. On both phones, tap Wi-Fi in Control Center to disconnect from the network, but leave Wi-Fi on in Settings: the phones use it to reach each other directly. Then tap \(target.tripName) again.")
        case .dropped:
            // Names the thing that actually causes this once retrying has failed.
            // Local Network is the one setting that lets two phones see each other
            // and refuse to connect, it is off by accident more often than not, and
            // nothing in the transport reports it, so the app has to say it out loud.
            trouble = String(localized: "Your code was right and \(target.hostName)'s phone accepted it, but the connection would not hold after three tries. On both phones, open Settings, find Tags, and check that Local Network is on. Then tap \(target.tripName) again.")
        }
    }

    /// The invitation is no longer outstanding, however it ended.
    private func settleJoin() {
        joinWatch?.cancel()
        joinWatch = nil
        joining = nil
        invitedAt = nil
        awaitingRediscovery = false
    }

    /// Back again after a drop.
    ///
    /// Silent and automatic, because the thing that caused it was almost certainly
    /// somebody's phone locking itself, and asking them to re-enter a code for that
    /// would be the app blaming them for its own transport. The code is still held
    /// from the first join, so the host's check is satisfied exactly as before.
    private func rejoin(_ peer: MCPeerID) {
        guard needsReconnect, rejoinPending == nil,
              let browser, let payload = code.data(using: .utf8) else { return }
        // Never under an id the host has already held. See `identitySpent`. The new
        // browser reports the host again, and that sighting comes back through here.
        if identitySpent {
            diag("rejoin.needsFreshId", ["host": Self.tag(peer)])
            return restartDiscovery()
        }
        // Same reason as `invite`: the session we just dropped out of is the one
        // least likely to let us back in.
        rebuildSession()
        rejoinPending = peer
        diag("rejoin.send", ["host": Self.tag(peer)])
        partyLog.notice("rejoining \(peer.displayName, privacy: .public), wifi=\(self.onWiFi)")
        browser.invitePeer(peer, to: session, withContext: payload,
                           timeout: Self.inviteTimeout)
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
        diag("wake", ["ended": "\(hasEnded)", "needsReconnect": "\(needsReconnect)"])
        guard !hasEnded else { return }
        partyLog.notice("woke up, \(self.session.connectedPeers.count) peer(s) still attached")

        if let advertiser {
            advertiser.stopAdvertisingPeer()
            advertiser.startAdvertisingPeer()
        }
        // A guest that lost the host while asleep goes straight back to knocking,
        // fresh identity and all, rather than restarting a browser that may have
        // nothing new to say. Counted from zero: waking is a new start, not the
        // tenth failure in a row.
        if needsReconnect {
            reconnectTries = 0
            scheduleReconnect(immediately: true)
        } else if let browser {
            browser.stopBrowsingForPeers()
            browser.startBrowsingForPeers()
        }
        for peer in session.connectedPeers { greet(peer) }
    }

    // MARK: - Leaving

    func leave() {
        // Marked over before the radios go, exactly as `saidGoodbye` does when the
        // host ends it. Without this the deferred `disconnect()` below arrives 0.4s
        // later as an ordinary drop and writes "Lost the party. Looking for it
        // again…" onto a party the user deliberately walked out of — reachable from
        // the Trips tab, where finishing or deleting a party trip calls this while
        // the Party screen is still holding the session.
        hasEnded = true
        diag("leave")
        send(.bye)
        // The goodbye needs a moment to actually leave the device. `send` hands the
        // data off asynchronously and `disconnect()` tears the connection down, so
        // going straight from one to the other drops it — and a peer that never hears
        // it cannot tell a deliberate exit from a dropout, so it spends the rest of
        // the drive politely trying to reconnect to somebody who has gone home.
        stop(gracePeriod: 0.4)
        if PartySession.shared === self { PartyHost.shared.session = nil }
    }

    private func stop(gracePeriod: TimeInterval = 0) {
        diag("stop", ["grace": "\(gracePeriod)"])
        // Before the radios go, or a watchdog left running reports a failed join
        // against a party the user has already walked away from.
        settleJoin()
        awaitingRediscovery = false
        reconnectWatch?.cancel()
        reconnectWatch = nil
        pathWatch?.cancel()
        pathWatch = nil
        accessProbe?.cancel()
        accessProbe = nil
        quietWatch?.cancel()
        quietWatch = nil
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
        // Resolved per send rather than cached, because the whole point is that it
        // can change: adopting a profile mid-party is exactly when this moves.
        let me = DevicePlayer.resolve(from: (try? context.fetch(FetchDescriptor<Player>())) ?? [])
        guard !targets.isEmpty else {
            diag("send.skip", ["kind": payload.diagnosticSummary, "why": "no peers"])
            return
        }
        guard let data = try? PartyEnvelope(payload, from: me?.id).encoded() else {
            diag("send.skip", ["kind": payload.diagnosticSummary, "why": "encode failed"])
            return
        }
        // TEMPORARY: was `try?`. A failed send is the most useful line in the log.
        do {
            try session.send(data, toPeers: targets, with: .reliable)
            diag("send", ["kind": payload.diagnosticSummary, "bytes": "\(data.count)",
                          "to": targets.map(Self.tag).joined(separator: ",")])
        } catch {
            diag("send.error", ["kind": payload.diagnosticSummary, "bytes": "\(data.count)",
                                "to": targets.map(Self.tag).joined(separator: ","),
                                "error": "\(error)"])
        }
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
            diag("recv.undecodable", ["from": Self.tag(peer), "bytes": "\(data.count)",
                                      "error": "\(error)"])
            trouble = String(localized: "Could not read a message from \(peer.displayName).")
            return
        }
        guard let envelope else {
            diag("recv.wrongVersion", ["from": Self.tag(peer), "bytes": "\(data.count)"])
            trouble = String(localized: "\(peer.displayName) is running a different version of Tags.")
            return
        }

        // Handled here rather than in the merge, because it is about the party and
        // not about the data — there is nothing in a goodbye to write down.
        diag("recv", ["from": Self.tag(peer), "kind": envelope.payload.diagnosticSummary,
                      "bytes": "\(data.count)", "player": envelope.from?.uuidString ?? "-"])
        if case .bye = envelope.payload { return saidGoodbye(peer) }

        // Anything they send tells us who they are, so the list can stop calling
        // them by the name their peer id was minted with.
        if let sender = envelope.from,
           let at = members.firstIndex(where: { $0.peer == peer }),
           members[at].playerID != sender {
            members[at].playerID = sender
            // The same person under an older peer id: somebody who dropped out and
            // came back (see `restartDiscovery`) before this phone's session noticed
            // the old link had died. The session drops the ghost when its keepalive
            // gives up; the list should not wait for it, or the screen shows two of
            // them — and, before the new one arrives, one who is not there at all.
            members.removeAll { $0.peer != peer && $0.playerID == sender }
        }

        let knownBefore = knownPlayerIDs
        switch envelope.payload {
        case .hello(let snapshot):
            knownPlayerIDs.formUnion(snapshot.players.map(\.id))
            noteHost(snapshot.hostPlayerID, peer: peer)
            adoptRules(snapshot.trip, from: peer)
        case .roster(let events):
            knownPlayerIDs.formUnion(events.map(\.id))
        case .tripUpdate(let event):
            adoptRules(event, from: peer)
        default:
            break
        }

        // Whether a removal is news, judged *before* the merge writes its tombstone.
        // Gating the relay on "we actually deleted something" would be wrong: a
        // removal for a plate this device had already dropped deletes nothing, and
        // the guests who still hold it would never be told.
        let removalIsNews: Bool = {
            guard case .remove(let event) = envelope.payload else { return false }
            return !event.sightingIDs.allSatisfy {
                tombstones.contains($0, in: event.tripID)
            }
        }()

        // Whether this peer gets to say what the trip *is* — its name, its scoring,
        // whether it has ended. A host is never told any of that by a guest, and a
        // guest only listens to the host it actually joined. The same test
        // `adoptRules` makes, applied to the rest of the trip's settings.
        let fromHost = role == .guest && peer == hostPeer

        let wasThere = localTrip() != nil
        let outcome = PartyMerge.apply(envelope, into: context,
                                       tombstones: tombstones, fromHost: fromHost)

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

        diag("recv.applied", ["from": Self.tag(peer), "outcome": "\(outcome)"])
        relay(envelope, from: peer, outcome: outcome, removalIsNews: removalIsNews)
    }

    /// A find, passed on to the guests who may not have heard it.
    ///
    /// Every guest invites the *host* into its own `MCSession`, so the party is
    /// assembled as a star. MultipeerConnectivity does then link the guests to each
    /// other — but it does so lazily, and whether that link exists by the time
    /// somebody taps a plate is a race.
    ///
    /// Measured, not assumed: with three simulators and no relay, the second guest
    /// missed the third guest's plate in roughly one run out of three, with the two
    /// outcomes produced by *identical* code minutes apart. When the link had formed,
    /// the find arrived directly and everything looked perfect; when it had not, the
    /// plate simply never appeared, and nothing in the app noticed or retried. That
    /// is the reported "the third player to join was missing the data", and it is
    /// invisible with two devices because every pair of them contains the host.
    ///
    /// So the host forwards live news rather than trusting the mesh. Only the host —
    /// a guest that relayed would be echoing into the same uncertainty — and only the
    /// two payloads that carry news. Snapshots are excluded deliberately: they are
    /// re-sent on every connection anyway, and forwarding one would push a guest's
    /// whole trip at another guest for no gain.
    ///
    /// Costs a duplicate when the direct link *did* form, which is free: the merge is
    /// idempotent, removals are tombstoned, and a no-op merge announces nothing — so
    /// nobody sees "Mia got Montana" twice.
    private func relay(_ envelope: PartyEnvelope, from peer: MCPeerID,
                       outcome: PartyMerge.Outcome, removalIsNews: Bool) {
        guard role == .host else { return }

        // Gated on the message having been news to us, which is what stops an echo
        // dead: something that arrives twice is a no-op the second time and is
        // therefore never forwarded twice.
        //
        // `.roster` is forwarded ungated, and has to be. It is how somebody's rename
        // travels, and it was reaching the host and going no further: guests are
        // linked to each other only by the same lazy mesh this whole function exists
        // to stop trusting, and the host's re-greet fires only when the roster *grew*
        // — which renaming a player everybody already knows never does. So in any
        // party past two phones, the third one kept calling somebody by their old
        // name for the rest of the drive.
        //
        // Ungated because the news test cannot see it: `Outcome` counts inserts, not
        // edits, so a rename merges to an empty outcome. Cheap to forward anyway —
        // `announceMe` only fires when somebody actually changes their name or avatar,
        // and the merge on the far side is idempotent.
        switch envelope.payload {
        case .sighting where outcome.sightingsAdded > 0,
             .remove   where removalIsNews,
             .roster:
            break
        default:
            return
        }

        let others = session.connectedPeers.filter { $0 != peer }
        guard !others.isEmpty else { return }
        send(envelope.payload, to: others)
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
        diag("bye.recv", ["from": Self.tag(peer), "isHost": "\(peer == hostPeer)"])
        if role == .guest, peer == hostPeer {
            hasEnded = true
            trouble = String(localized: "The host ended the party. Your plates are all still here.")
            stop()
        } else {
            disconnected(peer)
        }
    }

    /// Which player id belongs to the phone hosting.
    ///
    /// Travelled in every snapshot since the rules did and was read by nobody, which
    /// made "hosted by" a guess. Persisted so it survives the party — the trip editor
    /// names the host from it months later, and `PartyLedger` is where the rest of a
    /// party's identity already lives.
    private func noteHost(_ id: UUID?, peer: MCPeerID) {
        guard role == .guest, peer == hostPeer, let id else { return }
        PartyLedger.shared.note(trip: tripID, role: "guest", rules: rules,
                                hostName: peer.displayName, hostPlayerID: id)
    }

    /// The host's word on how the party plays.
    ///
    /// Guests only — a host that adopted rules from an incoming message could have
    /// its own settings overwritten by somebody else's stale snapshot — and only from
    /// the host's own peer. `broadcastTrip` guards the sending side, and a guarded
    /// sender with an unguarded receiver is half a rule: nothing stopped one guest
    /// handing another a `tripUpdate` that rewrote what a tap means for everybody.
    private func adoptRules(_ event: TripEvent, from peer: MCPeerID) {
        guard peer == hostPeer else { return }
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
        // The trip's own rarity when the sender did not bank one, rather than
        // `plate.points`. Those are the hand-assigned national numbers written from a
        // Northeast vantage point, which `PlateRarity` exists to replace — so the
        // toast announced an Alaska call-out as legendary while the grid an inch
        // below it said mythic. Reached only for a sender old enough not to send the
        // banked value, and it should still agree with the screen.
        let trip = try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == event.tripID })).first
        let rarity = event.rarityWhenSpotted
            ?? trip?.rarity(of: event.plateCode)
            ?? plate.points

        latestFromPeer = PeerFind(
            plateName: plate.name,
            finder: finder,
            tier: RarityTier.forRarity(rarity))
    }

    fileprivate func connecting(_ peer: MCPeerID) {
        handshaking.insert(peer)
        // The host has accepted, so its session now holds this id whatever happens
        // next. See `identitySpent`.
        if role == .guest, peer == hostPeer { identitySpent = true }
        partyLog.notice("connecting to \(peer.displayName, privacy: .public)")
        diag("connecting", linkFields(peer))
    }

    fileprivate func connected(_ peer: MCPeerID) {
        handshaking.remove(peer)
        if !members.contains(where: { $0.peer == peer }) {
            members.append(Member(peer: peer, peerName: peer.displayName))
        }
        isConnected = !session.connectedPeers.isEmpty
        trouble = nil
        partyLog.notice("connected to \(peer.displayName, privacy: .public), wifi=\(self.onWiFi)")
        diag("connected", linkFields(peer))
        // We are in. Only now is this a party worth silently reconnecting to —
        // and only now is "this device was a guest of that trip" true enough to
        // write down. `joining` still holds the advertisement for another line or
        // two, which is where the host's name comes from.
        if role == .guest, peer == hostPeer {
            identitySpent = true
            rejoinPending = nil
            reconnectTries = 0
            reconnectWatch?.cancel()
            reconnectWatch = nil
            hasJoined = true
            if let target = joining {
                PartyLedger.shared.note(trip: tripID, role: "guest", rules: rules,
                                        hostName: target.hostName)
            }
            settleJoin()
        }
        greet(peer)
    }

    fileprivate func disconnected(_ peer: MCPeerID) {
        members.removeAll { $0.peer == peer }
        isConnected = !session.connectedPeers.isEmpty
        partyLog.notice("lost \(peer.displayName, privacy: .public), wifi=\(self.onWiFi)")
        diag("disconnected", linkFields(peer))
        if peer == rejoinPending { rejoinPending = nil }

        // A refused invitation arrives here rather than as an error, and it is the
        // one disconnection that is not a dropout: we were never in. Checked first,
        // because the two want opposite things said and opposite things done.
        //
        // But not every not-connected is a refusal. When `invitePeer`'s own timeout
        // expires the framework delivers this same callback, and reading that as
        // "the host said no" tells somebody their code is wrong because nothing
        // answered — the exact misdiagnosis the failure split exists to kill, kept
        // alive on the one path a simulator cannot exercise. A refusal is quick; the
        // framework's own timeout is by definition at the deadline. So a
        // disconnection in the deadline's last breath is reported as silence.
        if let target = joining, peer == target.peer, !hasJoined {
            // A declined invitation goes straight to `.notConnected`; one that was
            // *accepted* passes through `.connecting` first and only lands here if
            // the connection then failed to hold. Reading both as a refusal is how
            // somebody who typed the right code — and whose code the host accepted —
            // got told the four characters did not match. The radio failing is not
            // the passenger's spelling.
            let reached = handshaking.remove(peer) != nil
            let ranOutTheClock = invitedAt.map {
                Date().timeIntervalSince($0) >= Self.inviteTimeout - 2
            } ?? false

            // Accepted and then lost. Worth another go on a clean session, silently:
            // the guest is already watching a spinner, and a retry that works is a
            // better answer than a sentence explaining why it did not.
            if reached, attemptsLeft > 1, !hasEnded {
                attemptsLeft -= 1
                joinWatch?.cancel()
                return knock(target)
            }
            if reached { return joinFailed(.dropped) }
            return joinFailed(ranOutTheClock ? .silence : .refused)
        }
        handshaking.remove(peer)

        // Not an error, and deliberately not reported as one. Dropping out is the
        // normal state of a phone in a pocket. Getting back is `scheduleReconnect`'s
        // job: it used to be left to `found` alone, which a browser that never saw
        // the host leave does not send again.
        if role == .guest, peer == hostPeer, hasJoined, !hasEnded {
            trouble = String(localized: "Lost the party. Looking for it again\u{2026}")
            scheduleReconnect()
        }
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard role == .guest,
              let raw = info?["id"], let id = UUID(uuidString: raw) else { return }
        diag("found", ["peer": Self.tag(peer), "trip": info?["trip"] ?? "-",
                       "ours": "\(id == tripID)", "joined": "\(hasJoined)",
                       "awaitingRediscovery": "\(awaitingRediscovery)",
                       "hostLinked": "\(hostLinked)"])

        // The party we are already in, back in range. Straight back in, no tapping.
        //
        // Matched on the advertised *trip*, not on the peer. An `MCPeerID` is only
        // meaningful for as long as the process that made it lives, so a host whose
        // app restarted comes back as a different peer with the same name — and
        // comparing peers would leave us hunting a phone that no longer exists while
        // the actual party advertised beside us. The trip id is the party's identity;
        // the peer is just where it happens to be answering from.
        if hasJoined, id == tripID {
            // Already in, and seeing the host again over a second transport, or
            // through the browser that stays running for exactly this. Pointing
            // `hostPeer` at it would make the live link look lost.
            guard !hostLinked else { return }
            hostPeer = peer
            return rejoin(peer)
        }

        // A join retry waiting for the fresh browser to see the host. See `knock`.
        if awaitingRediscovery, !hasJoined, let target = joining, id == target.tripID {
            awaitingRediscovery = false
            let again = Nearby(peer: peer, tripID: id,
                               tripName: target.tripName, hostName: target.hostName)
            joining = again
            hostPeer = peer
            return invite(again)
        }

        searchingQuietly = false
        quietWatch?.cancel()
        let fresh = Nearby(peer: peer, tripID: id,
                           tripName: info?["trip"] ?? "A trip",
                           hostName: info?["host"] ?? peer.displayName)
        // Replace, keyed on the trip, not the peer. The rejoin path above already
        // knows a peer id dies with its process; this list forgot. A host whose app
        // restarted came back as a new peer advertising the same trip, and until the
        // framework got around to `lostPeer` — which it does lazily, sometimes not
        // for minutes — the list held both. Worse, the two rows shared a `Nearby.id`,
        // so the `ForEach` drew only the first: the dead one. The guest tapped the
        // party in front of them, invited a phone that no longer existed, and got
        // thirty seconds of spinner for it — with nothing to see on the host's
        // screen, because the host was never asked. One trip, one row, and a fresh
        // advertisement always wins the seat.
        if let stale = nearby.firstIndex(where: { $0.tripID == id || $0.peer == peer }) {
            nearby[stale] = fresh
        } else {
            nearby.append(fresh)
        }
    }

    fileprivate func lost(_ peer: MCPeerID) {
        diag("lost", ["peer": Self.tag(peer), "joining": "\(joining?.peer == peer)"])
        nearby.removeAll { $0.peer == peer }
        // Waiting on a phone that has just stopped advertising. Said now rather than
        // left to the watchdog, which would sit there for another half a minute and
        // then blame the code.
        if let target = joining, peer == target.peer, !hasJoined {
            joinFailed(.vanished)
        }
    }

    /// The host is the only side that can answer this, because it is the only side
    /// that knows the code.
    ///
    /// It is also, until now, the only side that stayed silent about it. A wrong code
    /// was rejected here without a word, so the phone that *knew* what had gone wrong
    /// said nothing and the phone that could only guess did all the talking. Saying
    /// it on the host turns a minute of retyping into somebody in the front seat
    /// reading the code out again.
    ///
    /// Deliberately not a prompt, and not a decision. Nobody is being asked to admit
    /// anybody: the code is the door, and this is a notice that somebody tried the
    /// handle with the wrong key.
    fileprivate func shouldAdmit(_ peer: MCPeerID, offering context: Data?) -> Bool {
        guard role == .host else { return false }
        let offered = context.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        diag("invite.recv", ["from": Self.tag(peer), "codeOK": "\(Self.tidy(offered) == code)",
                             "members": "\(members.count)"])
        guard Self.tidy(offered) == code else {
            // Only worth saying while the car is still trying to get in, and only for
            // a moment. MultipeerConnectivity retries invitations across transports
            // and can re-deliver a declined one *after* a later attempt succeeded, so
            // a permanent card meant one mistyped code could leave an accusation on
            // screen for the rest of the drive — naming, by peer display name,
            // somebody sitting in the same car who is already in the party. A notice
            // that outlives the problem it describes is worse than no notice.
            if members.isEmpty {
                sayBriefly(String(localized: "Someone tried to join with the wrong code. The code for this party is \(code)."))
            }
            return false
        }
        // A previous wrong attempt, cleared by somebody getting it right.
        if trouble != nil { trouble = nil }
        return true
    }

    #if DEBUG
    /// Whether `-partyDropOnce` has spent its one failure.
    fileprivate var hasDroppedOne = false
    #endif

    fileprivate func failed(_ what: String) {
        diag("error", ["what": what])
        trouble = what
    }

    /// Says something that stops being true, and takes it back.
    ///
    /// `trouble` is one slot shared by everything that can go wrong, and most of what
    /// goes wrong in a party is momentary. Anything that describes a passing event
    /// rather than a standing state belongs here, or it sits on screen long after the
    /// car has stopped caring.
    private func sayBriefly(_ message: String) {
        trouble = message
        troubleFade?.cancel()
        troubleFade = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            // Only clears its own message: anything said since is somebody else's to
            // take down.
            guard !Task.isCancelled, let self, self.trouble == message else { return }
            self.trouble = nil
        }
    }

    /// Tell the party who I am now.
    ///
    /// A rename used to reach nobody. The roster only ever went out inside `greet`,
    /// which happens on connection — so changing your name mid-drive left every other
    /// phone showing the old one, and the scoreboard disagreed with the person
    /// sitting next to it.
    func announceMe(_ player: Player) {
        send(.roster([PartyMerge.event(for: player)]))
    }

    // MARK: - Bits

    private func localTrip() -> Trip? {
        let id = tripID
        return try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first
    }

    /// The code this trip is hosted under — the same one every time.
    ///
    /// It used to be minted fresh on every `host`, which is wrong for the case that
    /// actually happens: a host whose app is killed mid-drive. Re-hosting handed
    /// everyone a new code while the old one was still written on the whiteboard,
    /// still in the passenger's head, and still what the person who had not joined
    /// yet was typing. Reconnecting guests were fine — they hold the code from their
    /// first join — so the failure landed entirely on whoever was late.
    ///
    /// Also means a trip taken every weekend keeps its code, which regulars stop
    /// having to read out at all.
    private static func code(for trip: UUID) -> String {
        #if DEBUG
        // `-partyCode` still wins, or every two-device test would inherit whatever
        // the previous one happened to persist.
        if let given = LaunchFlags.value(after: "-partyCode") { return tidy(given) }
        #endif
        if let kept = PartyLedger.shared.code(for: trip), !kept.isEmpty { return kept }
        return freshCode()
    }

    /// No `O`/`0` or `I`/`1`: the code is read off one screen and typed into another,
    /// usually by a passenger, usually in a moving car.
    private static func freshCode() -> String {
        // `-partyCode` is handled by `code(for:)`, which is the only caller — putting
        // it in both places would mean a test flag that silently stopped applying the
        // day somebody called this directly.
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }

    /// The longest prefix of `name` that fits an `MCPeerID`, cut on a character
    /// boundary so an emoji is never sliced into rubble.
    private static func fitting(_ name: String, limit: Int = 60) -> String {
        var out = ""
        for character in name {
            if out.utf8.count + String(character).utf8.count > limit { break }
            out.append(character)
        }
        return out.isEmpty ? "Someone" : out
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

    /// Callbacks are keyed to the session they came from, because a guest can be
    /// holding two at once.
    ///
    /// `rebuildSession` throws the old `MCSession` away and makes a new one for every
    /// invitation — deliberately, since a collapsed session never recovers. But the
    /// discarded one still delivers its terminal `.notConnected`, and the hop to the
    /// main actor means it lands *after* the new attempt is already under way. Passed
    /// on blind, that reads as the current attempt failing: a guest whose code was
    /// right, mid-reconnect, gets told the host turned them away.
    ///
    /// So every callback is checked against the session the party is actually using
    /// and dropped if it is not. The framework hands us the answer in the argument
    /// this used to ignore.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = switch state {
        case .connected: "connected"
        case .connecting: "connecting"
        case .notConnected: "notConnected"
        @unknown default: "unknown"
        }
        PartyDiagnostics.record("mc.state", ["peer": PartySession.tag(peerID), "state": name,
                                             "session": PartySession.tag(session),
                                             "connected": "\(session.connectedPeers.count)"])
        Task { @MainActor [weak owner] in
            guard let owner else { return }
            guard owner.isCurrent(session) else {
                return PartyDiagnostics.record("stale.session", ["peer": PartySession.tag(peerID),
                                                                 "state": name])
            }
            switch state {
            case .connected:    owner.connected(peerID)
            case .connecting:   owner.connecting(peerID)
            case .notConnected: owner.disconnected(peerID)
            @unknown default:   break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak owner] in
            guard let owner else { return }
            guard owner.isCurrent(session) else {
                return PartyDiagnostics.record("stale.recv", ["peer": PartySession.tag(peerID),
                                                              "bytes": "\(data.count)"])
            }
            owner.received(data, from: peerID)
        }
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
        PartyDiagnostics.record("mc.invitation", ["from": PartySession.tag(peerID)])
        Task { @MainActor [weak owner] in
            guard let owner else { return invitationHandler(false, nil) }
            #if DEBUG
            // `-partyIgnore` drops the invitation without answering it, which is
            // exactly what a host out of range looks like from the other phone.
            // Without it the guest's "no answer" message can only be reached by
            // physically walking away mid-join, so it would ship untested — and it
            // is one of the two the whole `JoinFailure` split exists to separate.
            if ProcessInfo.processInfo.arguments.contains("-partyIgnore") { return }
            // `-partyDrop` accepts the invitation — the code is checked and passes —
            // and hands back a session that is released the moment this returns, so
            // the guest reaches `.connecting` and then fails. That is the shape of
            // the reported bug: a correct code, admitted, and a connection that did
            // not hold.
            // `-partyDropOnce` fails the first connection and accepts the next,
            // which is the case the retry exists for: a transient collapse that a
            // clean session gets past. `-partyDrop` never accepts, for the case it
            // does not.
            if ProcessInfo.processInfo.arguments.contains("-partyDropOnce"),
               !owner.hasDroppedOne {
                guard owner.shouldAdmit(peerID, offering: context) else {
                    return invitationHandler(false, nil)
                }
                owner.hasDroppedOne = true
                return invitationHandler(true, MCSession(peer: owner.mcSession.myPeerID))
            }
            if ProcessInfo.processInfo.arguments.contains("-partyDrop") {
                guard owner.shouldAdmit(peerID, offering: context) else {
                    return invitationHandler(false, nil)
                }
                return invitationHandler(true, MCSession(peer: owner.mcSession.myPeerID))
            }
            #endif
            guard owner.shouldAdmit(peerID, offering: context) else {
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
        PartyDiagnostics.record("mc.found", ["peer": PartySession.tag(peerID),
                                             "browser": PartySession.tag(browser)])
        Task { @MainActor [weak owner] in
            guard let owner else { return }
            guard owner.isCurrent(browser) else {
                return PartyDiagnostics.record("stale.found", ["peer": PartySession.tag(peerID)])
            }
            owner.found(peerID, info: info)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        PartyDiagnostics.record("mc.lost", ["peer": PartySession.tag(peerID),
                                            "browser": PartySession.tag(browser)])
        Task { @MainActor [weak owner] in
            guard let owner else { return }
            guard owner.isCurrent(browser) else {
                return PartyDiagnostics.record("stale.lost", ["peer": PartySession.tag(peerID)])
            }
            owner.lost(peerID)
        }
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

// MARK: - Permission and radios

extension PartySession {

    /// Watches whether iOS will let this app use the local network at all.
    ///
    /// A plain Bonjour browser for the party's own service, run beside the real
    /// transport purely for the state it reports. Denied, it sits in `waiting` with
    /// `kDNSServiceErr_PolicyDenied`; allowed, it goes `ready`. It also stands in
    /// `waiting` like that while the permission prompt is still on screen, which is
    /// harmless — the prompt covers the card, and answering it moves the state on.
    /// Live rather than checked once, so turning the setting on in Settings and
    /// coming back clears the warning without leaving the party.
    fileprivate func watchAccess() {
        let probe = NWBrowser(for: .bonjour(type: "_\(Self.service)._tcp", domain: nil),
                              using: NWParameters())
        probe.stateUpdateHandler = { [weak self] state in
            let denied: Bool
            switch state {
            case .waiting(let error), .failed(let error):
                if case .dns(let code) = error {
                    denied = code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
                } else {
                    denied = false
                }
            default:
                denied = false
            }
            Task { @MainActor in
                guard let self else { return }
                self.diag("localNetwork", ["state": "\(state)", "blocked": "\(denied)"])
                self.localNetworkBlocked = denied
            }
        }
        probe.start(queue: .main)
        accessProbe = probe
    }

    /// Twenty seconds of an empty list, on a guest that has not joined anything.
    /// Long enough that a phone bringing up its radios is done, short enough that
    /// the person is still looking at the screen.
    fileprivate func watchForQuiet() {
        searchingQuietly = false
        quietWatch?.cancel()
        quietWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.nearby.isEmpty, !self.hasJoined else { return }
            self.diag("search.quiet")
            self.searchingQuietly = true
        }
    }
}

// MARK: - TEMPORARY: the party log

/// Everything below exists for one round of field testing. See `PartyDiagnostics`.
extension PartySession {

    /// A peer as the log names it: display name, and a short hash that tells a
    /// fresh identity apart from the old one under the same name.
    nonisolated static func tag(_ peer: MCPeerID) -> String {
        "\(peer.displayName)#\(String(UInt(bitPattern: peer.hash) & 0xFFFF, radix: 16))"
    }

    nonisolated static func tag(_ object: AnyObject) -> String {
        String(UInt(bitPattern: ObjectIdentifier(object).hashValue) & 0xFFFF, radix: 16)
    }

    fileprivate func diag(_ event: String, _ fields: [String: String] = [:]) {
        var all = fields
        all["role"] = role == .host ? "host" : "guest"
        all["me"] = Self.tag(peerID)
        all["gen"] = "\(identityGeneration)"
        all["wifi"] = "\(onWiFi)"
        PartyDiagnostics.record(event, all)
    }

    /// The state of one link, for connecting, connected and disconnected.
    private func linkFields(_ peer: MCPeerID) -> [String: String] {
        [
            "peer": Self.tag(peer),
            "isHost": "\(peer == hostPeer)",
            "sinceInvite": invitedAt.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "-",
            "handshaking": "\(handshaking.contains(peer))",
            "connectedPeers": session.connectedPeers.map(Self.tag).joined(separator: ","),
            "joined": "\(hasJoined)",
            "attemptsLeft": "\(attemptsLeft)",
            "rejoinPending": rejoinPending.map(Self.tag) ?? "-",
        ]
    }

    /// The whole of the party's state, for a tester's Mark and for the export.
    var diagnosticState: [String: String] {
        [
            "role": role == .host ? "host" : "guest",
            "me": Self.tag(peerID),
            "gen": "\(identityGeneration)",
            "code": code,
            "trip": tripID.uuidString,
            "joined": "\(hasJoined)",
            "ended": "\(hasEnded)",
            "joining": joining.map { Self.tag($0.peer) } ?? "-",
            "hostPeer": hostPeer.map(Self.tag) ?? "-",
            "hostLinked": "\(hostLinked)",
            "connectedPeers": session.connectedPeers.map(Self.tag).joined(separator: ","),
            "members": members.map { Self.tag($0.peer) }.joined(separator: ","),
            "nearby": nearby.map { Self.tag($0.peer) }.joined(separator: ","),
            "isConnected": "\(isConnected)",
            "identitySpent": "\(identitySpent)",
            "rejoinPending": rejoinPending.map(Self.tag) ?? "-",
            "reconnectTries": "\(reconnectTries)",
            "awaitingRediscovery": "\(awaitingRediscovery)",
            "attemptsLeft": "\(attemptsLeft)",
            "handshaking": handshaking.map(Self.tag).joined(separator: ","),
            "advertising": "\(advertiser != nil)",
            "browsing": "\(browser != nil)",
            "wifi": "\(onWiFi)",
            "localNetworkBlocked": "\(localNetworkBlocked)",
            "trouble": trouble ?? "-",
        ]
    }
}
