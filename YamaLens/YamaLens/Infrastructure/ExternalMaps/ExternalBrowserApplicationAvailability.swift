import UIKit

@MainActor
enum ExternalBrowserApplicationAvailability {
    static var isChromeAvailable: Bool {
        guard let url = URL(string: "googlechromes://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
