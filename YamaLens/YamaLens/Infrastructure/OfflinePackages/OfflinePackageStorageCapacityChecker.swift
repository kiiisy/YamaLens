import Foundation

nonisolated protocol OfflinePackageStorageCapacityChecking: Sendable {
    func availableCapacity(at directoryURL: URL) throws -> Int64
}

nonisolated struct VolumeOfflinePackageStorageCapacityChecker: OfflinePackageStorageCapacityChecking {
    func availableCapacity(at directoryURL: URL) throws -> Int64 {
        let values = try directoryURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let availableBytes = values.volumeAvailableCapacityForImportantUsage,
              availableBytes >= 0 else {
            throw OfflinePackageStorageCapacityError.unavailable
        }
        return availableBytes
    }
}

nonisolated enum OfflinePackageStorageCapacityError: Error, Equatable, Sendable {
    case unavailable
}
