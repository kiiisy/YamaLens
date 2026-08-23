import Foundation
import OSLog

nonisolated struct BootstrapMountainPointOfInterestRepository: MountainPointOfInterestRepository {
    private static let logger = Logger(
        subsystem: "com.kiiisy.YamaLens",
        category: "BootstrapMountainPointOfInterestRepository"
    )

    private let repository: any MountainPointOfInterestRepository

    init(bundle: Bundle = .main) {
        guard let databaseURL = BootstrapMountainRepository.databaseURL(in: bundle) else {
            Self.logger.error("Bundled bootstrap SQLite was not found; facility information is unavailable")
            repository = EmptyMountainPointOfInterestRepository()
            return
        }
        do {
            repository = try SQLiteMountainPointOfInterestRepository(databaseURL: databaseURL)
        } catch {
            Self.logger.error("Bundled facility information could not be read")
            repository = EmptyMountainPointOfInterestRepository()
        }
    }

    func fetchPointsOfInterest(for mountainID: String) -> [MountainPointOfInterest] {
        repository.fetchPointsOfInterest(for: mountainID)
    }

    func fetchTrailheadAccessGuides(for mountainID: String) -> [TrailheadAccessGuide] {
        repository.fetchTrailheadAccessGuides(for: mountainID)
    }
}
