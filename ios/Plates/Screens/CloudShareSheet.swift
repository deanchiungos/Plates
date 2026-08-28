import CloudKit
import SwiftUI
import UIKit

/// Apple's share sheet for a `CKShare`, wrapped for SwiftUI.
///
/// This one *is* worth using as-is, unlike the party's peer browser. Sending an
/// iCloud invitation means Messages, Mail, and a link with the right entitlements
/// on it — reimplementing that would be reimplementing the share sheet, badly, and
/// people already know what it looks like. The party's picker was different: it was
/// a list of two names, and Apple's version arrived looking like a different app.
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // No public link — a plate book is not something to put on the open web,
        // and read-write because the whole point is that they add plates too.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudShareSheet
        init(_ parent: CloudShareSheet) { self.parent = parent }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            parent.share[CKShare.SystemFieldKey.title] as? String ?? "Plate book"
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            parent.onFinish()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            parent.onFinish()
        }

        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            parent.onFinish()
        }
    }
}
