import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Telling the home screen something changed.
///
/// A one-line wrapper because `WidgetKit` is not available everywhere this code
/// compiles — the app intents target and any future extension included — and an
/// `#if canImport` at each call site would be four copies of the same apology.
///
/// Deliberately not called on a timer. A widget that reloads on a schedule spends
/// somebody's battery guessing; this fires only when the sidecar actually changed,
/// which is the only moment there is anything new to draw.
enum WidgetRefresh {
    static func request() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
