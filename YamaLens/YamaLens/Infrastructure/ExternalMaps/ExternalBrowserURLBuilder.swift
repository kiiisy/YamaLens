import Foundation

nonisolated enum ExternalBrowserURLBuilder {
    static func chromeURL(for officialURL: URL) -> URL? {
        guard
            var components = URLComponents(url: officialURL, resolvingAgainstBaseURL: false),
            components.scheme == "https"
        else {
            return nil
        }
        components.scheme = "googlechromes"
        return components.url
    }
}
