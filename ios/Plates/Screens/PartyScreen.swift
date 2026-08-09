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
    @State private var party: PartySession? = PartySession.shared
    @State private var joining: PartySession.Nearby?
    @State private var typedCode = ""

    /// What to do once this phone has said who it is.
    ///
    /// Every fresh install seeds the same "Me", so without this a car full of phones
    /// is a party of three players called Me — identical in the member list, in the
    /// standings, and on every spotter chip, with only the colour telling them
    /// apart. The party is the one place a name genuinely matters to somebody other
    /// than its owner, so it is the place worth insisting.
    @State private var pendingEntry: Entry?

    private enum Entry: String, Identifiable {
        case host, join
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    if let party {
                        if let trouble = party.trouble { troubleCard(trouble) }
                        switch party.role {
                        case .host:  hostCard(party)
                        case .guest: guestCard(party)
                        }
                    } else {
                        startCard
                    }
                }
                .padding(Theme.screenPadding)
            }
        }
        .navigationTitle("Party")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $joining) { target in codeSheet(for: target) }
        .sheet(item: $pendingEntry) { entry in
            PlayerEditor(player: DevicePlayer.resolve(from: players),
                         usedColors: [],
                         onDelete: nil,
                         title: "Who's playing?",
                         saveLabel: "Continue",
                         onSaved: {
                             DevicePlayer.markProfileSet()
                             // Straight on into what they were trying to do, so the
                             // sheet reads as a step rather than an interruption.
                             enter(entry)
                         })
        }
        #if DEBUG
        // `-hostParty` / `-joinParty` start one without a tap, which is the only way
        // to reach either state on a simulator — and the only way to stand up the two
        // ends of a party at once for a two-device test.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard party == nil else { return }
            if args.contains("-hostParty"), let trip = currentTrip {
                party = PartySession.host(trip: trip, as: myName, context: context)
            } else if args.contains("-joinParty") {
                party = PartySession.browse(as: myName, context: context)
            }
        }
        // With `-partyCode`, join the first party found rather than waiting for a tap.
        .onChange(of: party?.nearby.first) { _, found in
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-joinParty"),
                  let at = args.firstIndex(of: "-partyCode"), at + 1 < args.count,
                  let found, let party, !party.isConnected else { return }
            party.join(found, code: args[at + 1])
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

            guard let at = args.firstIndex(of: "-partyLog"), at + 1 < args.count,
                  let plate = Plate.plate(for: args[at + 1].uppercased()) else { return }

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
    }

    // MARK: - Nothing running yet

    private var startCard: some View {
        VStack(spacing: 18) {
            SettingsGroup("Play together") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everyone spots on their own phone")
                        .font(.plates(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("One person starts the party and reads out the code. "
                         + "Plates anyone calls show up on every screen, and it all works with no signal.")
                        .font(.plates(size: 12.5))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }

            if let trip = currentTrip, cannotHost == nil {
                action("Start a party for \(trip.name)", filled: true) {
                    Haptics.selection()
                    begin(.host)
                }
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

            action("Join someone's party", filled: false) {
                Haptics.selection()
                begin(.join)
            }
        }
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
            party = PartySession.host(trip: trip, as: myName, context: context)
        case .join:
            party = PartySession.browse(as: myName, context: context)
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
        party.leave()
        self.party = nil
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
                ? "Everyone keeps their own copy. Finishing yours files it with your "
                  + "other trips, with everything anybody spotted still on it."
                : "You did not spot anything on this one. You can keep the copy anyway, "
                  + "or throw it away \u{2014} everybody else keeps theirs either way."
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

    private func ruleRow(title: String, detail: String, isOn: Bool,
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
                    self.party = nil
                    if let trip, !trip.isArchived { askAboutCopy(of: trip) }
                }
            } else if party.isConnected {
                memberCard(party, empty: "Connecting\u{2026}")
            } else if let target = party.joining {
                // The gap between tapping Join and hearing back is up to a dozen
                // seconds of Bluetooth, and until this said so the screen went back to
                // the same list of parties — so the honest reading of a correct code
                // was "nothing happened", and people tapped it again.
                SettingsGroup("Joining") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Asking \(target.hostName) to let you in\u{2026}")
                            .font(.plates(size: 13.5))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            } else {
                SettingsGroup("Nearby") {
                    if party.nearby.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for parties in the car\u{2026}")
                                .font(.plates(size: 13.5))
                                .foregroundStyle(Theme.inkMuted)
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
                action(party.isConnected ? "Leave party" : "Stop looking",
                       filled: false, destructive: party.isConnected) {
                    // Only a party that was actually joined has a copy worth deciding
                    // about. "Stop looking" is abandoning a search, not leaving a car.
                    if party.isConnected { askOnLeaving(party) } else {
                        party.leave()
                        self.party = nil
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

    private func memberCard(_ party: PartySession, empty: String) -> some View {
        SettingsGroup("In the party") {
            if party.members.isEmpty {
                Text(empty)
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(party.members.enumerated()), id: \.offset) { index, name in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.found)
                        Text(name)
                            .font(.plates(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(14)
                }
            }
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
        let host = PartyLedger.shared.hostName(for: trip.id)
        return "\(host ?? "Somebody else") started \(trip.name) and shared it with you, "
             + "so only they can start a party for it. Start one on a trip of your own instead."
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
    private var myName: String {
        DevicePlayer.resolve(from: players)?.name ?? "Me"
    }
}
