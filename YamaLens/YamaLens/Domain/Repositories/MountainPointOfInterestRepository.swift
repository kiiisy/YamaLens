import Foundation

nonisolated protocol MountainPointOfInterestRepository: Sendable {
    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest]
    func fetchTrailheadAccessGuides(for mountainID: String) -> [TrailheadAccessGuide]
}

nonisolated struct EmptyMountainPointOfInterestRepository: MountainPointOfInterestRepository {
    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest] {
        []
    }

    func fetchTrailheadAccessGuides(for mountainID: String) -> [TrailheadAccessGuide] {
        []
    }
}
