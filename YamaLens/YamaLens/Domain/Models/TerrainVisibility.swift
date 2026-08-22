import Foundation

nonisolated struct TerrainElevation: Equatable, Sendable {
    let meters: Double

    init?(meters: Double) {
        guard meters.isFinite else { return nil }
        self.meters = meters
    }
}

nonisolated struct TerrainProfileSample: Equatable, Sendable {
    let distance: MountainDistance
    let elevation: TerrainElevation?
}

nonisolated enum TerrainVisibility: Equatable, Sendable {
    case notOccluded
    case occluded(maximumExcessHeightMeters: Double)
    case unavailable
}
