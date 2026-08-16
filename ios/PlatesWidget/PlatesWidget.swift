import SwiftUI
import WidgetKit

/// What the home screen shows, and the one tap back into the app.
///
/// Reads only the sidecar the app writes — never the store. A widget cannot open a
/// CloudKit-backed SwiftData container safely from another process, and it does not
/// need to: everything here is a number the app already worked out. See `WidgetData`.
@main
struct PlatesWidgetBundle: WidgetBundle {
    var body: some Widget { ProgressWidget() }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlatesProgress", provider: Provider()) { entry in
            ProgressWidgetView(snapshot: entry.snapshot)
                .containerBackground(WidgetPalette.ground, for: .widget)
        }
        .configurationDisplayName("Collection")
        // "Whatever you are filling" is how the code talks about a trip-or-book.
        // On the widget gallery card it just sounds vague.
        .description("Your progress on the trip or book you are collecting into.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One entry, never expiring on its own.
///
/// Deliberately no refresh schedule. Nothing here changes with the clock — it
/// changes when somebody logs a plate, and the app calls `reloadAllTimelines` at
/// exactly that moment. A widget that reloads hourly is spending battery to
/// re-read a file that has not moved.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        // `.sample` only for the gallery. WidgetKit also asks for non-preview
        // snapshots, and answering those with the fabricated trip put "Summer
        // Roadtrip, 21 of 50" on the home screen of somebody who had never taken it
        // — then flipped to 0 of 50 the moment `getTimeline` ran, because that one
        // already fell back to an empty snapshot. The two have to agree, and empty
        // is the honest half.
        completion(Entry(date: Date(),
                         snapshot: context.isPreview ? .sample
                                                     : (WidgetSnapshot.read() ?? WidgetSnapshot())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: WidgetSnapshot.read() ?? WidgetSnapshot())
        // Refreshed at the next midnight rather than never.
        //
        // `.never` was paired with a caption computed from `Date()` at render time,
        // and the only thing that could ask for a new timeline was the app writing a
        // changed snapshot — which happens because a plate was just logged, which
        // sets the clock this caption measures back to zero. So "6 days quiet" could
        // not render: the widget was only ever redrawn on the one day it had nothing
        // to say. A day boundary is the granularity the line is written in, so that
        // is what it waits for.
        let tomorrow = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

// MARK: - The face of it

struct ProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        // One tap into the app, which was the second must-have. The app opens on the
        // Game tab, so this lands on the grid the plate gets tapped into.
        .widgetURL(URL(string: "plates://collect"))
    }

    // MARK: Small

    /// Numbers only, because there is no room for anything else that would still be
    /// legible. The rarest find earns its line here over a second count: two totals
    /// side by side is what every other app's widget looks like.
    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            label(kindLabel)
            title(name)
            count(snapshot.states)
            bar(snapshot.states)
            Spacer(minLength: 0)
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    /// The album, not a second progress bar.
    ///
    /// A medium widget with the same four lines as the small one, spread wider, is
    /// what "a little bare" means — it uses the extra room for whitespace rather than
    /// for anything to look at. The grid of codes is the shape of the whole app: you
    /// can see at a glance which corner of the country is still missing, which is the
    /// thing a number can never tell you.
    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                label(kindLabel)
                title(name)
                count(snapshot.states)
                bar(snapshot.states)
                Spacer(minLength: 0)
                detail
            }
            .frame(width: 118, alignment: .topLeading)

            CodeGrid(found: Set(snapshot.foundCodes))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Parts

    private var kindLabel: LocalizedStringKey {
        switch snapshot.headline {
        case .active(_, _, _, let kind): return kind == "book" ? "BOOK" : "ON THE ROAD"
        case .recent: return "LAST TRIP"
        case .lifetime: return "ALL TIME"
        }
    }

    /// Verbatim on purpose where it is a trip or book name — that is the person's
    /// own words and has no business being looked up in a catalog — and a key for
    /// the one case where the app is doing the naming.
    private var name: Text {
        switch snapshot.headline {
        case .active(let name, _, _, _), .recent(let name, _): return Text(verbatim: name)
        case .lifetime: return Text("Your collection")
        }
    }

    /// The line under the bar. A trip that has gone quiet says so, because that is
    /// the one thing on this widget that is asking for something back.
    @ViewBuilder
    private var detail: some View {
        switch snapshot.headline {
        case .active(_, _, let lastPlate, _):
            if let lastPlate, days(since: lastPlate) > 0 {
                // `^[…](inflect: true)` rather than splicing an "s" on by hand. The
                // hand-rolled form is untranslatable — Slavic and Arabic plurals need
                // three to six forms — and it produced no catalog entry at all.
                caption("^[\(days(since: lastPlate)) day](inflect: true) quiet")
            } else if let best = snapshot.bestCode {
                rarest(best)
            } else {
                caption("Nothing spotted yet")
            }
        case .recent:
            if let best = snapshot.bestCode { rarest(best) }
        case .lifetime(_, let plates):
            caption("^[\(plates) plate](inflect: true) in all")
        }
    }

    private func rarest(_ code: String) -> some View {
        HStack(spacing: 4) {
            Text(code)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetPalette.rarity(snapshot.bestIsRemarkable))
            Text("rarest")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.inkMuted)
        }
    }

    /// `LocalizedStringKey`, not `String`. Taking a `String` bound every one of
    /// these to `Text(some StringProtocol)` — the verbatim initializer — so nothing
    /// routed through these three helpers was ever harvested for translation, while
    /// the literals written inline a few lines up were. One widget, two languages.
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(WidgetPalette.inkMuted)
            .lineLimit(1)
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(WidgetPalette.inkMuted)
    }

    private func title(_ text: Text) -> some View {
        text
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WidgetPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func count(_ states: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(states)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.ink)
            Text("of \(WidgetSnapshot.stateTotal)")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.inkMuted)
        }
    }

    private func bar(_ states: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.line)
                Capsule()
                    .fill(WidgetPalette.route)
                    .frame(width: max(4, geo.size.width
                                      * CGFloat(states) / CGFloat(WidgetSnapshot.stateTotal)))
            }
        }
        .frame(height: 6)
    }

    private func days(since last: Date) -> Int {
        Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }
}

/// Fifty states as fifty marks.
///
/// Codes rather than plate art: the artwork lives in the app's asset catalogue and
/// the extension has its own bundle, so drawing real plates here would mean shipping
/// a second copy of every image to render them at four millimetres across. The code
/// is what the app's empty slots show anyway.
private struct CodeGrid: View {
    let found: Set<String>

    /// The same order the app's grid uses, so the shape somebody recognises from the
    /// Books tab is the shape on their home screen.
    private static let codes = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { column in
                        let code = Self.codes[row * 10 + column]
                        Text(code)
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(found.contains(code)
                                             ? WidgetPalette.ground : WidgetPalette.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: 13)
                            .background(
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(found.contains(code)
                                          ? WidgetPalette.route : WidgetPalette.line)
                            )
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// The app's palette, by value.
///
/// Mirrored rather than shared for the same reason `WidgetSnapshot` is: a whole
/// framework target to carry a handful of colors across is a worse trade than a
/// handful of literals. They are the same hexes as `Theme` — if those ever move,
/// these follow.
enum WidgetPalette {
    static let ground = Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xEF / 255)
    static let ink = Color(red: 0x1B / 255, green: 0x22 / 255, blue: 0x31 / 255)
    static let inkMuted = Color(red: 0x8A / 255, green: 0x83 / 255, blue: 0x77 / 255)
    static let route = Color(red: 0x12 / 255, green: 0x39 / 255, blue: 0x5E / 255)
    static let line = Color(red: 0xE7 / 255, green: 0xE1 / 255, blue: 0xD1 / 255)
    static let paint = Color(red: 0xF0 / 255, green: 0xB4 / 255, blue: 0x29 / 255)

    /// Only the top of the scale gets a color. `RarityTier` has five bands and the
    /// widget has room for one distinction: worth remarking on, or not.
    /// Takes the app's verdict rather than re-deriving one. `value >= 8` was a cut
    /// that matched no band in `RarityTier` — epic is 7...8 — so the home screen
    /// disagreed with the grid it links to, and mythic was painted as an epic.
    static func rarity(_ isRemarkable: Bool) -> Color { isRemarkable ? paint : ink }
}
