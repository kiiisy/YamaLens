import Foundation

actor OfflinePackageCollectionManager: OfflinePackageManaging {
    private let managers: [any OfflinePackageManaging]
    private let collectionPackageID: String

    init(
        managers: [any OfflinePackageManaging],
        collectionPackageID: String = "development.ar-field-test-set"
    ) {
        self.managers = managers
        self.collectionPackageID = collectionPackageID
    }

    func refresh() async throws -> OfflinePackageManagementSnapshot {
        try aggregate(snapshots: try await refreshedSnapshots())
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        let snapshots = try await refreshedSnapshots()
        for (index, manager) in managers.enumerated()
            where snapshots[index].installedPackage == nil {
            _ = try await manager.install(progress: progress)
        }
        let installed = try aggregate(snapshots: try await refreshedSnapshots())
        guard let summary = installed.installedPackage else {
            throw OfflinePackageManagementFailure.internalFailure
        }
        return summary
    }

    func deleteInstalledPackage() async throws {
        var firstFailure: Error?
        for manager in managers {
            do {
                try await manager.deleteInstalledPackage()
            } catch {
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func refreshedSnapshots() async throws -> [OfflinePackageManagementSnapshot] {
        var snapshots: [OfflinePackageManagementSnapshot] = []
        snapshots.reserveCapacity(managers.count)
        for manager in managers {
            snapshots.append(try await manager.refresh())
        }
        return snapshots
    }

    private func aggregate(
        snapshots: [OfflinePackageManagementSnapshot]
    ) throws -> OfflinePackageManagementSnapshot {
        guard snapshots.count == managers.count, !snapshots.isEmpty else {
            return OfflinePackageManagementSnapshot(
                installedPackage: nil,
                distributionAvailability: .unavailable
            )
        }
        let distribution = aggregateDistribution(snapshots: snapshots)
        let installed = snapshots.compactMap(\.installedPackage)
        guard installed.count == snapshots.count else {
            return OfflinePackageManagementSnapshot(
                installedPackage: nil,
                distributionAvailability: distribution
            )
        }
        return OfflinePackageManagementSnapshot(
            installedPackage: try aggregateSummary(installed),
            distributionAvailability: distribution
        )
    }

    private func aggregateDistribution(
        snapshots: [OfflinePackageManagementSnapshot]
    ) -> OfflinePackageDistributionAvailability {
        guard snapshots.allSatisfy(\.distributionAvailability.canInstall) else {
            return .unavailable
        }
        return snapshots.allSatisfy {
            $0.distributionAvailability == .developmentBundle
        } ? .developmentBundle : .available
    }

    private func aggregateSummary(
        _ packages: [OfflinePackageSummary]
    ) throws -> OfflinePackageSummary {
        guard let firstPackage = packages.first else {
            throw OfflinePackageManagementFailure.internalFailure
        }
        var totalBytes: Int64 = 0
        for package in packages {
            let (newTotal, overflowed) = totalBytes.addingReportingOverflow(package.byteCount)
            guard !overflowed else {
                throw OfflinePackageManagementFailure.internalFailure
            }
            totalBytes = newTotal
        }
        let versions = Set(packages.map(\.contentVersion))
        return OfflinePackageSummary(
            packageID: collectionPackageID,
            contentVersion: versions.count == 1 ? firstPackage.contentVersion : "複数バージョン",
            byteCount: totalBytes,
            createdAt: packages.map(\.createdAt).max() ?? firstPackage.createdAt
        )
    }
}
