import Foundation

/// Wikipedia's date ranges, reduced to the year a design started.
///
/// The raw strings are written by hundreds of different editors and it shows:
///
///     1978–82
///     mid2018 – present
///     mid2015 –mid2018
///     July 1, 1986 – December 2000
///     March 2022 -August 2024
///     October 15, 2018 – November 2024
///     January 3, 2022 – present
///
/// Every one of those is trying to say the same two things, and only the first of
/// them is worth a line on a card: *when did this design start*. The end is already
/// implied by the design listed above it, and a list of ranges in six different
/// house styles reads as a data dump rather than a history.
///
/// Whatever was actually written is kept and shown in full on the design's own card,
/// because "March 2022 -August 2024" being ugly is not a reason to throw away the day
/// somebody bothered to record.
enum PlateDates {

    /// A four-digit year that is not part of a longer number — so `mid2018` yields
    /// 2018 and a serial like `A-112000` yields nothing.
    private static let year = try? NSRegularExpression(
        pattern: "(?<![0-9])(1[89][0-9]{2}|20[0-9]{2})(?![0-9])")

    /// "1986". Falls back to the raw text, tidied, when there is no year in it at all.
    static func start(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let year,
              let match = year.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else {
            return text.split(separator: " ").joined(separator: " ")
        }
        return String(text[range])
    }

    /// The span, tidied: "2013 – 2021", "2021 – now", "1967".
    ///
    /// The raw strings are a scrape and they read like one. "December 29, 2021 –
    /// present", "April 15, 2013 – December 28, 2021", "mid2018 – present" and
    /// "AK January 1, 2010 – December 2022 ; AK January 2023 – present" are all
    /// saying a thing that fits in seven characters, and printing them verbatim
    /// under a photograph turns a clean screen into a database dump.
    ///
    /// The exact days are not lost, only unprinted: nobody looking at a plate
    /// wants to know it stopped being issued on a Tuesday.
    ///
    /// "now" rather than "present" because it also does the job the CURRENT tag
    /// used to do. A range ending in a year has ended; a range ending in "now"
    /// has not, and that is legible without a badge explaining it.
    static func range(_ raw: String) -> String {
        let years = allYears(raw)
        guard let first = years.first else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if isOpenEnded(raw) { return "\(first) – now" }
        guard let last = years.last, last != first else { return "\(first)" }
        return "\(first) – \(last)"
    }

    /// "8 years", "13 years so far", or nothing when the span is a single year
    /// or the design ran in more than one stretch.
    ///
    /// The second line of a timeline row wants to say something the first line
    /// does not, and how long a look lasted is the question a timeline invites.
    static func duration(_ raw: String, now: Int = currentYear) -> String? {
        // A semicolon means two separate runs, and the gap between them is not
        // time the design spent on the road.
        guard !raw.contains(";") else { return nil }
        let years = allYears(raw)
        guard let first = years.first else { return nil }
        let open = isOpenEnded(raw)
        let last = open ? now : (years.last ?? first)
        let span = last - first
        guard span >= 1 else { return nil }
        return "\(span) year\(span == 1 ? "" : "s")" + (open ? " so far" : "")
    }

    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private static func isOpenEnded(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("present") || lower.contains("current")
    }

    /// Every four-digit year in the string, in order, with two-digit range ends
    /// expanded — "1982–85" means 1985, not nothing.
    private static func allYears(_ raw: String) -> [Int] {
        guard let year else { return [] }
        let text = raw as NSString
        var out: [Int] = []
        var lastEnd = 0
        year.enumerateMatches(in: raw, range: NSRange(location: 0, length: text.length)) {
            match, _, _ in
            guard let match else { return }
            // A two-digit tail hanging off the previous year, as in "1990–93".
            // Read it against that year's century rather than dropped.
            let gap = text.substring(with: NSRange(location: lastEnd,
                                                   length: match.range.location - lastEnd))
            if let previous = out.last,
               let short = shortTail(in: gap),
               let expanded = expand(short, after: previous) {
                out.append(expanded)
            }
            if let value = Int(text.substring(with: match.range)) { out.append(value) }
            lastEnd = match.range.location + match.range.length
        }
        if let previous = out.last,
           let short = shortTail(in: text.substring(from: lastEnd)),
           let expanded = expand(short, after: previous) {
            out.append(expanded)
        }
        return out
    }

    private static let tail = try? NSRegularExpression(
        pattern: "^\\s*[–—-]\\s*([0-9]{2})(?![0-9])")

    /// A two-digit number opening the fragment, right after a dash: the "85" of
    /// "1982–85". Anything after it is somebody else's problem.
    private static func shortTail(in fragment: String) -> Int? {
        guard let tail,
              let match = tail.firstMatch(in: fragment,
                                          range: NSRange(location: 0,
                                                         length: (fragment as NSString).length)),
              let range = Range(match.range(at: 1), in: fragment)
        else { return nil }
        return Int(fragment[range])
    }

    private static func expand(_ short: Int, after year: Int) -> Int? {
        let candidate = (year / 100) * 100 + short
        return candidate >= year ? candidate : candidate + 100
    }

    /// The same year as a number, for sorting.
    ///
    /// Sorting these strings alphabetically looks like it works and does not:
    /// "1984–present" sorts above "2003 – June 2010" because `1` precedes `2`,
    /// but "November 19, 2018" sorts above both because `N` precedes every
    /// digit. Ohio's designs came out 2021, 2001, 2004, 2013, 1967 in that
    /// order, which is no order at all.
    static func startYear(_ raw: String) -> Int {
        Int(start(raw)) ?? 0
    }
}
