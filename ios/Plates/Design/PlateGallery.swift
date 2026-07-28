#if DEBUG
import SwiftUI

/// Contrast audit. Legibility of ink-on-plate is the one thing about this
/// catalogue that can be checked by machine rather than by eye, so it is —
/// 65 tiles is far too many to squint at individually.
enum ContrastAudit {

    /// WCAG relative luminance.
    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = channel((hex >> 16) & 0xFF)
        let g = channel((hex >> 8) & 0xFF)
        let b = channel(hex & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let l1 = luminance(a), l2 = luminance(b)
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// 4.5:1 is the WCAG AA threshold for normal text. The plate code is large
    /// and bold so it would pass at 3:1, but the state name underneath is tiny —
    /// hold the whole tile to the stricter number.
    static let threshold = 4.5

    /// Worst case across the gradient — the ink has to hold up at both ends.
    static func check(_ style: PlateStyle) -> Double {
        min(ratio(style.bgHex, style.inkHex),
            ratio(style.bgHex2, style.inkHex))
    }

    /// Every plate that fails, worst first.
    static func failures() -> [(code: String, ratio: Double)] {
        Plate.all.compactMap { plate in
            guard let s = PlateStyle.style(for: plate.code) else { return nil }
            let r = check(s)
            return r < threshold ? (plate.code, r) : nil
        }
        .sorted { $0.ratio < $1.ratio }
    }
}

/// Launch with `-gallery` to see the whole catalogue on one screen. Contrast
/// failures get a red ring and their ratio printed, so a single screenshot
/// audits all 65 rather than scrolling the game screen and guessing.
struct PlateGallery: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        let failures = Dictionary(uniqueKeysWithValues:
            ContrastAudit.failures().map { ($0.code, $0.ratio) })

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(failures: failures)
                group("States", Plate.states, failures)
                group("Bonus", Plate.bonus, failures)
                group("Canada", Plate.provinces, failures)
            }
            .padding(12)
        }
        .background(Theme.ground)
    }

    private func header(failures: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Plate catalogue")
                .font(.system(size: 20, weight: .bold))
            Text(summary(failures: failures))
                .font(.system(size: 12))
                .foregroundStyle(failures.isEmpty ? Theme.inkMuted : Color.red)
        }
    }

    private func summary(failures: [String: Double]) -> String {
        let styled = "\(PlateStyle.catalog.count) of \(Plate.all.count) styled"
        let contrast = failures.isEmpty
            ? "contrast: all pass"
            : "contrast: \(failures.count) below "
              + String(format: "%.1f", ContrastAudit.threshold) + ":1"
        return styled + "  \u{00B7}  " + contrast
    }

    private func group(_ title: String, _ plates: [Plate],
                       _ failures: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkMuted)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(plates) { plate in
                    VStack(spacing: 2) {
                        PlateTile(plate: plate, isFound: true)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.tileRadius,
                                                 style: .continuous)
                                    .strokeBorder(Color.red,
                                                  lineWidth: failures[plate.code] != nil ? 2 : 0)
                            )
                        if let r = failures[plate.code] {
                            Text(String(format: "%.1f", r))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}
#endif
