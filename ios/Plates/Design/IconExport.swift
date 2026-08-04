#if DEBUG
import SwiftUI
import UIKit

/// Renders the app icon to PNG at every size the asset catalogue asks for.
///
/// Run with `-exportIcons`; the files land in the app's Documents directory and are
/// copied into `Assets.xcassets` from there. Doing it inside the app rather than in
/// a design tool means the icon is rendered by the same SwiftUI and the same DIN
/// Condensed as the plate tiles, so it cannot drift.
enum IconExport {

    /// Every slot in an iOS app icon set. `points` decides which of the two drawings
    /// is used; `points x scale` decides the pixel size.
    struct Slot {
        let idiom: String
        let points: Double
        let scale: Int

        var pixels: Int { Int((points * Double(scale)).rounded()) }
        /// Large and small art collide at 120 px (iPhone 40pt@3x vs 60pt@2x), so the
        /// filename has to carry the drawing as well as the size.
        var filename: String { "icon_\(pixels)_\(points >= 60 ? "lg" : "sm").png" }
    }

    static let slots: [Slot] = [
        .init(idiom: "iphone", points: 20,   scale: 2),
        .init(idiom: "iphone", points: 20,   scale: 3),
        .init(idiom: "iphone", points: 29,   scale: 2),
        .init(idiom: "iphone", points: 29,   scale: 3),
        .init(idiom: "iphone", points: 40,   scale: 2),
        .init(idiom: "iphone", points: 40,   scale: 3),
        .init(idiom: "iphone", points: 60,   scale: 2),
        .init(idiom: "iphone", points: 60,   scale: 3),
        .init(idiom: "ipad",   points: 20,   scale: 1),
        .init(idiom: "ipad",   points: 20,   scale: 2),
        .init(idiom: "ipad",   points: 29,   scale: 1),
        .init(idiom: "ipad",   points: 29,   scale: 2),
        .init(idiom: "ipad",   points: 40,   scale: 1),
        .init(idiom: "ipad",   points: 40,   scale: 2),
        .init(idiom: "ipad",   points: 76,   scale: 1),
        .init(idiom: "ipad",   points: 76,   scale: 2),
        .init(idiom: "ipad",   points: 83.5, scale: 2),
        .init(idiom: "ios-marketing", points: 1024, scale: 1)
    ]

    @MainActor
    static func run() -> [String] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var written: Set<String> = []
        var log: [String] = []

        for slot in slots where !written.contains(slot.filename) {
            written.insert(slot.filename)
            let px = CGFloat(slot.pixels)

            // Square and unrounded: iOS applies the squircle mask itself, and an
            // icon that arrives pre-rounded gets rounded twice.
            let art = AppIconArt.preset(forPointSize: slot.points, size: px, rounded: false)

            let renderer = ImageRenderer(content: art)
            renderer.scale = 1     // content is already in pixels
            guard let image = renderer.uiImage else {
                log.append("FAILED \(slot.filename)")
                continue
            }

            guard let data = opaquePNG(from: image, side: px) else {
                log.append("FAILED encode \(slot.filename)")
                continue
            }
            try? data.write(to: dir.appendingPathComponent(slot.filename))
            log.append("\(slot.filename)  \(data.count / 1024) KB")
        }

        log.append("DIR \(dir.path)")
        return log
    }

    /// Re-encodes without an alpha channel.
    ///
    /// An opaque `UIGraphicsImageRenderer` is not enough — `pngData()` writes RGBA
    /// whatever the context was, and the App Store rejects an app icon carrying
    /// transparency (ITMS-90717). Drawing through a `noneSkipLast` bitmap is what
    /// actually produces a 24-bit PNG.
    @MainActor
    private static func opaquePNG(from image: UIImage, side: CGFloat) -> Data? {
        guard let source = image.cgImage,
              let context = CGContext(
                data: nil,
                width: Int(side), height: Int(side),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        // No flip. `CGContext.draw` orients a CGImage correctly on its own here —
        // adding the usual translate/scale correction mirrored the wordmark.
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let flattened = context.makeImage() else { return nil }
        return UIImage(cgImage: flattened).pngData()
    }
}

/// A plain readout, so a screenshot confirms the export ran and what it produced.
struct IconExportView: View {
    @State private var log: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(log, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Theme.ground)
        .onAppear { log = IconExport.run() }
    }
}
#endif
