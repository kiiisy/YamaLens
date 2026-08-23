import Foundation

nonisolated enum ExternalBrowserApplication: String, CaseIterable, Sendable {
    case defaultBrowser
    case chrome
    case askEveryTime

    var displayName: String {
        switch self {
        case .defaultBrowser: "既定のブラウザ"
        case .chrome: "Chrome"
        case .askEveryTime: "毎回選択"
        }
    }
}
