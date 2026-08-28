import CoreText
import Foundation

/// Whether this device can actually draw a character.
///
/// Emoji are not a fixed set. They arrive with new OS versions, and a phone one
/// release behind has no glyph for the ones it has not heard of — it draws the
/// empty box instead. That is a real case here rather than a theoretical one: a
/// party puts four phones side by side, and a shared book puts a stranger's chosen
/// face in your collection for years. Somebody picking this season's emoji should
/// not show up as a broken square on their sister's older iPhone.
///
/// So a face is only used if it can be drawn, and initials — which are always
/// drawable — are the fallback. Checked rather than assumed, because the failure is
/// silent: nothing throws, the layout is fine, and the only symptom is a box where
/// a person should be.
///
/// **What this does not catch.** The iOS 26.3 simulator draws every emoji as a box
/// while `CTFontGetGlyphsForCharacters` cheerfully reports the glyph exists — its
/// emoji font has the glyph *ids* but not the bitmaps behind them. There is no API
/// that answers "and can you actually paint it": emoji are bitmap glyphs, so
/// `CTFontCreatePathForGlyph` returns nil for all of them, working or not. So this
/// guard covers the case it was written for — a font that has never heard of the
/// character — and cannot cover a font that has heard of it and is missing the
/// artwork. On a real device the second case does not arise.
@MainActor
enum Glyphs {

    /// Cached: this is asked once per avatar per render pass, and the answer cannot
    /// change while the app is running.
    private static var known: [String: Bool] = [:]

    static func canDraw(_ text: String) -> Bool {
        if let cached = known[text] { return cached }

        var utf16 = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        // Asked of the emoji font specifically. A cascade through the system font
        // would answer "yes" via the last-resort font, which is the box we are
        // trying to avoid drawing.
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 16, nil)
        let complete = CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count)

        known[text] = complete
        return complete
    }
}

extension Player {
    /// True when this player's chosen face will actually draw here.
    ///
    /// `@MainActor` because `Glyphs` is: the cache behind it is a plain mutable
    /// dictionary, and this is reached through a `@Model` class that carries no
    /// isolation of its own. Every caller today is a SwiftUI body, so saying so
    /// costs nothing and closes the door on a poster render moved off the main
    /// thread finding a torn dictionary rather than a stale answer.
    @MainActor
    var usesEmoji: Bool {
        guard let avatar, !avatar.isEmpty else { return false }
        return Glyphs.canDraw(avatar)
    }
}
