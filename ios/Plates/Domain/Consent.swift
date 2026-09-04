import Foundation

/// Whether this device has agreed to the current Terms, and the record of it.
///
/// **Why a record.** "By using the app you agree" is browsewrap, and courts decline
/// to enforce it with some regularity: nobody can show the person saw the terms,
/// let alone assented. What survives is clickwrap: the documents put in front of
/// somebody, a button that says *agree*, and a record of when they pressed it and
/// what edition was on screen. That record is these three defaults. It stays on the
/// device, because there is no TAGS server to send it to; that is a limitation
/// worth knowing about, and it is still a record where before there was none.
///
/// **What re-asks.** The version string, not the fingerprint. The fingerprint is
/// evidence of the exact text agreed to; the version is the editorial decision that
/// a change is one people should agree to again. A corrected typo changes the first
/// and not the second, and should not put a gate in front of every user.
enum Consent {
    private static let versionKey     = "legal.acceptedVersion"
    private static let atKey          = "legal.acceptedAt"
    private static let fingerprintKey = "legal.acceptedFingerprint"

    static var acceptedVersion: String? { AppDefaults.store.string(forKey: versionKey) }
    static var acceptedAt: Date? { AppDefaults.store.object(forKey: atKey) as? Date }
    static var acceptedFingerprint: String? { AppDefaults.store.string(forKey: fingerprintKey) }

    /// True once this device has agreed to the edition this build carries.
    static var isCurrent: Bool { acceptedVersion == Legal.version }

    /// True when they agreed to an earlier edition, so the gate can say "changed"
    /// rather than introducing itself as if for the first time.
    static var isUpdate: Bool { acceptedVersion != nil && !isCurrent }

    static func record() {
        AppDefaults.store.set(Legal.version, forKey: versionKey)
        AppDefaults.store.set(Date(), forKey: atKey)
        AppDefaults.store.set(Legal.fingerprint, forKey: fingerprintKey)
    }

    #if DEBUG
    /// `-consentReset` forgets the agreement, which is how the gate is looked at
    /// twice. `-consented` records one silently, so every other launch flag that
    /// drives straight to a screen keeps working without a tap on the way.
    static func applyLaunchArguments() {
        if LaunchFlags.isSet("-consentReset") {
            for key in [versionKey, atKey, fingerprintKey] {
                AppDefaults.store.removeObject(forKey: key)
            }
        }
        if LaunchFlags.isSet("-consented") { record() }
    }
    #endif
}
