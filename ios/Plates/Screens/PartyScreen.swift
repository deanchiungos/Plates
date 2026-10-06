import SwiftData
import SwiftUI

/// Starting a party, or joining one.
///
/// Deliberately not `MCBrowserViewController`. Apple's stock picker works, and it
/// arrives looking like a piece of a different app — a system list with system
/// type, in the middle of a screen made of paper and plate lettering. The whole of
/// what it does is "show nearby peers, tap one", which is a list.
struct PartyScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(PopupHost.self) private var popup
    @Environment(TourGuide.self) private var tour

    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Book.startedAt, order: .reverse) private var books: [Book]
    @Query(sort: \Player.joinedAt) private var players: [Player]
    @AppStorage(TripSelection.key) private var currentTripID = ""
    @AppStorage(PlaySelection.bookKey) private var currentBookID = ""
    @AppStorage(PlaySelection.kindKey) private var targetKind = "trip"

    /// Mirrored rather than read through `PartySession.shared` at every use, because
    /// a static is not observable — the object's properties are, once something has
    /// read them, but swapping which object is current is not a change SwiftUI can
    /// see. This screen is the only place a party starts or ends, so holding it here
    /// is honest as well as convenient.
    /// Read, not mirrored. See `PartyHost` for what the `@State` copy that used to
    /// live here cost: a party ended from the Trips tab left this screen drawing a
    /// live host card for a session that was over.
    private var party: PartySession? { PartySession.shared }
    @State private var joining: PartySession.Nearby?
    @State private var typedCode = ""

    /// What to do once this phone has said who it is.
    ///
    /// Every fresh install seeds the same "Me", so without this a car full of phones
    /// is a party of three players called Me — identical in the member list, in the
    /// standings, and on every spotter chip, with only the color telling them
    /// apart. The party is the one place a name genuinely matters to somebody other
    /// than its owner, so it is the place worth insisting.
    @State private var pendingEntry: Entry?
    /// Whoever's row was tapped in the roster. See `PersonSheet`.
    @State private var person: Player?
    // TEMPORARY — the party log. See `PartyDiagnostics`.
    @State private var sharedLog: SharedLog?
    @State private var markedAt: Date?
    @State private var exporting = false

    private enum Entry: String, Identifiable {
        case host, join
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
              ScrollViewReader { scroller in
                VStack(spacing: 18) {
                    if let party {
                        if party.localNetworkBlocked { localNetworkCard }
                        if let trouble = party.trouble { troubleCard(trouble) }
                        switch party.role {
                        case .host:  hostCard(party)
                        case .guest: guestCard(party)
                        }
                    } else {
                        startCard
                    }
                    // TEMPORARY — see `PartyDiagnostics`.
                    diagnosticsCard
                }
                .padding(Theme.screenPadding)
                .tourScrolling(scroller)
              }
            }
        }
        .navigationTitle("Party")
        .sheet(item: $person) { PersonSheet(player: $0) }
        .sheet(item: $sharedLog) { ShareSheet(items: [$0.url]) }
        .onAppear { tour.offer(.party, stops: tourStops) }
        .onDisappear { tour.left(.party) }
        // A party starting pulls every stop out from under a tour that is mid-walk:
        // the three things it points at all belong to `startCard`, which is no longer
        // drawn. Ended rather than restored, because the screen it was touring is gone
        // and there is nothing left to put back. In practice the scrim blocks the taps
        // that would do this, so it is the debug launch hooks and any future path into
        // a party that this actually catches.
        .onChange(of: party == nil) { _, none in
            if !none { tour.left(.party) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $joining) { target in codeSheet(for: target) }
        .sheet(item: $pendingEntry) { entry in
            // Straight on into what they were trying to do once it has an answer, so
            // the sheet reads as a step rather than an interruption.
            IdentityPrompt(saveLabel: "Continue") { enter(entry) }
        }
        #if DEBUG
        // `-hostParty` / `-joinParty` start one without a tap, which is the only way
        // to reach either state on a simulator — and the only way to stand up the two
        // ends of a party at once for a two-device test.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard party == nil else { return }
            if args.contains("-hostParty"), let trip = currentTrip {
                _ = PartySession.host(trip: trip, as: myName, context: context)
            } else if args.contains("-joinParty") {
                _ = PartySession.browse(as: myName, context: context)
            }
        }
        // With `-partyCode`, join the first party found rather than waiting for a tap.
        .onChange(of: party?.nearby.first) { _, found in
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-joinParty"),
                  let given = LaunchFlags.value(after: "-partyCode"),
                  let found, let party, !party.isConnected else { return }
            party.join(found, code: given)
        }
        // `-partyLog OH` logs a plate the moment somebody joins, through the real
        // `PlateLogger` path — so a two-device test exercises the actual broadcast
        // hook rather than a stand-in for it.
        .onChange(of: party?.isConnected) { _, connected in
            let args = ProcessInfo.processInfo.arguments
            guard connected == true else { return }

            // `-partyEnd` says goodbye once somebody is in, so the other phone's
            // "the host ended the party" state is reachable without a tap. Ahead of
            // the `-partyLog` guard, so it works on its own.
            // Through `askOnLeaving`, not straight to `leave()`, so the thing a
            // launch argument exercises is the thing a finger would — including the
            // question about what happens to the copy.
            if args.contains("-partyEnd") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    if let live = self.party { askOnLeaving(live) }
                }
            }

            // `-renameMe Ethan` changes this phone's player mid-party, the same two
            // steps `PlayersScreen.save` takes. The only way to reach the case
            // without a keyboard, and the case is the reported bug: a rename has to
            // reach the other phones, and it must not be undone by their stale copy.
            if let named = LaunchFlags.value(after: "-renameMe") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard let me = DevicePlayer.resolve(from: players) else { return }
                    me.name = named
                    try? context.save()
                    PartySession.shared?.announceMe(me)
                }
            }

            guard let code = LaunchFlags.value(after: "-partyLog"),
                  let plate = Plate.plate(for: code.uppercased()) else { return }

            // Connected is not the same as caught up: a guest is pointed at its own
            // trip until the snapshot lands and switches it. Logging before then puts
            // the plate on the wrong trip, where `broadcast` rightly refuses to send
            // it — so wait for the party's trip to actually be the one being filled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard let party = PartySession.shared,
                      let trip = currentTrip, trip.id == party.tripID else { return }
                PlateLogger.record(plate, in: trip,
                                   by: DevicePlayer.resolve(from: players), context: context)

                // `-partyUnlog` then takes it straight back, which is the case
                // tombstones exist for: the peer must drop it *and* refuse to re-add
                // it when the next snapshot still contains it.
                guard args.contains("-partyUnlog") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    var withdrawn: [UUID] = []
                    for sighting in trip.allSightings where sighting.plateCode == plate.code {
                        withdrawn.append(sighting.id)
                        context.delete(sighting)
                    }
                    try? context.save()
                    PartySession.shared?.broadcastRemoval(withdrawn, in: trip.id)
                }
            }
        }
        #endif
        // Last in the chain, so the scrim covers this screen and nothing else.
        .tourLayer(.party, Self.tourCopy)
    }

    /// What this screen's tour stops say. Out of the chain, not out of the
    /// file — see `coachLayer`.
    private static let tourCopy: [Tour.Stop: TourWords] = [
        .partyWhat: TourWords("A party pools what everyone spots. Nobody has to hand their phone around, and it works with no signal at all."),
        .partyHost: TourWords("One person starts it and reads the four character code out loud."),
        .partyJoin: TourWords("Everyone else taps here, picks the party they can see, and types that code in.")
    ]

    // MARK: - Nothing running yet

    private var startCard: some View {
        VStack(spacing: 18) {
            SettingsGroup("Play together") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everyone spots on their own phone")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("One person starts the Party and reads out the code. Plates anyone calls show up on every screen, and it all works with no signal.")
                        .font(.plates(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .tourAnchor(.partyWhat)
            .tourStop(.partyWhat)

            if let trip = currentTrip, cannotHost == nil {
                action("Start a Party for \(trip.name)", filled: true) {
                    Haptics.selection()
                    begin(.host)
                }
                .tourAnchor(.partyHost)
                .tourStop(.partyHost)
            } else if let reason = cannotHost {
                // Said rather than silently hidden. A missing button is
                // indistinguishable from a broken one, and this is a rule about
                // whose trip it is, which nobody can guess.
                SettingsGroup("Not this one") {
                    Text(reason)
                        .font(.plates(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }

            action("Join someone's Party", filled: false) {
                Haptics.selection()
                begin(.join)
            }
            .tourAnchor(.partyJoin, prefersAbove: true)
            .tourStop(.partyJoin)
        }
    }

    /// Which stops this screen can host.
    ///
    /// Empty while a party is actually running, which stands the tour down rather than
    /// spending it: the live screen is a code, a member list and a way out, all of
    /// which are self-describing and none of which should be behind a scrim while
    /// somebody is trying to read four characters out loud to a car. It runs on the
    /// next visit, when the screen is the one that needs explaining.
    private var tourStops: [Tour.Stop] {
        guard party == nil else { return [] }
        var route: [Tour.Stop] = [.partyWhat]
        if currentTrip != nil, cannotHost == nil { route.append(.partyHost) }
        route.append(.partyJoin)
        return route
    }

    /// Asks who this phone is first, if it has never said.
    private func begin(_ entry: Entry) {
        guard DevicePlayer.hasProfile else { return pendingEntry = entry }
        enter(entry)
    }

    private func enter(_ entry: Entry) {
        switch entry {
        case .host:
            // Re-checked here, not just at the button. The debug launch hooks call
            // this directly, and a rule about whose trip it is should not depend on
            // which door you came through.
            guard let trip = currentTrip, cannotHost == nil else { return }
            _ = PartySession.host(trip: trip, as: myName, context: context)
        case .join:
            _ = PartySession.browse(as: myName, context: context)
        }
    }

    // MARK: - Leaving, and what happens to the copy

    /// The trip this party is about, if this phone has it.
    private func partyTrip(_ party: PartySession) -> Trip? {
        trips.first { $0.id == party.tripID }
    }

    /// Leave, then decide what the copy becomes.
    ///
    /// Two separate things, deliberately in that order. Leaving is not in question by
    /// the time somebody has tapped the button, and making it wait behind a popup
    /// would leave the radios running while they think — so the goodbye goes out
    /// immediately and the question is about the trip, not the party.
    private func askOnLeaving(_ party: PartySession) {
        let trip = partyTrip(party)
        // `leave()` clears the shared session itself, which is the whole point of
        // it being shared: nothing here has a private copy to keep in step.
        party.leave()
        Haptics.selection()
        guard let trip, !trip.isArchived else { return }
        askAboutCopy(of: trip)
    }

    /// What should happen to this phone's copy of a drive that has finished.
    ///
    /// The copy always survives if they want it to — that is the design, and it is
    /// what makes the party work with no signal. But a trip left open goes on looking
    /// live: it stays the thing the Game screen is filling, and it keeps drawing a
    /// running scoreboard for a car that has emptied. That is the reported "I still
    /// see multiple players on my Game tab even though the party has ended", and the
    /// people on it are not a bug — they really did spot those plates — so the answer
    /// is to let the drive be over rather than to erase anybody.
    private func askAboutCopy(of trip: Trip) {
        let mine = TripClosing.hasOwnFinds(in: trip, players: players)

        popup.present(
            "\(trip.name) is finished",
            message: mine
                ? "Everyone keeps their own copy. Finishing yours files it with your other trips, with everything anybody spotted still on it."
                : "You did not spot anything on this one. You can keep the copy anyway, or throw it away. Everybody else keeps theirs either way."
        ) {
            if mine {
                PopupChoice(title: "Finish the trip",
                            subtitle: "Files it away. Nothing is lost.") {
                    TripClosing.finish(trip, in: context)
                    Haptics.milestone()
                    popup.dismiss()
                }
            } else {
                PopupChoice(title: "Discard this trip",
                            subtitle: "Removes your copy only.") {
                    TripClosing.discard(trip, in: context)
                    Haptics.destructive()
                    popup.dismiss()
                }
                PopupChoice(title: "Finish and keep it",
                            subtitle: "Files it away with your trips.") {
                    TripClosing.finish(trip, in: context)
                    Haptics.milestone()
                    popup.dismiss()
                }
            }
            PopupButton(title: "Leave it open") { popup.dismiss() }
        }
    }

    // MARK: - Hosting

    private func hostCard(_ party: PartySession) -> some View {
        VStack(spacing: 18) {
            SettingsGroup("Your code") {
                VStack(spacing: 8) {
                    Text(party.code)
                        .font(Theme.PlateFont.glyph(52))
                        .tracking(10)
                        // Tracking pads the right of the last character too, which
                        // walks the whole code off centre at this size.
                        .padding(.leading, 10)
                        .foregroundStyle(Theme.ink)
                    Text("Read this out. Everyone else taps Join and types it in.")
                        .font(.plates(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 14)
            }

            rulesCard(party)

            memberCard(party, empty: "Nobody has joined yet.")

            action("End party", filled: false, destructive: true) {
                askOnLeaving(party)
            }
        }
    }

    /// Host only, and live: flipping one sends it to every phone in the party.
    ///
    /// Only the host gets these because they change what a tap *means*, and two
    /// people in one car disagreeing about that is worse than either answer.
    private func rulesCard(_ party: PartySession) -> some View {
        SettingsGroup("Rules") {
            ruleRow(
                title: "Protect what people find",
                detail: "Only the person who spotted a plate can take it back.",
                isOn: party.rules.protectsClaims
            ) { on in
                var next = party.rules
                next.protectsClaims = on
                party.setRules(next)
            }

            SettingsDivider()

            ruleRow(
                title: "Everyone can claim a plate",
                detail: "A state stays open after the first person calls it, so it counts for all of you.",
                isOn: party.rules.sharedClaims
            ) { on in
                var next = party.rules
                next.sharedClaims = on
                party.setRules(next)
            }
        }
    }

    private func ruleRow(title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Bool,
                         set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { new in Haptics.selection(); set(new) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.plates(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.plates(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.route)
        .padding(14)
    }

    // MARK: - Joining

    private func guestCard(_ party: PartySession) -> some View {
        VStack(spacing: 18) {
            if party.hasEnded {
                // Nothing to show but the way out. The trouble card above has already
                // said what happened, and the radios are off — a "looking for
                // parties" spinner here would be the screen inventing activity that
                // stopped when the host left.
                // The host went home, so the same decision arrives — just without a
                // party to leave first. Never automatic: somebody whose host quit
                // unexpectedly should not also find their trip filed away for them.
                let trip = partyTrip(party)
                action("Done", filled: true) {
                    Haptics.selection()
                    // `leave()`, not a local nil. Clearing the screen's own copy left
                    // `PartySession.shared` holding the ended session forever — a
                    // static outlives every view — so coming back to this screen
                    // re-adopted it, showed "The host ended the party" again, and
                    // re-asked what to do with a trip that had already been finished.
                    party.leave()
                    if let trip, !trip.isArchived { askAboutCopy(of: trip) }
                }
            } else if party.isConnected {
                memberCard(party, empty: "Connecting\u{2026}")
            } else if let target = party.joining {
                // The gap between tapping Join and hearing back is half a minute of
                // Bluetooth, and until this said so the screen went back to the same
                // list of parties — so the honest reading of a correct code was
                // "nothing happened", and people tapped it again.
                //
                // It used to read "Asking Anna to let you in…", which was a lie with
                // a cost. Nothing appears on the host's phone — admission is a silent
                // string compare against the code, see `PartySession.shouldAdmit` —
                // so the sentence promised a prompt that does not exist, and people
                // sat waiting for somebody who did not know they had been asked. What
                // is actually uncertain in these seconds is the radio and the code,
                // and neither is anything the host can act on while it happens.
                SettingsGroup("Joining") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Connecting to \(target.hostName)'s party\u{2026}")
                            .font(.plates(size: 13.5))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            } else {
                SettingsGroup("Nearby") {
                    if party.nearby.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Looking for parties in the car\u{2026}")
                                    .font(.plates(size: 13.5))
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            // Not while Local Network is the known reason — the card
                            // above already says the one thing that will fix it.
                            if party.searchingQuietly, !party.localNetworkBlocked {
                                Text("Nothing yet. Keep the Party screen open on both phones, and check that Wi-Fi and Bluetooth are on in Settings. Wi-Fi doesn't need to be connected to a network.")
                                    .font(.plates(size: 13))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    } else {
                        ForEach(Array(party.nearby.enumerated()), id: \.element.id) { index, found in
                            if index > 0 { SettingsDivider() }
                            Button {
                                Haptics.selection()
                                typedCode = ""
                                joining = found
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(found.tripName)
                                            .font(.plates(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("Hosted by \(found.hostName)")
                                            .font(.plates(size: 12.5))
                                            .foregroundStyle(Theme.inkMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.inkMuted.opacity(0.55))
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !party.hasEnded {
                // `hasJoined`, not `isConnected`. A guest whose host has locked their
                // phone is disconnected and still very much in the party — that is
                // the case the whole reconnect path exists for — and asking
                // `isConnected` relabelled the button "Stop looking" and skipped the
                // question about their copy of the trip. So an hour of collected
                // plates was left on a live trip with a scoreboard for a car that had
                // emptied, which is the report `askAboutCopy` was added to answer.
                action(party.hasJoined ? "Leave party" : "Stop looking",
                       filled: false, destructive: party.hasJoined) {
                    if party.hasJoined { askOnLeaving(party) } else {
                        party.leave()
                    }
                }
            }
        }
    }

    private func codeSheet(for target: PartySession.Nearby) -> some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("The code \(target.hostName) is showing")
                        .font(.plates(size: 13))
                        .foregroundStyle(Theme.inkMuted)

                    TextField("ABCD", text: $typedCode)
                        .font(Theme.PlateFont.glyph(38))
                        .tracking(8)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1))
                        )

                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("Join \(target.tripName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { joining = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        party?.join(target, code: typedCode)
                        joining = nil
                    }
                    .fontWeight(.semibold)
                    .disabled(typedCode.trimmingCharacters(in: .whitespaces).count < 4)
                }
            }
        }
        .presentationDetents([.height(260)])
    }

    // MARK: - Bits

    /// What to call somebody in the party.
    ///
    /// Their live `Player` row if they have told us which one they are, and the name
    /// their peer id was minted with if they have not. The fallback is what the whole
    /// list used to be, and it is frozen: an `MCPeerID` display name is fixed for the
    /// life of the sending process, so renaming yourself mid-drive left everybody
    /// else's copy of this list calling you the old thing until the party restarted.
    /// Reading a `Player` through the query means a rename lands here the moment the
    /// roster carrying it does.
    private func name(of member: PartySession.Member) -> String {
        guard let id = member.playerID,
              let player = players.first(where: { $0.id == id }) else {
            return member.peerName
        }
        return player.name
    }

    /// The stored player behind a peer, once the handshake has named them.
    private func person(for member: PartySession.Member) -> Player? {
        guard let id = member.playerID else { return nil }
        return players.first { $0.id == id }
    }

    private func memberCard(_ party: PartySession, empty: LocalizedStringKey) -> some View {
        SettingsGroup("In the party") {
            if party.members.isEmpty {
                Text(empty)
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                // Keyed on the member, not on where they are sitting in the array.
                // `members` mutates as peers come and go, so an offset key told
                // SwiftUI that row 1 was the same row it had been: dropping the
                // middle peer renamed that row to the person below them and removed
                // the last one instead. The sibling list above already does this.
                ForEach(Array(party.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { SettingsDivider() }
                    let known = person(for: member)
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.found)
                        Text(name(of: member))
                            .font(.plates(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        // Only once a peer has resolved to somebody this phone has
                        // a record of. Until the handshake names them there is no
                        // `Player` to block, and a control that could not act would
                        // be worse than none.
                        if known != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkMuted.opacity(0.55))
                        }
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                    .onTapGesture { if let known { person = known } }
                }
            }
        }
    }

    // MARK: - TEMPORARY: the party log

    /// For the TestFlight round only. Every phone in the car shares its log after a
    /// failure, and `dev/tools/party_log_merge.py` lines them up on one clock.
    private var diagnosticsCard: some View {
        SettingsGroup("Party log (test build)") {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "If the party misbehaves, tap Mark straight away, then Share from every phone in the car before closing the app.")
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let markedAt {
                    Text(verbatim: "Marked at \(markedAt.formatted(date: .omitted, time: .standard)).")
                        .font(.plates(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.route)
                }
                action("Mark a problem now", filled: false) {
                    markedAt = PartyDiagnostics.mark()
                }
                action(exporting ? "Preparing…" : "Share party log", filled: true) {
                    guard !exporting else { return }
                    exporting = true
                    Task {
                        if let url = await PartyDiagnostics.export() { sharedLog = SharedLog(url: url) }
                        exporting = false
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private struct SharedLog: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// iOS is keeping this app off the local network. Above everything else, because
    /// until it is fixed nothing else on the screen can work. See
    /// `PartySession.localNetworkBlocked`.
    private var localNetworkCard: some View {
        SettingsGroup("Local Network is off") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tags can't see nearby phones because Local Network is turned off for it. Open Settings, tap Tags, and turn on Local Network. Every phone in the party needs it.")
                    .font(.plates(size: 13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                action(String(localized: "Open Settings"), filled: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func troubleCard(_ message: String) -> some View {
        SettingsGroup("Trouble") {
            Text(message)
                .font(.plates(size: 13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    private func action(_ title: String, filled: Bool,
                        destructive: Bool = false,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.plates(size: 15, weight: .semibold))
                .foregroundStyle(filled ? Color.white : (destructive ? Color.red : Theme.route))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(filled ? Theme.route : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(filled ? Color.clear
                                                     : (destructive ? Color.red : Theme.route).opacity(0.4),
                                              lineWidth: 1.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// Whatever the Game screen is filling, if it is a trip at all.
    private var currentTrip: Trip? {
        guard case .trip(let trip)? = PlaySelection.current(
            kind: targetKind, tripID: currentTripID, bookID: currentBookID,
            trips: trips, books: books) else { return nil }
        return trip
    }

    /// Why this phone cannot start a party for what it is looking at, or nil if it
    /// can. Phrased as the sentence the screen shows, because there is no case where
    /// knowing the reason is optional.
    private var cannotHost: String? {
        // A book is a lifetime collection with no journey, and sharing one is a
        // different product — so the party is a trip, always.
        guard let trip = currentTrip else {
            return "Parties are for trips. Switch to a trip on the Game screen to start one."
        }
        // A trip that arrived by joining somebody else's party is not yours to host.
        // Hosting it would advertise their trip id under your name, giving the party
        // two hosts with two ideas of the rules. See `PartyLedger.joinedAsGuest`.
        guard PartyLedger.shared.joinedAsGuest(trip.id) else { return nil }
        let host = PartyLedger.shared.hostLabel(for: trip.id, among: players)
        return String(localized: "\(host ?? String(localized: "Somebody else")) started \(trip.name) and shared it with you, so only they can start a party for it. Start one on a trip of your own instead.")
    }

    /// What the other phones in the car see us as — the peer's display name, and the
    /// "hosted by" line on everybody else's list.
    ///
    /// This was `players.first?.name`, left over from before `DevicePlayer` existed,
    /// and it was wrong in exactly the situation the party is for. `first` is the
    /// earliest to join, which on a phone that has ever been in a party is whoever
    /// had the oldest `joinedAt` of everyone merged in — quite possibly a person
    /// sitting in a different car. So you advertised under their name, and the host
    /// list showed a party hosted by somebody who was not there.
    /// Fetched, not read off this screen's `@Query`.
    ///
    /// The identity sheet's completion runs `enter` synchronously inside
    /// `PlayerEditor.save()` — insert, save, `onSaved`, `adopt`, `onDone` — all in
    /// one call stack with no SwiftUI update in between, so `players` here is still
    /// the array from before the insert. `resolve` then found neither the id just
    /// written nor any row at all and returned nil, so a first-ever party advertised
    /// itself as "Me". Worse on a restored install: the fallback is earliest-joined,
    /// so it would have hosted under the name of somebody in a different car. The
    /// display name is frozen into the `MCPeerID` for the life of the process and
    /// persisted by `PartyLedger`, so there is no second chance at it.
    private var myName: String {
        DevicePlayer.current(in: context)?.name
            ?? DevicePlayer.resolve(from: players)?.name
            ?? String(localized: "Me")
    }
}
