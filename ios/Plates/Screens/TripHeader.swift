import SwiftUI

/// The road rail: a filled route-blue bed, a dashed road-paint centre line, and a
/// mile-marker pin that travels with progress.
struct RoadRail: View {
    /// How much of the map is collected. Drives the fill and the mile-marker pin.
    let progress: Double

    /// How far along the actual drive you are, 0...1. Nil when the trip has no
    /// destination pinned or no location fix, in which case no car is drawn.
    ///
    /// Deliberately a second, separate marker rather than a replacement for the pin.
    /// They answer different questions — the pin is how much of the *map* you have
    /// filled, the car is how much of the *road* you have covered — and on a good
    /// trip they are nowhere near each other.
    var journey: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                    .frame(height: 10)

                Capsule().fill(Theme.route)
                    .frame(width: max(10, w * clamped), height: 10)

                // dashed centre line
                Path { p in
                    p.move(to: CGPoint(x: 8, y: 5))
                    p.addLine(to: CGPoint(x: w - 8, y: 5))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [9, 9]))
                .foregroundStyle(Theme.paint)
                .frame(height: 10)

                Circle()
                    .fill(Theme.paint)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 3, y: 2)
                    .offset(x: (w * clamped) - 10)

                if let journey {
                    let at = min(max(journey, 0), 1)
                    // Riding on top of the rail rather than centred on it, so it
                    // reads as a car on a road instead of a second bead on a string.
                    // `car.side.fill`, not `car.fill`. The plain one is a car seen
                    // head-on from the front, so it has no direction at all and
                    // mirroring it does precisely nothing. This one is a profile,
                    // drawn facing left, so the flip actually turns it to face the
                    // way the rail runs.
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .scaleEffect(x: -1, y: 1)
                        .foregroundStyle(Theme.route)
                        .shadow(color: .white, radius: 2)
                        .shadow(color: .white, radius: 2)
                        .offset(x: (w - 22) * at, y: -11)
                }
            }
            .frame(height: geo.size.height, alignment: .center)
        }
        .frame(height: 30)
        .animation(.snappy(duration: 0.32), value: progress)
        .animation(.snappy(duration: 0.6), value: journey)
        .accessibilityHidden(true)
    }
}

struct TripCard: View {
    let trip: Trip
    /// Tapping the card switches trips. Nil leaves it inert.
    var onSwitch: (() -> Void)?

    var body: some View {
        Button { onSwitch?() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(trip.isActive ? "ACTIVE" : "FINISHED") TRIP \u{00B7} DAY \(trip.dayNumber)")
                        .font(.plates(size: 10.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if onSwitch != nil {
                        Text("SWITCH")
                            .font(.plates(size: 10, weight: .bold))
                            .tracking(0.9)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(onSwitch != nil ? Theme.route : Theme.inkMuted)

                Text(trip.name)
                    .font(.plates(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.top, 2)

                // The route, when there is one, earns the line that would
                // otherwise state the scoring mode — where you are going is the
                // more interesting fact, and the mode still shows in the editor.
                Text(trip.routeLabel ?? trip.scoringMode.label)
                    .font(.plates(size: 12.5))
                    .foregroundStyle(trip.routeLabel == nil ? Theme.inkMuted : Theme.route.opacity(0.85))
                    .lineLimit(1)
                    .padding(.top, 1)

                RoadRail(progress: trip.progress, journey: trip.journeyProgress)
                    .padding(.top, 14)

                HStack {
                    // The distance takes this slot when there is one: while you are
                    // actually driving it is the more useful of the two, and the
                    // scoring mode has not changed since you set it.
                    Text(trip.remainingLabel ?? (trip.routeLabel == nil ? "Start" : trip.scoringMode.label))
                        .foregroundStyle(trip.remainingLabel == nil ? Theme.inkMuted : Theme.route)
                    Spacer()
                    Text("\(trip.statesFound) of \(Plate.stateTotal)")
                        .monospacedDigit()
                }
                .font(.plates(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: Theme.ink.opacity(0.10), radius: 9, y: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSwitch == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(onSwitch != nil ? "Switch to another trip" : "")
    }
}

/// The book's turn at the top of the Drive screen.
///
/// Deliberately the same shape and the same rail as `TripCard` — the grid below it
/// behaves identically either way, so a different-looking header would imply a
/// difference that isn't there. What changes is the framing: no day counter, no
/// route, no finish line. A book is open-ended, and the card says so.
struct BookCard: View {
    let book: Book
    /// Tapping the card switches what you are filling. Nil leaves it inert.
    var onSwitch: (() -> Void)?

    var body: some View {
        Button { onSwitch?() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("PLATE BOOK")
                        .font(.plates(size: 10.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if onSwitch != nil {
                        Text("SWITCH")
                            .font(.plates(size: 10, weight: .bold))
                            .tracking(0.9)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .foregroundStyle(onSwitch != nil ? Theme.route : Theme.inkMuted)

                Text(book.name)
                    .font(.plates(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(book.sinceLabel)
                    .font(.plates(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                    .padding(.top, 1)

                RoadRail(progress: book.progress)
                    .padding(.top, 14)

                HStack {
                    Text("Collecting")
                    Spacer()
                    Text("\(book.statesFound) of \(Plate.stateTotal)")
                        .monospacedDigit()
                }
                .font(.plates(size: 11))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
                    .shadow(color: Theme.ink.opacity(0.10), radius: 9, y: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSwitch == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(onSwitch != nil ? "Switch to a trip or another book" : "")
    }
}

/// Compact standings, sitting between the trip card and the grid. Hidden entirely
/// when only one person is playing — solo play should not pay for multiplayer chrome.
///
/// It used to split the width evenly between however many people were playing,
/// which meant every extra person made everybody's card narrower: at six the names
/// were down to a few letters, and past that they were unreadable. Dividing a fixed
/// width by an unbounded number is the wrong shape for this. Cards keep a size that
/// fits a name and the row scrolls instead, so the seventh person costs the first
/// six nothing.
///
/// Up to three still stretch to fill the width, because three cards floating at the
/// left of an empty row looks like something failed to load. The switch happens at
/// the point where filling the width would start to squeeze.
struct PlayerStrip: View {
    let standings: [(player: Player, score: Int)]

    /// Wide enough for a real name at 11pt without truncating.
    private let cardWidth: CGFloat = 104

    /// Past this, stop dividing the width and start scrolling.
    private var scrolls: Bool { standings.count > 3 }

    var body: some View {
        Group {
            if scrolls {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) { cards }
                        // The cards sit inside the scroll view, so the screen's own
                        // padding has to be re-applied here or the first and last
                        // ones start and end flush against the bezel.
                        .padding(.horizontal, Theme.screenPadding)
                }
                .scrollIndicators(.hidden)
                // Let the row bleed to both edges, so a card scrolling off does it
                // at the screen edge rather than at an invisible inset.
                .padding(.horizontal, -Theme.screenPadding)
            } else {
                HStack(spacing: 7) { cards }
            }
        }
    }

    private var cards: some View {
        ForEach(Array(standings.enumerated()), id: \.element.player.id) { index, entry in
            let color = Theme.playerColor(entry.player.colorIndex)
            let isLeader = index == 0 && entry.score > 0

            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Text(entry.player.initial)
                                .font(Theme.PlateFont.condensed(10))
                                .foregroundStyle(Theme.ink)
                        )
                    Text(entry.player.name)
                        .font(.plates(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Text("\(entry.score)")
                    .font(Theme.PlateFont.condensed(19))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 6)
            .frame(width: scrolls ? cardWidth : nil)
            .frame(maxWidth: scrolls ? nil : .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(isLeader ? color : Theme.line,
                                          lineWidth: isLeader ? 1.5 : 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.player.name), \(entry.score) points\(isLeader ? ", leading" : "")")
        }
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.plates(size: 16, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(.plates(size: 13))
                .monospacedDigit()
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Says why the car is not on the rail yet, and offers the one action that fixes it.
///
/// Four different things stop the car appearing and they used to be indistinguishable
/// — an empty rail either way. Naming which one is missing turns "this feature is
/// broken" into "oh, I need to pin a destination".
///
/// The permission case doubles as the pre-prompt. The system dialog is a one-shot:
/// whatever is answered first is the answer more or less forever, so raising it
/// unannounced spends that chance at the exact moment nobody knows what it is for.
struct TrackingHintCard: View {
    enum State {
        case needsPermission
        case denied
        case needsDestination
        case locating
    }

    let state: State
    /// A book has no route and no car on a rail, so the same permission has to be
    /// asked for in different words: what it buys there is rarity, and nothing else.
    var isBook: Bool = false
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(state == .denied ? Theme.inkMuted : Theme.route)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.plates(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.plates(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if state == .needsPermission {
                Button(action: onAllow) {
                    Text("Allow")
                        .font(.plates(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.route))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.route.opacity(state == .denied ? 0.12 : 0.25), lineWidth: 1))
        )
    }

    private var symbol: String {
        switch state {
        case .needsPermission: return "location.circle.fill"
        case .denied:          return "location.slash"
        case .needsDestination:return "mappin.and.ellipse"
        case .locating:        return "location.magnifyingglass"
        }
    }

    private var title: String {
        switch state {
        case .needsPermission: return isBook ? "Score by where you are?" : "Follow the drive?"
        case .denied:          return "Location is off"
        case .needsDestination:return "Where are you heading?"
        case .locating:        return "Finding you\u{2026}"
        }
    }

    private var detail: String {
        switch state {
        case .needsPermission:
            return isBook
                ? "Makes plates from far away worth more, wherever you happen to open the book. Only while the app is open."
                : "Moves the car along your route and makes plates from far away worth more. Only while the app is open."
        case .denied:
            return isBook
                ? "Turn it on for Plates in Settings and rarity follows you instead of using national averages."
                : "Turn it on for Plates in Settings to see the car and have rarity follow you."
        case .needsDestination:
            return "Pin a destination on this trip and the rail will show how far is left."
        case .locating:
            return isBook
                ? "Rarity re-ranks as soon as your first location comes in."
                : "The car appears as soon as your first location comes in."
        }
    }
}
