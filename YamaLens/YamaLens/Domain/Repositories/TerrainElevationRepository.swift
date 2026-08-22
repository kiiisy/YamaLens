import Foundation

nonisolated protocol TerrainElevationRepository: Sendable {
    func elevations(at coordinates: [GeoCoordinate]) async throws -> [TerrainElevation?]
}
