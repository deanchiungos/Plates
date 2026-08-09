import SwiftUI
import UIKit

/// The system share sheet, for the one case `ShareLink` cannot cover.
///
/// `ShareLink` wants its payload up front, and the payload here is a 1400×2125
/// image that takes real work to draw. Building it during `body` would render a
/// poster every time the sheet redrew, for a button most people will never press.
/// A plain `Button` that renders on tap and then presents this costs nothing until
/// it is used.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A rendered poster waiting to be shared. Identifiable so `.sheet(item:)` can
/// present it, since the image itself is not.
struct PosterToShare: Identifiable {
    let id = UUID()
    let image: UIImage
}
