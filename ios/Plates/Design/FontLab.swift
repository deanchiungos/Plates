#if DEBUG
import SwiftUI
import UIKit

/// Debug-only typeface comparison. Launch with `-fontLab`; `-fontLab duel` shows
/// only the current face and its bundled challenger, side by side.
///
/// Every candidate here ships with iOS except Overpass, which is bundled (see
/// Info.plist). The shipping-fonts constraint was the original brief and is what
/// produced Avenir Next; Overpass is the question of whether escaping that
/// constraint buys anything — it is a free digitisation of Highway Gothic, the
/// U.S. interstate signage face, which makes it the text-face sibling of the DIN
/// the plates are already set in.
///
/// The row header resolves each PostScript name through `UIFont` and says so. That
/// check is the point of the screen as much as the samples are: `Font.custom(_:size:)`
/// falls back to the system face without complaining, so a mistyped name renders as
/// SF Pro and looks merely disappointing rather than broken.
struct FontLab: View {

    private struct Candidate: Identifiable {
        let name: String
        /// Empty string means the system face.
        let regular: String
        let semibold: String
        let bold: String
        var id: String { name }
    }

    private let candidates: [Candidate] = [
        // The label used to say current, from before the app switched to Avenir.
        .init(name: "SF Pro — system", regular: "", semibold: "", bold: ""),
        .init(name: "Avenir Next — previous",
              regular: "AvenirNext-Regular",
              semibold: "AvenirNext-DemiBold",
              bold: "AvenirNext-Bold"),
        .init(name: "Overpass — current",
              regular: "Overpass-Regular",
              semibold: "Overpass-SemiBold",
              bold: "Overpass-Bold"),
        .init(name: "Seravek",
              regular: "Seravek",
              semibold: "Seravek-Medium",
              bold: "Seravek-Bold"),
        .init(name: "Futura",
              regular: "Futura-Medium",
              semibold: "Futura-Medium",
              bold: "Futura-Bold"),
        .init(name: "American Typewriter",
              regular: "AmericanTypewriter",
              semibold: "AmericanTypewriter-Semibold",
              bold: "AmericanTypewriter-Bold"),
        .init(name: "Gill Sans",
              regular: "GillSans",
              semibold: "GillSans-Semibold",
              bold: "GillSans-Bold"),
        .init(name: "Charter",
              regular: "Charter-Roman",
              semibold: "Charter-Black",
              bold: "Charter-Bold")
    ]

    private var page: [Candidate] {
        let args = ProcessInfo.processInfo.arguments
        // The decision as it will actually be made: incumbent against challenger,
        // nothing else on the page.
        if args.contains("duel") {
            return candidates.filter { $0.name.hasSuffix("current") || $0.name.hasSuffix("previous") }
                .filter { !$0.regular.isEmpty }
        }
        let second = args.contains("2")
        return second ? Array(candidates.dropFirst(4)) : Array(candidates.prefix(4))
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // `-fontLab 2` shows the rest. Paged rather than shrunk: these
                    // have to be judged at the sizes the app actually sets them.
                    ForEach(page) { sample($0) }
                }
                .padding(16)
            }
        }
    }

    private func sample(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(c.name.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.route)
                Text(availability(c))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(missing(c) ? .red : Theme.found)
            }

            // The same four roles the app actually uses, at the sizes it uses them.
            //
            // `verbatim` because these are type specimens, not copy. Written as
            // plain literals they extract into the String Catalog like any other
            // sentence, so a translator opening the catalogue finds "LEGENDARY"
            // and a fact about a drive-in theatre sitting beside the real UI.
            // This screen only exists in a DEBUG build; the catalogue ships.
            Text(verbatim: "LEGENDARY")
                .font(font(c.bold, 30))
                .foregroundStyle(Theme.paint)
            Text(verbatim: "New Jersey")
                .font(font(c.bold, 19))
                .foregroundStyle(Theme.ink)
            Text(verbatim: "The first drive-in theatre opened in Camden, New Jersey, in 1933.")
                .font(font(c.regular, 17))
                .foregroundStyle(Theme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "Playing with others?  Start a party")
                .font(font(c.semibold, 15))
                .foregroundStyle(Theme.route)
            Text(verbatim: "Rarity is scored against this route.")
                .font(font(c.regular, 12.5))
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
        )
    }

    private func font(_ name: String, _ size: CGFloat) -> Font {
        name.isEmpty ? .system(size: size, weight: .regular) : .custom(name, size: size)
    }

    private func missing(_ c: Candidate) -> Bool {
        guard !c.regular.isEmpty else { return false }
        return [c.regular, c.semibold, c.bold].contains { UIFont(name: $0, size: 12) == nil }
    }

    private func availability(_ c: Candidate) -> String {
        c.regular.isEmpty ? "system" : (missing(c) ? "NAME NOT FOUND" : "available")
    }
}
#endif
