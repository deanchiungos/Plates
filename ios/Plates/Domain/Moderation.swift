import Foundation
import SwiftData
import UIKit

/// Reporting somebody, and blocking them.
///
/// **What there is to moderate.** TAGS has no feed, no comments, no photos and no
/// captions. The only things one person can put in front of another are a display
/// name, an emoji avatar, and a run of plate sightings. That is a small surface, and
/// the controls here are deliberately the same size as it: a report says who and
/// why, and a block stops their contributions arriving and takes the ones already
/// here off the screen. Anything grander would be theatre.
///
/// **Where they arrive from.** Two places, both invitation-only. A shared book is a
/// `CKShare` sent to somebody by name; a party is a Multipeer session on the local
/// network. Nobody can reach this phone without having been let in, which is why
/// blocking is the right primitive: the person is already known.
///
/// **Why a report is an email.** There is no TAGS server to file one with. Every
/// byte the app stores is on the phone or in the user's own iCloud, and standing up
/// a public CloudKit database purely to hold reports would mean adding the app's
/// first shared backend for a feature that fires once a year. A prefilled message to
/// a mailbox a person actually reads is the honest version, and it degrades
/// gracefully: if no mail client will take it, the address is offered to copy.
enum Moderation {

    static let mailbox = Legal.Publisher.support

    /// Why somebody is being reported.
    ///
    /// Five, and no "other" with a mandatory essay. A list long enough to make the
    /// reporter classify their complaint is a list that loses reports; these are the
    /// things that can actually go wrong given what the app lets people send.
    enum Reason: String, CaseIterable, Identifiable {
        case name
        case harassment
        case impersonation
        case cheating
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name:          String(localized: "Offensive name or avatar")
            case .harassment:    String(localized: "Harassment or threats")
            case .impersonation: String(localized: "Pretending to be someone else")
            case .cheating:      String(localized: "Fake or spam plates")
            case .other:         String(localized: "Something else")
            }
        }
    }

    // MARK: - Blocking

    /// Hides everything this person has contributed, and turns away everything they
    /// send from now on.
    ///
    /// Refuses to block the person using the phone. Nothing in the UI offers it, but
    /// a device that blocked itself would empty its own collection, and that is too
    /// expensive a mistake to leave to the call sites.
    ///
    /// Resolved through the store, not read from `currentID`. That key is nil on
    /// any install that has never adopted a profile, and `nil != anyone` is true,
    /// so the guard was open on exactly the phones with the least idea who they
    /// are. `DevicePlayer.resolve` answers the same question the grid does.
    @discardableResult
    @MainActor
    static func block(_ player: Player, in context: ModelContext) -> Bool {
        guard player.id != DevicePlayer.current(in: context)?.id else { return false }
        guard player.blockedAt == nil else { return true }
        player.blockedAt = Date()
        try? context.save()
        // The widget draws from its own sidecar and would keep showing their plates
        // on the home screen until the next launch rebuilt it.
        WidgetData.write(from: context)
        return true
    }

    @MainActor
    static func unblock(_ player: Player, in context: ModelContext) {
        guard player.blockedAt != nil else { return }
        player.blockedAt = nil
        try? context.save()
        WidgetData.write(from: context)
    }

    // MARK: - Reporting

    /// The report, as a message ready to send.
    ///
    /// Carries the player's id as well as their name because names are the thing
    /// being complained about and are therefore the thing most likely to have
    /// changed by the time anybody reads the mail.
    ///
    /// Carries no location, no plate data and no identifier for the reporter. Their
    /// mail client supplies a return address, which is all a reply needs, and the
    /// rest would be collecting more than the complaint requires.
    @MainActor
    static func mail(about player: Player, reason: Reason, note: String) -> URL? {
        let bundle = Bundle.main.infoDictionary
        let short = bundle?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle?["CFBundleVersion"] as? String ?? "1"
        let when = ISO8601DateFormatter().string(from: Date())

        let subject = "TAGS report: \(reason.rawValue)"
        var body = """
        Reported person: \(player.name)
        Reference: \(player.id.uuidString)
        Reason: \(reason.title)

        """
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body += "\nWhat happened:\n\(trimmed)\n" }
        body += """

        ---
        Sent from TAGS \(short) (\(build))
        \(when)
        """

        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = mailbox
        comps.queryItems = [URLQueryItem(name: "subject", value: subject),
                            URLQueryItem(name: "body", value: body)]
        // `URLComponents` leaves "+" unescaped in a query value, and a mail client
        // reading the query as form data turns it into a space. Nothing above emits
        // one today; a note somebody types can.
        comps.percentEncodedQuery = comps.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return comps.url
    }

    /// Whether anything on this phone will accept a `mailto:`.
    ///
    /// False on a simulator with no Mail account, and on a phone where Mail has been
    /// removed and nothing replaced it. The sheet offers the address to copy instead
    /// rather than opening a URL that silently does nothing.
    @MainActor
    static var canSendMail: Bool {
        guard let url = URL(string: "mailto:\(mailbox)") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
