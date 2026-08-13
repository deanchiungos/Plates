import Foundation
import SwiftData
import UserNotifications

/// The one nudge this app sends: a trip you started and stopped feeding.
///
/// Local, not pushed. There is no server behind Plates and there does not need to
/// be — the phone already knows when a trip last took a plate, so the whole feature
/// is `UNUserNotificationCenter` and a date.
///
/// **Off until asked for.** The permission prompt is a one-shot, the same as
/// location's, and firing it unannounced on launch spends the only chance at the
/// moment nobody knows what it is for. So this lives behind a switch in Settings and
/// asks the system only when somebody turns it on. The cost is that people have to
/// find it, which is a real cost — but a "don't ask again" from a stranger is
/// permanent, and this is worth less than that.
///
/// Deliberately one reminder per trip, keyed by trip id, rescheduled from scratch
/// every time anything changes. Trying to patch pending requests individually is how
/// notification code ends up firing for trips that were deleted three weeks ago.
@MainActor
final class TripReminders {

    static let shared = TripReminders()

    static let enabledKey = "tripRemindersOn"

    /// Long enough that a lunch stop is not "abandoned", short enough that the
    /// reminder still arrives while the drive is a live idea rather than a memory.
    static let quiet: TimeInterval = 24 * 60 * 60

    private let centre = UNUserNotificationCenter.current()

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Turning it on

    /// Asks the system, and only stays on if the system said yes. A switch that
    /// stays on after the permission was refused is a switch that lies.
    @discardableResult
    func enable() async -> Bool {
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: Self.enabledKey)
        return granted
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        centre.removeAllPendingNotificationRequests()
    }

    /// Whether the system would actually deliver one. Distinct from `isEnabled`:
    /// permission can be withdrawn in Settings long after it was granted here, and
    /// the row has to be able to say so rather than claiming to be on.
    func systemAllows() async -> Bool {
        await centre.notificationSettings().authorizationStatus == .authorized
    }

    // MARK: - Scheduling

    /// Rebuilt from the store, every time. Called after a plate is logged, when a
    /// trip is finished, and when the app comes forward — all the moments the answer
    /// could have changed.
    func refresh(in context: ModelContext) {
        centre.removeAllPendingNotificationRequests()
        guard isEnabled else { return }

        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        for nudge in Self.plan(for: trips, now: Date()) { schedule(nudge) }
    }

    /// What *would* be scheduled, as plain values.
    ///
    /// Split out from the scheduling so it can be checked. Delivery needs a
    /// permission grant and a system that is willing, neither of which a launch
    /// argument can arrange — but which trips earn a reminder, and when, is ordinary
    /// logic and the part that can actually be wrong. See `-partyMergeCheck`.
    struct Nudge: Equatable {
        var tripID: UUID
        var fireAt: Date
        var title: String
        var body: String
    }

    static func plan(for trips: [Trip], now: Date) -> [Nudge] {
        trips.collectable.compactMap { trip in
            // A trip with nothing on it is not abandoned, it is unstarted. Nagging
            // somebody about a trip they have never logged a plate on is the app
            // asking them to use it.
            guard let last = trip.allSightings.map(\.spottedAt).max() else { return nil }

            let fireAt = last.addingTimeInterval(quiet)
            // Already past — the trip went quiet before this was ever switched on.
            // Reminding somebody about last month's drive is worse than saying
            // nothing, and firing immediately is how that would come out.
            guard fireAt > now else { return nil }

            return Nudge(tripID: trip.id,
                         fireAt: fireAt,
                         title: String(localized: "Still traveling?"),
                         body: String(localized: "You have \(trip.statesFound) of 50 states on \(trip.name)."))
        }
    }

    #if DEBUG
    /// `-remindersTest` reports what is actually queued with the system and then
    /// schedules one ten seconds out.
    ///
    /// The 24-hour fuse is the whole point of the feature and hopeless to verify —
    /// "wait a day and hope" is not a test. This goes through `schedule` unchanged,
    /// so what arrives is the real notification with a shorter trigger, and it
    /// compiles out of Release.
    func test(in context: ModelContext) async {
        let pending = await centre.pendingNotificationRequests()
        print("[reminders] enabled=\(isEnabled) allowed=\(await systemAllows())")
        print("[reminders] \(pending.count) queued")
        for request in pending {
            let seconds = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0
            print("[reminders]   \(request.identifier) in \(Int(seconds / 3600))h — \(request.content.body)")
        }

        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        guard var soon = Self.plan(for: trips, now: Date()).first else {
            print("[reminders] nothing to nudge about")
            return
        }
        soon.fireAt = Date().addingTimeInterval(10)
        schedule(soon)
        print("[reminders] scheduled a copy 10s out: \(soon.body)")
    }
    #endif

    private func schedule(_ nudge: Nudge) {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-\(nudge.tripID.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                // Floored at a second rather than a minute so `-remindersTest` can
                // use a short fuse without a special path of its own; a real nudge is
                // a day out and never comes near it.
                timeInterval: max(1, nudge.fireAt.timeIntervalSinceNow), repeats: false))
        centre.add(request)
    }
}
