import CloudKit
import Foundation

/// The one thing every CloudKit failure has in common: it usually arrives wearing
/// somebody else's coat.
///
/// `.partialFailure` is CloudKit's umbrella for "some of the records did not save",
/// and it is the common one — any batch write can return it. Its own description is
/// the bare "The operation couldn't be completed (CKErrorDomain error 2.)"; the
/// reason is buried in `partialErrorsByItemID`. So every place that turns an error
/// into a sentence has to unwrap it first, and a place that forgets shows error 2 to
/// somebody whose iCloud is simply full.
///
/// Only the unwrapping is shared. The wording deliberately is not: backing up and
/// sharing fail for the same reasons and mean different things by them, and "your
/// plates will copy over once you are back online" is the wrong sentence about an
/// invitation that did not send.
enum CloudErrors {

    /// The error actually worth describing, or nil when it is not CloudKit's.
    ///
    /// Which of several partial errors gets picked is arbitrary — they arrive in a
    /// dictionary — but they are nearly always the same failure repeated once per
    /// record, and one accurate sentence beats a list nobody can act on.
    static func meaningful(_ error: Error) -> CKError? {
        guard let ck = error as? CKError else { return nil }
        guard ck.code == .partialFailure,
              let underlying = ck.partialErrorsByItemID?.values.first else { return ck }
        return meaningful(underlying) ?? ck
    }

    /// Whether the thing we were about to change is already gone.
    ///
    /// Worth its own answer because "it is not there" is a success for anything that
    /// was trying to remove it, and a failure for everything else.
    static func isAlreadyGone(_ error: Error) -> Bool {
        guard let ck = meaningful(error) else { return false }
        switch ck.code {
        case .zoneNotFound, .unknownItem, .userDeletedZone: return true
        default: return false
        }
    }
}
