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

    static let group = "group.com.tagsmedia.tags"
    private static let filename = "Widget.json"

    var tripName: String?
    var tripStates: Int = 0
    /// "trip" or "book". The app can be filling either, and calling a book a trip is
    /// the widget describing a different app from the one on the phone.
    var targetKind: String = "trip"
    var tripLastPlate: Date?
    var foundCodes: [String] = []
    var bestCode: String?
    /// Whether the app judged the best find worth painting. Resolved on the app
    /// side, where `RarityTier` is in scope — this target cannot see it, and the
    /// threshold invented here to stand in for it agreed with no band in the real
    /// scale.
    ///
    /// The rarity *number* used to cross the wire beside this and is not here any
    /// more. Nothing read it once the verdict replaced it, and two fields for one
    /// fact is how the next person reintroduces the threshold this replaced — worse,
    /// `matches` is Equatable, so a best find moving 9 to 10 at the same tier still
    /// counted as a change and spent a widget reload on a pixel-identical render.
    var bestIsRemarkable: Bool = false

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
        bestIsRemarkable: true,
        lifetimeStates: 33,
        lifetimePlates: 36,
        updatedAt: Date())
}

/// Decoding, in an extension.
///
/// In the type body it would suppress the synthesized memberwise init, and that
/// mattered: the replacement was fourteen hand-written lines that every new field had
/// to be added to as well as to the property list and the decoder — four places
/// instead of two, in the one file whose own doc says field drift here is what blanks
/// the home screen. An initializer declared in an extension suppresses nothing.
extension WidgetSnapshot {

    /// Hand-written, because the promise in the header above was not true otherwise.
    ///
    /// Swift's synthesized `init(from:)` emits `decode` for every non-optional
    /// property and ignores its default entirely — defaults are only used by the
    /// memberwise init. So eight of the properties here were hard requirements, and
    /// one field added to the app's `WidgetData` would throw `keyNotFound` against
    /// the Widget.json already on disk, `read()` would return nil, and the home
    /// screen would drop from a live trip to "ALL TIME / 0 of 50" until the app was
    /// next opened. `targetKind`, `foundCodes` and `bestCode` were all added
    /// mid-branch, so this has already been reachable once.
    ///
    /// `decodeIfPresent` semantics for every one of them is what the stated contract
    /// asks for: a widget reading a file it half-understands degrades to missing
    /// numbers rather than to nothing at all.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One `try?` rather than an optional dance: it returns `fallback` for a
        // missing key and for a JSON null alike, which is exactly the contract.
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        tripName = try? c.decodeIfPresent(String.self, forKey: .tripName)
        tripStates = value(.tripStates, 0)
        targetKind = value(.targetKind, "trip")
        tripLastPlate = try? c.decodeIfPresent(Date.self, forKey: .tripLastPlate)
        foundCodes = value(.foundCodes, [])
        bestCode = try? c.decodeIfPresent(String.self, forKey: .bestCode)
        bestIsRemarkable = value(.bestIsRemarkable, false)
        lastTripName = try? c.decodeIfPresent(String.self, forKey: .lastTripName)
        lastTripStates = value(.lastTripStates, 0)
        lifetimeStates = value(.lifetimeStates, 0)
        lifetimePlates = value(.lifetimePlates, 0)
        updatedAt = value(.updatedAt, .distantPast)
    }
}
