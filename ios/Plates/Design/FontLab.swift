#if DEBUG
import SwiftUI
import UIKit

/// Debug-only typeface comparison. Launch with `-fontLab`.
///
/// Every candidate here already ships with iOS, so switching to one costs no bundle
/// size, no licence and no `UIAppFonts` entry.
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
        .init(name: "SF Pro — current", regular: "", semibold: "", bold: ""),
        .init(name: "Avenir Next",
              regular: "AvenirNext-Regular",
              semibold: "AvenirNext-DemiBold",
              bold: "AvenirNext-Bold"),
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
            Text("LEGENDARY")
                .font(font(c.bold, 30))
                .foregroundStyle(Theme.paint)
            Text("New Jersey")
                .font(font(c.bold, 19))
                .foregroundStyle(Theme.ink)
            Text("The first drive-in theatre opened in Camden, New Jersey, in 1933.")
                .font(font(c.regular, 17))
                .foregroundStyle(Theme.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            Text("Playing with others?  Start a party")
                .font(font(c.semibold, 15))
                .foregroundStyle(Theme.route)
            Text("Rarity is scored against this route.")
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
