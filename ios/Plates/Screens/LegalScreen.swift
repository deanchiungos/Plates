import CryptoKit
import SwiftUI

/// The Privacy Policy and the Terms, as documents.
///
/// The first version of this page was built out of `SettingsGroup` cards, the same
/// shape How to Play uses, and that was the wrong instinct. How to Play is a
/// reference somebody dips into: cards are right there, because each one is a
/// separate answer and nobody reads the page end to end. A legal document is the
/// opposite. It is one instrument, its clauses are numbered because they refer to
/// each other, and chopping it into twenty floating panels makes it read as twenty
/// opinions rather than one agreement. So this is a single sheet, top to bottom,
/// with numbered headings and running text, which is what everybody already knows
/// a document looks like.
///
/// **These strings are deliberately not localized.** Every other user-facing string
/// in the app is a `LocalizedStringKey` and lands in the String Catalog. These are
/// not, and use `Text(verbatim:)`, for two reasons: eight thousand words of counsel
/// text would swamp the catalog and make every real UI string harder to find in it,
/// and a machine translation of an indemnity clause is not the indemnity clause.
/// If TAGS ever ships in another language these get translated by a person, as
/// separate documents, or they stay in English with a note.
///
/// The same text is published at playtagsnow.com. App Store Connect requires a URL
/// and will not accept an in-app copy, so the web version is the canonical one and
/// this is the convenience copy. When one changes, both change.
enum Legal {
    /// Who is publishing, and where to write.
    ///
    /// The documents themselves spell the addresses out inline, because in a legal
    /// instrument the address is part of the sentence and not a variable. These are
    /// for the parts of the app that have to *reach* a mailbox rather than quote
    /// one: the masthead above, and anything that composes mail to support.
    enum Publisher {
        static let entity  = "TAGs Media LLC"
        static let site    = "www.PlayTAGsNow.com"
        static let privacy = "privacy@playtagsnow.com"
        static let support = "support@playtagsnow.com"
        static let legal   = "legal@playtagsnow.com"
    }

    static let effectiveDate = "September 3, 2026"

    /// Which edition of the documents this build carries.
    ///
    /// The consent gate compares the version a device agreed to against this one,
    /// and asks again when they differ. So: bump it when the documents change in a
    /// way people should agree to afresh, and leave it alone for a typo. The
    /// fingerprint below records exactly which text was agreed to either way.
    static let version = "2026-09-03"

    /// A hash of both documents' full text.
    ///
    /// Recorded alongside the version when somebody agrees, printed in the Legal
    /// section, and written into the website pages. It answers the question a
    /// version string cannot: not "which edition" but "which exact words". If the
    /// app's copy and the website's copy ever disagree, their fingerprints disagree,
    /// and that is visible without reading either.
    static let fingerprint: String = {
        let text = (privacy + terms).map(\.text).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    /// The first twelve characters, for anywhere a human reads it.
    static var shortFingerprint: String { String(fingerprint.prefix(12)) }

    /// One piece of a document.
    ///
    /// A tagged block rather than free-form views, so the typography is decided
    /// once here instead of once per clause. Twenty-three sections hand-styled is
    /// twenty-three chances for one heading to come out a half point off, and that
    /// is exactly the kind of drift that makes a document look unofficial.
    enum Block {
        /// A numbered section heading.
        case heading(String)
        /// An unnumbered heading inside a section.
        case sub(String)
        /// Running text.
        case body(String)
        /// An item in a list.
        case bullet(String)
        /// A conspicuous clause. Warranty disclaimers and liability limits are
        /// capitalised because statute in several states asks for them to be
        /// conspicuous, so the capitals are load-bearing and not shouting.
        case caps(String)
        /// The signature block at the end.
        case contact(String)

        var text: String {
            switch self {
            case .heading(let t), .sub(let t), .body(let t),
                 .bullet(let t), .caps(let t), .contact(let t): t
            }
        }
    }
}

// MARK: - The page

/// One document, rendered.
struct LegalScreen: View {
    let title: String
    let blocks: [Legal.Block]

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead

                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        view(for: block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 28)
                // The whole document on one sheet. The border and the fill are the
                // ones every card in the app uses, so the page still belongs here;
                // it is the absence of *internal* edges that makes it a document.
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
                .padding(Theme.screenPadding)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Title, publisher, date, rule. The four things that tell somebody at a glance
    /// which document this is and whether it is the current one.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title.uppercased())
                .font(Theme.PlateFont.condensed(24))
                .tracking(1.6)
                .foregroundStyle(Theme.ink)

            Text(verbatim: Legal.Publisher.entity)
                .font(.plates(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text(verbatim: "Effective date: \(Legal.effectiveDate)")
                .font(.plates(size: 12))
                .foregroundStyle(Theme.inkMuted)

            Rectangle()
                .fill(Theme.ink.opacity(0.85))
                .frame(height: 1.5)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func view(for block: Legal.Block) -> some View {
        switch block {
        case .heading(let text):
            Text(verbatim: text)
                .font(.plates(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 22)
                .padding(.bottom, 7)

        case .sub(let text):
            Text(verbatim: text)
                .font(.plates(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11)
                .padding(.bottom, 5)

        case .body(let text):
            paragraph(text)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                // A glyph rather than a `Label`, so the hanging indent is exact and
                // a wrapped second line sits under the first word and not under
                // the dot.
                Text(verbatim: "\u{2022}")
                    .font(.plates(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
                paragraph(text)
            }
            .padding(.leading, 4)

        case .caps(let text):
            Text(verbatim: text)
                .font(.plates(size: 12.5, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(Theme.ink)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)

        case .contact(let text):
            Text(verbatim: text)
                .font(.plates(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                // Selectable, because the only thing anybody does with this block
                // is copy an address out of it.
                .textSelection(.enabled)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.plates(size: 13.5))
            .foregroundStyle(Theme.ink)
            // Legal prose runs to long sentences and this is the one setting that
            // decides whether a wall of them is readable at all.
            .lineSpacing(3.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
    }
}

// MARK: - The two documents

struct PrivacyPolicyScreen: View {
    var body: some View { LegalScreen(title: "Privacy Policy", blocks: Legal.privacy) }
}

struct TermsScreen: View {
    var body: some View { LegalScreen(title: "Terms and Conditions", blocks: Legal.terms) }
}
