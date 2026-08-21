import Foundation

nonisolated struct GeoCoordinate: Codable, Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}
