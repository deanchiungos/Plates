import SwiftUI

/// Cross-tab navigation, deliberately kept to the one jump that needs it.
///
/// Screens reach their destinations by pushing within their own tab, and that
/// should stay true — a global router is a hole everything eventually falls
/// through. This exists because a trip's record lives on the Trips tab while the
/// Trail lives behind More, and "show me this trip's road" should be one tap, not
/// a tab switch, a push and a scope menu. The sheet cannot push onto another
/// tab's stack, so it leaves a note here instead; each reader consumes its half.
@Observable
final class Router {
    /// The selected tab, lifted out of `RootView` so something outside the tab
    /// bar can change it.
    var tab: Int

    /// A scope the Trail should open on. One-shot: `MoreScreen` sees it and
    /// pushes the Trail, the Trail takes it and clears it.
    var pendingTrail: TrailScreen.Scope?

    init(tab: Int = 0) {
        self.tab = tab
    }

    /// The whole of the cross-tab API: jump to the Trail, opened on this scope.
    func showTrail(_ scope: TrailScreen.Scope) {
        pendingTrail = scope
        tab = RootView.moreTab
    }

    /// Go and collect. The Book tab's "collect into this book" used to only change
    /// what the Game screen was filling and leave you looking at the same album,
    /// which is indistinguishable from nothing happening — the one thing it promised
    /// was on another tab.
    func showGame() {
        tab = RootView.gameTab
    }
}
