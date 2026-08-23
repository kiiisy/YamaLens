import UIKit

@MainActor
enum ExternalMapApplicationAvailability {
    static var isGoogleMapsAvailable: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
