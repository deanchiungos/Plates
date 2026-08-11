import Foundation

/// The app's `WidgetData`, read from the other side of a process boundary.
///
/// **A deliberate duplicate.** The widget is its own target with its own
/// file-system-synchronised folder, so it cannot see `Plates/Domain/WidgetData.swift`
/// — and the alternative, a shared framework target, is a whole build product to
/// carry six stored properties across.
///
/// Treat it the way `PartyWire` is treated: this is a wire format, not shared code.
/// The two ends are allowed to be separate files precisely because the contract
/// between them is the thing that matters, and every property here is optional or
/// defaulted so an older widget reading a newer app's file degrades to missing
/// numbers rather than to nothing at all.
struct WidgetSnapshot: Codable {

    static let group = "group.com.eggeppel.plates"
    private static let filename = "Widget.json"

    var tripName: String?
    var tripStates: Int = 0
    /// "trip" or "book". The app can be filling either, and calling a book a trip is
    /// the widget describing a different app from the one on the phone.
    var targetKind: String = "trip"
    var tripLastPlate: Date?
    var foundCodes: [String] = []
    var bestCode: String?
    var bestRarity: Int = 0

    var lastTripName: String?
    var lastTripStates: Int = 0

    var lifetimeStates: Int = 0
    var lifetimePlates: Int = 0

    var updatedAt: Date = .distantPast

    static let stateTotal = 50

    /// Nil when the app has never written one, or when the App Group is not in place
    /// — which is a build-configuration problem, and the widget's job is to look
    /// empty rather than to explain it.
    static func read() -> WidgetSnapshot? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(filename),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - What the widget actually shows

    /// The three tiers, in order, exactly as they were asked for: the trip being
    /// filled, the one most recently finished, and a lifetime total that is always
    /// true even on a phone that has never run a trip at all.
    enum Headline {
        case active(name: String, states: Int, lastPlate: Date?, kind: String)
        case recent(name: String, states: Int)
        case lifetime(states: Int, plates: Int)
    }

    var headline: Headline {
        if let tripName { return .active(name: tripName, states: tripStates,
                                         lastPlate: tripLastPlate, kind: targetKind) }
        if let lastTripName { return .recent(name: lastTripName, states: lastTripStates) }
        return .lifetime(states: lifetimeStates, plates: lifetimePlates)
    }

    var states: Int {
        switch headline {
        case .active(_, let states, _, _), .recent(_, let states): return states
        case .lifetime(let states, _): return states
        }
    }

    /// The placeholder WidgetKit draws in the gallery and while a real one loads.
    /// Plausible numbers rather than zeroes, so nobody picks the widget believing it
    /// will always look empty.
    static let sample = WidgetSnapshot(
        tripName: "Summer Roadtrip",
        tripStates: 21,
        tripLastPlate: Date(),
        foundCodes: ["AK", "AZ", "AR", "CA", "CO", "HI", "ID", "IL", "KS", "MO",
                     "MT", "NE", "NV", "NM", "NY", "OK", "OR", "TX", "UT", "WA", "WY"],
        bestCode: "AK",
        bestRarity: 9,
        lifetimeStates: 33,
        lifetimePlates: 36,
        updatedAt: Date())
}
