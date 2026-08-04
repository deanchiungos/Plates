import CloudKit
import CoreData
import Foundation
import Observation

/// What to tell the user about iCloud.
///
/// The reason this exists at all, rather than the app just quietly syncing: a
/// lifetime collection with silent backup is worse than no backup, because you only
/// discover the truth at the moment you have already lost the phone. A competitor
/// review makes the failure concrete — *"Had to wipe my phone and had to start the
/// game over after 42 states."* So the Book screen states plainly whether the plates
/// on it exist anywhere other than this device.
///
/// The bar for saying "backed up" is deliberately high: an *observed successful
/// export*, not merely a container that opened with iCloud configured. Configuration
/// succeeding proves the entitlement is present, nothing more.
@MainActor
@Observable
final class CloudBackup {
    static let shared = CloudBackup()

    enum State: Equatable {
        /// Not iCloud-backed. The string is the reason, when there is one.
        case off(String?)
        /// Configured, but nobody is signed into iCloud on this device.
        case noAccount
        /// Configured and signed in, with no sync observed yet.
        case waiting
        case working
        case backedUp(Date)
        case failed(String)
    }

    private(set) var state: State
    private var observer: NSObjectProtocol?

    private init() {
        #if DEBUG
        // `-backup synced` and friends pin the row to one state. Every other state
        // needs a real account, a real container and a real network to reach, none of
        // which a screenshot run has.
        if let forced = Self.forcedState {
            state = forced
            return
        }
        #endif

        guard PlatesStore.isCloudBacked else {
            state = .off(PlatesStore.cloudFailure)
            return
        }
        state = .waiting
        watchSyncEvents()
    }

    #if DEBUG
    private static var forcedState: State? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-backup"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "off":       return .off(nil)
        case "noaccount": return .noAccount
        case "waiting":   return .waiting
        case "working":   return .working
        case "synced":    return .backedUp(Date().addingTimeInterval(-240))
        case "failed":    return .failed("iCloud storage is full.")
        default:          return nil
        }
    }
    #endif

    /// SwiftData runs on `NSPersistentCloudKitContainer` underneath, which posts an
    /// event per setup / import / export whether or not anyone is listening. It is the
    /// only honest signal available — there is no public SwiftData API that reports
    /// "your data is safe" — so the absence of events is treated as "waiting", never
    /// as failure.
    private func watchSyncEvents() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }

            MainActor.assumeIsolated { self?.apply(event) }
        }
    }

    private func apply(_ event: NSPersistentCloudKitContainer.Event) {
        // An event with no end date is still in flight.
        guard let ended = event.endDate else {
            state = .working
            return
        }

        if let error = event.error {
            // A quota or network error is not the same as a broken setup, but from the
            // user's side the only thing that matters is that the last attempt did not
            // land — so it reads as failed either way, with the reason attached.
            state = .failed(Self.describe(error))
            return
        }

        switch event.type {
        case .export:
            // Only an export proves *your* data reached iCloud. An import means the
            // account works, which is not the same promise.
            state = .backedUp(ended)
        case .setup, .import:
            if case .backedUp = state { return }
            state = .waiting
        @unknown default:
            break
        }
    }

    /// Turns a CloudKit failure into something worth reading.
    ///
    /// `localizedDescription` is close to useless for the errors that actually happen
    /// here. The common one is `.partialFailure` — CloudKit's umbrella for "some
    /// records failed" — whose description is the bare "The operation couldn't be
    /// completed (CKErrorDomain error 2.)". The real cause is buried in
    /// `partialErrorsByItemID`, so unwrap one level and describe *that*.
    ///
    /// This file exists to avoid unactionable messages; passing error 2 straight
    /// through would have been exactly that.
    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }

        if ck.code == .partialFailure,
           let underlying = ck.partialErrorsByItemID?.values.first {
            return describe(underlying)
        }

        switch ck.code {
        case .networkUnavailable, .networkFailure:
            return "No connection to iCloud. Your plates will copy over once you are back online."
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to back up your plates."
        case .quotaExceeded:
            return "Your iCloud storage is full, so nothing new can be copied over."
        case .permissionFailure, .managedAccountRestricted:
            return "This iCloud account is not allowed to store app data."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy. This will retry on its own."
        case .invalidArguments, .unknownItem, .serverRejectedRequest, .constraintViolation:
            // Almost always the schema: a TestFlight or App Store build talks to the
            // *production* CloudKit environment, which never creates record types on
            // demand the way the development one does. Deploying the schema in the
            // CloudKit Console fixes it, and no new build is needed.
            #if DEBUG
            return "iCloud rejected the data (\(ck.code.rawValue)). "
                 + "The production CloudKit schema is probably not deployed."
            #else
            return "Your plates could not be copied to iCloud. This is being looked into."
            #endif
        default:
            return ck.localizedDescription
        }
    }

    /// Signed out of iCloud is by far the likeliest reason a correctly configured app
    /// never syncs, and it is the one thing the user can actually fix, so it is worth
    /// asking about rather than sitting on "waiting" forever.
    func checkAccount() async {
        guard PlatesStore.isCloudBacked else { return }
        guard case .waiting = state else { return }

        let status = try? await CKContainer(
            identifier: "iCloud.com.eggeppel.plates").accountStatus()

        if let status, status != .available {
            state = .noAccount
        }
    }
}

// MARK: - Copy

extension CloudBackup.State {
    var title: String {
        switch self {
        case .off:                return "Not backed up"
        case .noAccount:          return "Sign in to iCloud"
        case .waiting, .working:  return "Backing up to iCloud"
        case .backedUp:           return "Backed up to iCloud"
        case .failed:             return "Backup problem"
        }
    }

    var detail: String {
        switch self {
        case .off(let reason):
            return reason == nil
                ? "Your plates live on this phone only. Losing it loses the book."
                : "Your plates live on this phone only. \(reason!)"
        case .noAccount:
            return "Your plates are on this phone only until you sign in, in Settings."
        case .waiting:
            return "Your plates will copy to iCloud shortly."
        case .working:
            return "Copying now\u{2026}"
        case .backedUp(let when):
            return "Last copied \(when.formatted(.relative(presentation: .named)))."
        case .failed(let reason):
            return reason
        }
    }

    var isHealthy: Bool {
        switch self {
        case .backedUp, .waiting, .working: return true
        case .off, .noAccount, .failed:     return false
        }
    }

    var symbol: String {
        switch self {
        case .backedUp:          return "checkmark.icloud.fill"
        case .waiting, .working: return "arrow.trianglehead.2.clockwise.rotate.90.icloud"
        case .noAccount:         return "person.icloud"
        case .off, .failed:      return "exclamationmark.icloud"
        }
    }
}
