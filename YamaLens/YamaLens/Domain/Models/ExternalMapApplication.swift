import Foundation

nonisolated enum ExternalMapApplication: String, CaseIterable, Sendable {
    case appleMaps
    case googleMaps
    case askEveryTime

    var displayName: String {
        switch self {
        case .appleMaps: "Appleマップ"
        case .googleMaps: "Google Maps"
        case .askEveryTime: "毎回選択"
        }
    }
}
