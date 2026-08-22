import Foundation

nonisolated struct OfflinePackageSummary: Equatable, Sendable {
    let packageID: String
    let contentVersion: String
    let byteCount: Int64
    let createdAt: Date
}

nonisolated enum OfflinePackageDistributionAvailability: Equatable, Sendable {
    case available
    case unavailable
}

nonisolated struct OfflinePackageManagementSnapshot: Equatable, Sendable {
    let installedPackage: OfflinePackageSummary?
    let distributionAvailability: OfflinePackageDistributionAvailability
}

nonisolated enum OfflinePackageOperationProgress: Equatable, Sendable {
    case downloading(completedBytes: Int64, totalBytes: Int64?)
    case verifying
}

nonisolated enum OfflinePackageManagementFailure: Error, Equatable, Sendable {
    case temporaryFailure
    case distributionUnavailable
    case insufficientStorage(requiredBytes: Int64?, availableBytes: Int64?)
    case invalidData
    case cancelled
    case internalFailure

    var canRetry: Bool {
        switch self {
        case .temporaryFailure:
            return true
        case .distributionUnavailable,
             .insufficientStorage,
             .invalidData,
             .cancelled,
             .internalFailure:
            return false
        }
    }
}
