import Foundation

extension String {

    /// A localized string with automatic grammar agreement actually applied.
    ///
    /// `String(localized: "^[\(n) plate](inflect: true)")` looks like it should work
    /// and does not: it returns the markup verbatim, so the chip on the Drive screen
    /// read `^[2 set](inflect: true)` in as many words. Inflection is an *attributed*
    /// transformation — the agreement engine needs the runs of the string to know
    /// which span the number governs — so it only happens on the way through
    /// `AttributedString`. `Text(someLocalizedStringKey)` gets this for free, which
    /// is why the popups were right and these two call sites were wrong.
    ///
    /// Use this anywhere the words have to come back as a `String` rather than a
    /// `Text` — a computed property feeding a label, mostly. Where a
    /// `LocalizedStringKey` will do, pass the key and let SwiftUI do it.
    ///
    /// The key still lands in the String Catalog: it is a literal in a
    /// `LocalizedStringResource` position, which is all the compiler's harvest
    /// looks for.
    static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }
}
