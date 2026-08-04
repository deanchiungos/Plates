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
        #if DEBUG
        // `-hostParty` / `-joinParty` start one without a tap, which is the only way
        // to reach either state on a simulator — and the only way to stand up the two
        // ends of a party at once for a two-device test.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard party == nil else { return }
            if args.contains("-hostParty"), let trip = hostableTrip {
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
            self.party = PartySession.shared
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

            if let trip = hostableTrip {
                action("Start a party for \(trip.name)", filled: true) {
                    Haptics.selection()
                    party = PartySession.host(trip: trip, as: myName, context: context)
                }
            } else {
                // A book is a lifetime collection with no journey, and sharing one is
                // a different product — so the party is a trip, always.
                SettingsGroup("Not this one") {
                    Text("Parties are for trips. Switch to a trip on the Game screen to start one.")
                        .font(.plates(size: 13))
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }

            action("Join someone's party", filled: false) {
                Haptics.selection()
                party = PartySession.browse(as: myName, context: context)
            }
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

            memberCard(party, empty: "Nobody has joined yet.")

            action("End party", filled: false, destructive: true) {
                party.leave()
                self.party = nil
            }
        }
    }

    // MARK: - Joining

    private func guestCard(_ party: PartySession) -> some View {
        VStack(spacing: 18) {
            if party.isConnected {
                memberCard(party, empty: "Connecting\u{2026}")
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

            action(party.isConnected ? "Leave party" : "Stop looking",
                   filled: false, destructive: party.isConnected) {
                party.leave()
                self.party = nil
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
                        party = PartySession.shared
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

    /// Only a trip can be hosted, and only one that will still take plates.
    private var hostableTrip: Trip? {
        guard case .trip(let trip)? = PlaySelection.current(
            kind: targetKind, tripID: currentTripID, bookID: currentBookID,
            trips: trips, books: books) else { return nil }
        return trip
    }

    /// Phase 2 replaces this with the device player. Until then the first player is
    /// the only "me" the app has.
    private var myName: String { players.first?.name ?? "Me" }
}
