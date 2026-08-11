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
        .configurationDisplayName("Trip progress")
        .description("How far along the trip you are filling is.")
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
        completion(Entry(date: Date(),
                         snapshot: context.isPreview ? .sample : (WidgetSnapshot.read() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: WidgetSnapshot.read() ?? WidgetSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - The face of it

struct ProgressWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch snapshot.headline {
            case .active(let name, let states, let lastPlate):
                label("ON THE ROAD")
                title(name)
                count(states)
                bar(states)
                if let lastPlate { footnote(since: lastPlate) }

            case .recent(let name, let states):
                label("LAST TRIP")
                title(name)
                count(states)
                bar(states)

            case .lifetime(let states, let plates):
                label("ALL TIME")
                title("Your collection")
                count(states)
                bar(states)
                Text("\(plates) plates in all")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // One tap into the app, which was the second must-have. The app opens on the
        // Game tab, so this lands on the grid the plate gets tapped into.
        .widgetURL(URL(string: "plates://collect"))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(WidgetPalette.inkMuted)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WidgetPalette.ink)
            .lineLimit(1)
    }

    private func count(_ states: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(states)")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
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

    /// "2 days quiet" rather than a date. The number that matters is how long it has
    /// been, and a widget has no room to make anybody work that out.
    private func footnote(since last: Date) -> some View {
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return Text(days <= 0 ? "Spotted today"
                              : "\(days) day\(days == 1 ? "" : "s") quiet")
            .font(.system(size: 11))
            .foregroundStyle(WidgetPalette.inkMuted)
    }
}

/// The app's palette, by value.
///
/// Mirrored rather than shared for the same reason `WidgetSnapshot` is: a whole
/// framework target to carry five colours across is a worse trade than five
/// literals. They are the same hexes as `Theme` — if those ever move, these follow.
enum WidgetPalette {
    static let ground = Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xEF / 255)
    static let ink = Color(red: 0x1B / 255, green: 0x22 / 255, blue: 0x31 / 255)
    static let inkMuted = Color(red: 0x8A / 255, green: 0x83 / 255, blue: 0x77 / 255)
    static let route = Color(red: 0x12 / 255, green: 0x39 / 255, blue: 0x5E / 255)
    static let line = Color(red: 0xE7 / 255, green: 0xE1 / 255, blue: 0xD1 / 255)
}
