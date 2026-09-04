#if DEBUG
import Foundation

/// Writes the Privacy Policy and the Terms out as standalone web pages.
///
/// **Why this exists.** App Store Connect will not accept an in-app copy of a
/// privacy policy; it wants a URL, and the Terms need one too. That means the same
/// two documents have to exist in two places, and two copies of a legal instrument
/// maintained by hand is a guarantee that one day they will say different things,
/// silently, and the one somebody relies on will be the wrong one. So there is one
/// source: the `Legal.privacy` and `Legal.terms` arrays that the app itself renders.
/// The website is generated from them and never edited directly.
///
/// **How to run it.** `-legalHTML` on the scheme, or:
///
///     xcrun simctl launch --console <device> com.eggeppel.plates -legalHTML
///
/// It prints the two paths it wrote. Copy those files to the web host. The page is
/// entirely self-contained: no stylesheet, no script, no font to fetch, nothing to
/// track a reader with, which is the least a privacy policy can do. It follows the
/// same shape as `-poster` and `-layoutStress`, and like them it is DEBUG only,
/// because nothing about it belongs on a phone.
enum LegalExport {

    static var isRequested: Bool { LaunchFlags.isSet("-legalHTML") }

    static func run() -> String {
        var lines = ["── legal export ──"]
        for (file, title, blocks) in [("privacy.html", "Privacy Policy", Legal.privacy),
                                      ("terms.html", "Terms and Conditions", Legal.terms)] {
            let html = page(title: title, blocks: blocks)
            guard let dir = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first else {
                lines.append("no documents directory")
                continue
            }
            let url = dir.appendingPathComponent(file)
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                lines.append(url.path)
            } catch {
                lines.append("\(file): \(error.localizedDescription)")
            }
        }
        lines.append("── legal export: done ──")
        return lines.joined(separator: "\n")
    }

    // MARK: - The page

    /// The app's own colors and proportions, in a form a browser understands.
    ///
    /// A reader who taps through from the App Store listing and a reader who opens
    /// the page inside the app should not feel they have arrived at two different
    /// companies. The type stack falls back to the system's UI face rather than
    /// fetching Overpass, because a webfont request is a third-party connection and
    /// this is the one page on which that would be embarrassing.
    private static func page(title: String, blocks: [Legal.Block]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .heading(let t): body += "    <h2>\(esc(t))</h2>\n"
            case .sub(let t):     body += "    <h3>\(esc(t))</h3>\n"
            case .body(let t):    body += "    <p>\(esc(t))</p>\n"
            case .bullet(let t):  body += "    <p class=\"b\">\(esc(t))</p>\n"
            case .caps(let t):    body += "    <p class=\"caps\">\(esc(t))</p>\n"
            case .contact(let t):
                let joined = t.split(separator: "\n")
                    .map { esc($0.trimmingCharacters(in: .whitespaces)) }
                    .joined(separator: "<br>")
                body += "    <p class=\"contact\">\(joined)</p>\n"
            }
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title)) | TAGS</title>
        <style>
        :root { color-scheme: light; }
        body {
          margin: 0; background: #FAF7EF; color: #1B2231;
          font: 16px/1.62 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          -webkit-text-size-adjust: 100%;
        }
        main {
          max-width: 44rem; margin: 2rem auto; padding: 2rem 1.5rem 3rem;
          background: #fff; border: 1px solid #E7E1D1; border-radius: 16px;
        }
        h1 {
          font-size: 1.6rem; letter-spacing: .08em; text-transform: uppercase;
          margin: 0 0 .35rem;
        }
        .who { font-weight: 600; margin: 0; }
        .date { color: #8A8377; margin: .2rem 0 0; font-size: .92rem; }
        hr { border: 0; border-top: 1.5px solid #1B2231; margin: 1.1rem 0 1.6rem; }
        h2 { font-size: 1.06rem; margin: 2rem 0 .5rem; }
        h3 { font-size: .98rem; margin: 1.3rem 0 .35rem; }
        p { margin: 0 0 .75rem; }
        p.b { padding-left: 1.15rem; text-indent: -1.15rem; }
        p.b::before { content: "\\2022"; color: #8A8377; padding-right: .55rem; }
        p.caps { font-size: .9rem; font-weight: 600; }
        p.contact { font-weight: 600; margin-top: .4rem; }
        p.fine { color: #8A8377; font-size: .82rem; margin-top: 2.2rem; }
        a { color: #1B4E8C; }
        @media (max-width: 34rem) {
          main { margin: 0; border: 0; border-radius: 0; padding: 1.5rem 1.15rem 2.5rem; }
        }
        </style>
        </head>
        <body>
        <main>
            <h1>\(esc(title))</h1>
            <p class="who">\(esc(Legal.Publisher.entity))</p>
            <p class="date">Effective date: \(esc(Legal.effectiveDate))</p>
            <hr>
        \(body)    <p class="fine">Version \(esc(Legal.version)). Document fingerprint \(esc(Legal.shortFingerprint)). The same fingerprint is shown under Legal in the app; if the two differ, the two texts differ.</p>
        </main>
        </body>
        </html>
        """
    }

    /// Ampersand first, or every entity written after it gets its own escaped.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
#endif
