import Foundation

nonisolated protocol MountainPointOfInterestRepository: Sendable {
    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest]
}

nonisolated struct EmptyMountainPointOfInterestRepository: MountainPointOfInterestRepository {
    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest] {
        []
    }
}
