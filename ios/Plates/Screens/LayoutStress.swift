import SwiftUI
import SwiftData
import UIKit

#if DEBUG

/// Draws the app's crowded rows at every width and text size they can be asked for,
/// with names and parties long enough to break them, and writes the sheets out as
/// PNGs.
///
/// `-layoutStress` from the launch arguments.
///
/// The rows collected here have one shape in common: several things competing for a
/// single line of width, where at least one of them grows with what somebody types
/// and all of them grow with the reader's text size. A trip row is a name, a route, a
/// stack of faces and a score; the Book tab's header is a name, a date, four faces
/// and an edit circle; the Drive header is a title with a SWITCH control pinned
/// opposite it. The failure mode is not a crash or a warning. It is two labels
/// quietly sitting on top of each other on somebody else's phone, at a text size
/// nobody on this side ever selected.
///
/// So this draws the real views, not mocks of them: same views, same fonts, same
/// `AvatarStack`. A copy would drift from the row within a release and start passing
/// while the row failed.
///
/// Against an in-memory store, like `PartyMergeCheck`. Nothing here can reach the
/// user's trips or books, which is the only acceptable way to run a test that needs
/// to invent forty of them.
@MainActor
enum LayoutStress {

    static var isRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        // `-rowStress` was the name while this covered only the trips list. Kept so
        // an old command line still works.
        return args.contains("-layoutStress") || args.contains("-rowStress")
    }

    /// The widths that actually ship. 320 is the iPhone SE, and it is the one that
    /// breaks first; 402 is the iPhone 17; 440 is the Pro Max.
    private static let widths: [CGFloat] = [320, 402, 440]

    /// Text sizes worth drawing. `.large` is the default, `.xxxLarge` is the top of
    /// the ordinary slider, and `.accessibility3` is deep into the accessibility
    /// range where the app's fonts have roughly doubled.
    private static let sizes: [(name: String, size: DynamicTypeSize)] = [
        ("large", .large), ("xxxLarge", .xxxLarge), ("a11y3", .accessibility3)
    ]

    /// One PNG per screen per width per text size. Split by screen rather than one
    /// tall sheet because a sheet with every row on it is 8000 points high at
    /// `.accessibility3` and unreadable at any zoom that fits it.
    private static let sheets: [(name: String, build: (ModelContext) throws -> AnyView)] = [
        ("trips", { AnyView(try tripSheet(in: $0)) }),
        ("book", { AnyView(try bookSheet(in: $0)) }),
        ("drive", { AnyView(try driveSheet(in: $0)) }),
        ("compare", { AnyView(try compareSheet(in: $0)) })
    ]

    static func run() -> String {
        do {
            var written = 0
            for (sheetName, build) in sheets {
                // A fresh store per sheet: the cases insert dozens of throwaway
                // players, and a sheet that accidentally saw the previous sheet's
                // would be testing something nobody wrote.
                let context = try makeStore()
                let content = try build(context)
                for width in widths {
                    for (sizeName, size) in sizes {
                        let file = "stress-\(sheetName)-\(Int(width))-\(sizeName).png"
                        guard let image = render(content, width: width, size: size,
                                                 caption: "\(sheetName) \u{00B7} width \(Int(width)) \u{00B7} text \(sizeName)")
                        else { return "render failed at \(file)" }
                        guard let data = image.pngData() else { return "encode failed at \(file)" }
                        try data.write(to: FileManager.default
                            .urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent(file))
                        written += 1
                    }
                }
            }
            return "layoutStress wrote \(written) sheets to Documents"
        } catch {
            return "layoutStress failed: \(error)"
        }
    }

    // MARK: - The strings that break things

    /// Long enough to be a real answer from the place picker rather than a row of
    /// Xs. "Rancho Santa Margarita" and the like are what a US map search returns.
    private static let longFrom = "Rancho Santa Margarita, California"
    private static let longTo = "Sault Sainte Marie, Michigan"
    private static let longName = "Thanksgiving at my grandparents in Pennsylvania"
    /// A single unbroken token, which truncation handles differently from a sentence:
    /// there is no space to break at, so a layout that relies on wrapping rather than
    /// on `lineLimit` fails here and nowhere else.
    private static let unbreakable = String(repeating: "Pennsylvania", count: 4)

    private static let partyNames = ["Mia", "Theo", "Dad", "Mom", "Grandma Josephine",
                                     "Al", "Bo", "Cy", "Dee", "Ed", "Flo", "Gus"]

    private static func party(_ count: Int, in context: ModelContext,
                              emoji: Bool = false, longNames: Bool = false) -> [Player] {
        (0..<count).map { index in
            let player = Player(
                name: longNames ? "Great-Aunt Wilhelmina \(index + 1)"
                                : partyNames[index % partyNames.count],
                colorIndex: index)
            if emoji { player.avatar = ["\u{1F680}", "\u{1F984}", "\u{1F415}"][index % 3] }
            context.insert(player)
            return player
        }
    }

    private static func trip(_ name: String, from: String? = nil, to: String? = nil,
                             finished: Bool = false, pinned: Bool = false,
                             in context: ModelContext) -> Trip {
        let trip = Trip(name: name)
        trip.origin = from
        trip.destination = to
        if finished { trip.endedAt = Date() }
        if pinned { trip.pinnedAt = Date() }
        context.insert(trip)
        return trip
    }

    // MARK: - Trips tab

    /// The row in the trips list: name, dates, route, faces, score, edit.
    private static func tripSheet(in context: ModelContext) throws -> some View {
        func row(_ label: String, name: String, from: String?, to: String?,
                 players: Int, current: Bool = false, finished: Bool = false,
                 pinned: Bool = false, emoji: Bool = false) -> Labelled<TripRow> {
            Labelled(label, TripRow(
                trip: trip(name, from: from, to: to, finished: finished,
                           pinned: pinned, in: context),
                isCurrent: current, onSelect: {}, onEdit: {},
                party: party(players, in: context, emoji: emoji)))
        }

        return Sheet {
            row("ordinary", name: "Shore Run", from: "Newark", to: "Asbury Park",
                players: 0)
            row("ordinary, party of 3", name: "Summer Roadtrip",
                from: "Newark", to: "San Diego", players: 3, current: true)
            row("long route, no party", name: "Summer Roadtrip",
                from: longFrom, to: longTo, players: 0)
            row("long route, party of 3", name: "Summer Roadtrip",
                from: longFrom, to: longTo, players: 3)
            row("long route, party of 12", name: "Summer Roadtrip",
                from: longFrom, to: longTo, players: 12)
            row("long name + long route + party", name: longName,
                from: longFrom, to: longTo, players: 12)
            // Every badge at once: playing, party, pinned, and a name with no room
            // left.
            row("every badge, worst case", name: longName,
                from: longFrom, to: longTo, players: 12, current: true, pinned: true)
            row("finished, long, party", name: longName,
                from: longFrom, to: longTo, players: 12, finished: true)
            row("unbreakable name", name: unbreakable,
                from: String(repeating: "Philadelphia", count: 3),
                to: String(repeating: "Pittsburgh", count: 3), players: 4)
            // Emoji faces are wider than initials in most fonts, and the party badge
            // is the one thing here sized off glyphs rather than points.
            row("emoji faces", name: "Summer Roadtrip",
                from: "Newark", to: "San Diego", players: 3, emoji: true)
        }
    }

    // MARK: - Book tab

    /// `ScopeCard`, which carries one more column than the trip row does: the avatar
    /// stack here takes four faces rather than three, so it starves the name sooner.
    private static func bookSheet(in context: ModelContext) throws -> some View {
        func card(_ label: String, kind: LocalizedStringKey = "BOOK", shared: Bool = false,
                  name: String, subtitle: String, people: Int = 0,
                  filling: Bool = false, editable: Bool = true,
                  emoji: Bool = false, longNames: Bool = false)
        -> Labelled<ScopeCard> {
            Labelled(label, ScopeCard(
                kind: kind, isShared: shared, name: name, subtitle: subtitle,
                contributors: party(people, in: context, emoji: emoji,
                                    longNames: longNames),
                isFilling: filling, onSwitch: {},
                onEdit: editable ? {} : nil))
        }

        let since = "Since Aug 15, 2026"
        let longBook = "Every plate the whole family found on the way to Yellowstone"

        return Sheet {
            card("ordinary", name: "Family Book", subtitle: since)
            card("all time", kind: "EVERY PLATE EVER", name: "All time",
                 subtitle: "Across every book and trip", editable: false)
            card("filling now", name: "Family Book",
                 subtitle: "\(since) \u{00B7} filling now", filling: true)
            card("shared, 2 people", kind: "SHARED BOOK", shared: true,
                 name: "Family Book", subtitle: since, people: 2)
            // Four is the stack's limit, so this is the widest it ever gets — the
            // fifth person and the fiftieth cost the same width.
            card("shared, 4 people", kind: "SHARED BOOK", shared: true,
                 name: "Family Book", subtitle: since, people: 4)
            card("shared, 12 people", kind: "SHARED BOOK", shared: true,
                 name: "Family Book", subtitle: since, people: 12)
            card("long name, shared, filling", kind: "SHARED BOOK", shared: true,
                 name: longBook, subtitle: "\(since) \u{00B7} filling now",
                 people: 12, filling: true)
            card("unbreakable name", kind: "SHARED BOOK", shared: true,
                 name: unbreakable, subtitle: "\(since) \u{00B7} filling now",
                 people: 12, filling: true)
            card("emoji faces", kind: "SHARED BOOK", shared: true,
                 name: longBook, subtitle: since, people: 6, emoji: true)
            card("long contributor names", kind: "SHARED BOOK", shared: true,
                 name: longBook, subtitle: since, people: 6, longNames: true)
        }
    }

    // MARK: - Drive tab

    /// The header cards and the standings strip. `TripCard` pins SWITCH opposite a
    /// day counter, and `PlayerStrip` divides the width between up to three people
    /// before it starts scrolling — both are width divided by content, which is the
    /// same bet the rows above make.
    private static func driveSheet(in context: ModelContext) throws -> some View {
        func standings(_ count: Int, longNames: Bool = false)
        -> [(player: Player, score: Int)] {
            party(count, in: context, longNames: longNames).enumerated().map {
                ($0.element, 120 - $0.offset * 7)
            }
        }

        let book = Book(name: "Family Book")
        context.insert(book)
        let longBook = Book(name: "Every plate the whole family found on the way to Yellowstone")
        context.insert(longBook)

        return Sheet {
            Labelled("trip card, ordinary",
                     TripCard(trip: trip("Shore Run", from: "Newark",
                                         to: "Asbury Park", in: context),
                              onSwitch: {}))
            Labelled("trip card, long name + long route",
                     TripCard(trip: trip(longName, from: longFrom, to: longTo,
                                         in: context),
                              onSwitch: {}))
            Labelled("trip card, unbreakable, no switch",
                     TripCard(trip: trip(unbreakable, from: longFrom, to: longTo,
                                         in: context)))
            Labelled("book card, ordinary", BookCard(book: book, onSwitch: {}))
            Labelled("book card, long name", BookCard(book: longBook, onSwitch: {}))
            Labelled("standings, 2", PlayerStrip(standings: standings(2)))
            Labelled("standings, 3", PlayerStrip(standings: standings(3)))
            // Three is the last count that divides the width; four starts scrolling,
            // so this pair is where the strip changes strategy.
            Labelled("standings, 3 long names",
                     PlayerStrip(standings: standings(3, longNames: true)))
            // These two draw as blank boxes on the sheet, and that is the renderer
            // rather than the strip: `ImageRenderer` lays a `ScrollView` out and
            // then does not paint its contents. Past three people the strip scrolls,
            // so this is the one case here that has to be read rather than looked
            // at — and it is the safe one. A scrolling card is a fixed 104pt
            // whatever the party size, and the name inside it is the same
            // `lineLimit(1)` label the three-person cases above do exercise.
            Labelled("standings, 4 long names (scrolls: renderer draws it blank)",
                     PlayerStrip(standings: standings(4, longNames: true)))
            Labelled("standings, 12 (scrolls: renderer draws it blank)",
                     PlayerStrip(standings: standings(12)))
        }
    }

    // MARK: - Compare

    /// `TripSummaryRow`: a name on one side, a two-part score on the other, and a
    /// row of labels under the bar that has no `lineLimit` at all.
    private static func compareSheet(in context: ModelContext) throws -> some View {
        func row(_ label: String, name: String, from: String?, to: String?,
                 current: Bool = false) -> Labelled<TripSummaryRow> {
            let made = trip(name, from: from, to: to, in: context)
            return Labelled(label, TripSummaryRow(summary: TripSummary(trip: made),
                                                  isCurrent: current, best: 50))
        }

        return Sheet {
            row("ordinary", name: "Shore Run", from: "Newark", to: "Asbury Park")
            row("current", name: "Shore Run", from: "Newark", to: "Asbury Park",
                current: true)
            row("long name", name: longName, from: "Newark", to: "San Diego")
            row("long name + long route, current", name: longName,
                from: longFrom, to: longTo, current: true)
            row("unbreakable", name: unbreakable, from: longFrom, to: longTo,
                current: true)
            row("no route", name: longName, from: nil, to: nil)
        }
    }

    // MARK: - Drawing

    /// A case and the name to blame when it breaks. Labelling on the sheet is what
    /// turns "something is wrong on the 440 sheet" into "the shared 12-person card
    /// loses its date".
    private struct Labelled<Content: View>: View {
        let label: String
        let content: Content

        init(_ label: String, _ content: Content) {
            self.label = label
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                content
            }
        }
    }

    private struct Sheet<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) { content }
        }
    }

    private static func render(_ content: AnyView, width: CGFloat,
                               size: DynamicTypeSize, caption: String) -> UIImage? {
        let sheet = VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
            content
        }
        // The same padding the screens give their rows, so the width a row is handed
        // here is the width it gets on the phone.
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
        .frame(width: width)
        .background(Theme.ground)
        .environment(\.dynamicTypeSize, size)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        return renderer.uiImage
    }

    private static func makeStore() throws -> ModelContext {
        let schema = Schema([Trip.self, Book.self, Player.self, Sighting.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}

#endif
