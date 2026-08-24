import Foundation
import SwiftData

@Model
final class SavedDeparturePoint {
    @Attribute(.unique) var identifier: String
    var name: String
    var latitude: Double
    var longitude: Double
    var updatedAt: Date

    init(
        name: String,
        coordinate: GeoCoordinate,
        updatedAt: Date = .now
    ) {
        identifier = "frequent-departure-station"
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.updatedAt = updatedAt
    }

    var coordinate: GeoCoordinate? {
        guard
            latitude.isFinite,
            longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    func replace(
        name: String,
        coordinate: GeoCoordinate,
        updatedAt: Date = .now
    ) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.updatedAt = updatedAt
    }
}

nonisolated struct StationSearchResult: Identifiable, Equatable, Sendable {
    let name: String
    let locality: String?
    let coordinate: GeoCoordinate

    var id: String {
        "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"
    }
}

nonisolated protocol StationSearching: Sendable {
    func searchStations(query: String) async throws -> [StationSearchResult]
}

nonisolated enum StationSearchError: Error, Equatable, Sendable {
    case emptyQuery
    case temporarilyUnavailable
}
