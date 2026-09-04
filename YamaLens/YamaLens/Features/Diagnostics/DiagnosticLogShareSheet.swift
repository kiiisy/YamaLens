import SwiftUI
import UIKit

struct DiagnosticLogShareSheet: UIViewControllerRepresentable {
    let fileURLs: [URL]
    let onCompletion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: fileURLs,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onCompletion()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
