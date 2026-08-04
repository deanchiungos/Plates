import SwiftUI

/// How loudly a find is celebrated.
///
/// Bands of the 1...10 rarity scale rather than a continuous curve, because the
/// reward has to be legible: a kid should learn after two or three finds that gold
/// letters mean something genuinely unusual just went past the window. Five tiers
/// is the most that stays distinguishable at a glance.
///
/// The bands are read off the *geographic* rarity, so the same plate escalates
/// differently depending on the trip. A New Jersey plate is silent in Newark and a
/// banner in Sacramento, which is the entire point.
enum RarityTier: Int, Comparable {
    case common      // 1-2
    case uncommon    // 3-4
    case rare        // 5-6
    case epic        // 7-8
    case legendary   // 9-10

    static func < (a: RarityTier, b: RarityTier) -> Bool { a.rawValue < b.rawValue }

    static func forRarity(_ rarity: Int) -> RarityTier {
        switch rarity {
        case ...2:  return .common
        case 3...4: return .uncommon
        case 5...6: return .rare
        case 7...8: return .epic
        default:    return .legendary
        }
    }

    /// Every tier is named, including the dull ones. Naming only the top three hid
    /// the scale that gives them meaning — "RARE" lands harder when you have seen
    /// "COMMON" and "UNCOMMON" go past and know where it sits on the ramp. What
    /// escalates is the size and the colour, not whether the word appears at all.
    var label: String {
        switch self {
        case .common:    return "COMMON"
        case .uncommon:  return "UNCOMMON"
        case .rare:      return "RARE"
        case .epic:      return "EPIC"
        case .legendary: return "LEGENDARY"
        }
    }

    /// Grey to navy to blue to violet to gold — a ramp that reads as escalating even
    /// if you never learn which word means what.
    var color: Color {
        switch self {
        case .common:    return Theme.inkMuted
        // Green rather than the route navy it used to be. Navy is the app's accent —
        // it is on every button and every selected thing — so as a rarity it read as
        // "this control is active" rather than as a step on a scale. Green also puts
        // the ramp on the grey/green/blue/violet/gold ladder that every collecting
        // game already uses, which is a convention worth having for free.
        case .uncommon:  return Color(hex: 0x2E9E52)
        case .rare:      return Color(hex: 0x2F8FE0)
        case .epic:      return Color(hex: 0xA45BE8)
        case .legendary: return Color(hex: 0xF0B429)
        }
    }

    /// The lit face of the tier — its own colour with the light on it.
    ///
    /// Only ever the near side of a gradient, never a fill in its own right. A disc
    /// of flat colour seven points across reads as a printed sticker at any
    /// saturation; the same disc with a highlight off one shoulder reads as a bead,
    /// and that is the whole difference between a mark you scan past and one you look
    /// at.
    var highlight: Color {
        switch self {
        case .common:    return Color(hex: 0xB9C3D2)
        case .uncommon:  return Color(hex: 0x74D294)
        case .rare:      return Color(hex: 0x9AD2F8)
        case .epic:      return Color(hex: 0xD8B8FB)
        case .legendary: return Color(hex: 0xFFE9A8)
        }
    }

    /// How far the tier's colour bleeds past the edge of its dot.
    ///
    /// Steeply weighted rather than evenly spaced, because a grid where every dot
    /// glows is a grid where none of them does. Common gets nothing at all — a plate
    /// that was wallpaper where you caught it should not be lit up about it — and
    /// legendary gets enough to find from across the screen without reading its
    /// colour.
    var glowRadius: CGFloat {
        switch self {
        case .common:    return 0
        case .uncommon:  return 2
        case .rare:      return 3.5
        case .epic:      return 5
        case .legendary: return 7
        }
    }

    /// How big the tier word is on the find card.
    var titleSize: CGFloat {
        switch self {
        case .common:    return 34
        case .uncommon:  return 42
        case .rare:      return 52
        case .epic:      return 60
        case .legendary: return 68
        }
    }

    /// Fill colour for the map, which needs a different ramp from the pips.
    ///
    /// `color` is tuned to read at four points on a white tile, and there the dark
    /// route blue of "uncommon" is simply a dot. Filling whole states with it made
    /// uncommon look *heavier* than rare, so the ramp ran backwards. These go pale
    /// to saturated instead, which is the only ordering a filled choropleth can
    /// actually convey.
    var mapFill: Color {
        switch self {
        case .common:    return Color(hex: 0xE7EBF1)
        // Follows `color` onto green, so the map and the grid do not disagree about
        // what uncommon looks like.
        case .uncommon:  return Color(hex: 0xBFE3CB)
        case .rare:      return Color(hex: 0x86BCEC)
        case .epic:      return Color(hex: 0xC79BF0)
        case .legendary: return Color(hex: 0xF5C651)
        }
    }

    /// Confetti scales with the tier — a common plate gets a puff, a legendary one
    /// gets thrown across the screen.
    var confettiCount: Int {
        switch self {
        case .common:    return 8
        case .uncommon:  return 12
        case .rare:      return 18
        case .epic:      return 26
        case .legendary: return 40
        }
    }

    var confettiReach: ClosedRange<CGFloat> {
        switch self {
        case .common:    return 40...70
        case .uncommon:  return 52...96
        case .rare:      return 62...130
        case .epic:      return 74...170
        case .legendary: return 90...240
        }
    }

    /// Only the top tier gets the full-screen wash. Used sparingly it lands; used
    /// on every find it would be exhausting.
    var flashesScreen: Bool { self == .legendary }

    @MainActor
    func playHaptic() {
        switch self {
        case .common:    Haptics.repeatSighting()
        case .uncommon:  Haptics.found()
        case .rare:      Haptics.found()
        case .epic, .legendary: Haptics.milestone()
        }
    }
}

/// The card that flashes over the grid when a plate is found.
///
/// Shown on every *first* find, not just rare ones, because the fun fact is the
/// reward as much as the confetti is — and a fact you only ever see for Nunavut is
/// a fact nobody sees. What escalates is the volume: the tier word grows and
/// changes colour as the plate gets rarer, and a legendary one is big enough to
/// read from the back seat.
///
/// Deliberately not a popup: it must not need dismissing, must not block the next
/// tap, and must not interrupt a car full of people still looking out the window.
struct FindBanner: View {
    let tier: RarityTier
    let plateName: String
    let fact: String?

    /// How long the card stays up before the screen clears it.
    ///
    /// Scaled to the length of the fact rather than fixed, because these run from a
    /// short clause to a full sentence and a timer tuned for the short ones cuts the
    /// long ones off mid-read. Read aloud in a moving car is slower than read on a
    /// desk, so the allowance is generous; impatience is handled by letting you tap
    /// it away, not by ripping it off the screen early.
    static func dwell(fact: String?) -> Double {
        guard let fact else { return 2.2 }
        return min(13, 4.0 + Double(fact.count) / 14.0)
    }

    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            Text(tier.label)
                .font(Theme.PlateFont.condensed(tier.titleSize))
                .tracking(tier == .legendary ? 3.5 : 2.5)
                .foregroundStyle(tier.color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: tier.color.opacity(0.55), radius: 16)
                .padding(.bottom, 2)

            Text(plateName.uppercased())
                .font(.plates(size: 19, weight: .bold))
                .tracking(2.4)
                .foregroundStyle(Theme.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            if let fact {
                Text(fact)
                    .font(.plates(size: 17))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Text("tap to dismiss")
                .font(.plates(size: 11))
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
                .padding(.top, 8)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: tier.color.opacity(tier >= .rare ? 0.38 : 0), radius: 26, y: 8)
                .shadow(color: Theme.ink.opacity(0.18), radius: 10, y: 5)
        )
        .scaleEffect(shown ? 1 : 0.62)
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.label) find. \(plateName). \(fact ?? "")")
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) { shown = true }
        }
    }
}

/// A single wash of tier colour over the whole screen. Legendary only.
struct RarityFlash: View {
    let tier: RarityTier
    @State private var on = false

    var body: some View {
        RadialGradient(
            colors: [tier.color.opacity(0.34), tier.color.opacity(0)],
            center: .center, startRadius: 10, endRadius: 460
        )
        .ignoresSafeArea()
        .opacity(on ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { on = true }
            withAnimation(.easeIn(duration: 0.55).delay(0.2)) { on = false }
        }
    }
}
