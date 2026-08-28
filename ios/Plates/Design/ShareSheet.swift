import LinkPresentation
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
    /// The line that travels with the picture. See `ShareInvite`.
    var caption: String?

    /// What actually goes into the share sheet.
    ///
    /// Two items, not one. `UIActivityViewController` hands every item to whichever
    /// app is picked, and the ones that take both — Messages, Mail, Notes — put the
    /// text beside the picture, where the link is tappable. The ones that only want
    /// a picture, like Instagram, ignore the string and are no worse off than before.
    ///
    /// The image goes in wrapped. A lone `UIImage` gets a thumbnail in the sheet's
    /// header for free; a `UIImage` *plus* a string gets neither, and the sheet falls
    /// back to a generic text header — so a poster somebody just waited two seconds
    /// for was represented by an "A" glyph. See `PosterItemSource`.
    var activityItems: [Any] {
        guard let caption else { return [image] }
        return [PosterItemSource(image: image, title: caption), caption]
    }
}

/// The poster, plus what the share sheet should show for it.
///
/// `UIActivityItemSource` exists for exactly this: the payload and its presentation
/// are two different questions, and handing over a bare `UIImage` only answers the
/// first. `activityViewControllerLinkMetadata` is what draws the header.
final class PosterItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    /// Called before the sheet has the real item, on the main thread, to size the
    /// preview. The image itself is already in memory, so there is nothing cheaper to
    /// hand back that would still be the right shape.
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        // The first line only. The caption's second line is the store link, and a
        // URL in a preview title reads as a link somebody is meant to tap here.
        metadata.title = title.split(separator: "\n").first.map(String.init) ?? title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

/// The words that go out with a poster.
///
/// This exists because the alternative was a QR code printed on the poster itself,
/// and a poster is a flat image: wherever it lands, nothing drawn in it is tappable.
/// A line of text in the same message is — and it says what the picture is to
/// anybody skimming, which a square of dots does not.
enum ShareInvite {

    /// **Set this when the app has an App Store ID.** Until then every poster goes
    /// out with the sentence and no link, which is the honest state of things — a
    /// link to a store page that does not exist is worse than no link at all.
    ///
    /// The App Store URL is the whole of what belongs here. Apple's "Download on the
    /// App Store" badge is a separate matter: it is their artwork, taken from the
    /// Marketing Resources page and used to their guidelines, and it is not
    /// something to approximate.
    static let storeURL: String? = nil

    /// One sentence, then the link on its own line so it is not swallowed by
    /// punctuation when a messaging app auto-detects it.
    static func line(for title: String, states: Int) -> String {
        let sentence = String(localized: "\(title): \(states) states spotted on Tags.")
        guard let storeURL else { return sentence }
        return sentence + "\n" + storeURL
    }
}

/// The share button, everywhere sharing a poster is offered.
///
/// Three screens had this written out: the Books tab, the book editor and the trip
/// editor. Each carried two pieces of state, a `Task` that flipped one of them either
/// side of an await, a button that swapped its icon for a spinner, and a `.sheet`
/// somewhere else in the file bound to the other. Four separate things that only make
/// sense together, kept in sync by hand in three places.
///
/// The spinner is not decoration. A trip's poster waits on MapKit for driving
/// directions, which is seconds rather than milliseconds, and without it the button
/// simply looked broken for the whole of that.
struct PosterShareButton: View {
    /// What this shares, said the way VoiceOver should read it: "Share this trip".
    let label: LocalizedStringKey
    /// Deferred rather than rendered up front, because rendering costs a map
    /// snapshot and most people never tap it. See `ShareSheet`.
    let make: () async -> PosterToShare?

    @State private var poster: PosterToShare?
    @State private var preparing = false
    /// Held so it can be cancelled. A poster is the most expensive thing the app
    /// renders — driving directions, a map snapshot, then the whole page through
    /// `ImageRenderer` — and left unstructured it kept running after the screen it
    /// was started from had gone, to set a `@State` nobody would ever see.
    /// Cancellation is cooperative, so this does not stop MapKit mid-request; it
    /// stops everything after the first await that checks, and it stops the write.
    @State private var job: Task<Void, Never>?

    var body: some View {
        Button {
            preparing = true
            job = Task {
                let made = await make()
                guard !Task.isCancelled else { return }
                poster = made
                preparing = false
            }
        } label: {
            if preparing {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .tint(Theme.route)
        .disabled(preparing)
        .accessibilityLabel(label)
        .sheet(item: $poster) { ready in
            ShareSheet(items: ready.activityItems)
        }
        .onDisappear {
            job?.cancel()
            preparing = false
        }
    }
}
