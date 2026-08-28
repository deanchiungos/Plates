import Foundation

/// The preferences the app writes to.
///
/// `UserDefaults.standard`, in the app, always — this is not a settings layer and it
/// adds nothing to a normal run. It exists so `-partyMergeCheck` can point every
/// preference this app owns at a scratch suite for the length of a run and throw the
/// suite away afterwards.
///
/// That matters more than it sounds. The check's own header promises it never
/// touches real state, and it was doing exactly that: `FactBook.reset()` wipes every
/// fact you have unlocked, permanently, on the phone of whoever ran it. There is no
/// undo and nothing says it happened — the facts simply start arriving as new again.
/// A debug tool that damages the machine it runs on is one people stop running, and
/// this one is the only evidence the merge code works.
///
/// Swappable only in DEBUG, so a shipped build has no path to it. `nonisolated
/// (unsafe)` because the single writer is the check, before anything here is running
/// concurrently, and the alternative is isolating a property every view body reads.
enum AppDefaults {
    #if DEBUG
    nonisolated(unsafe) static var store: UserDefaults = .standard
    #else
    static let store: UserDefaults = .standard
    #endif
}
