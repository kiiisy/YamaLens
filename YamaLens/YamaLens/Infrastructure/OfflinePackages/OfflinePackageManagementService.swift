import Foundation

actor OfflinePackageManagementService: OfflinePackageManaging {
    private let packageID: String
    private let store: OfflinePackageStore
    private let installer: OfflinePackageInstaller?
    private let source: OfflinePackageSource?
    private let sourceResolver: (any OfflinePackageSourceResolving)?
    private let availableDistribution: OfflinePackageDistributionAvailability
    private let now: @Sendable () -> Date
    private let activeStagingIdentifiers: @Sendable () async -> Set<String>

    init(
        packageID: String = "jp.kanagawa.tanzawa",
        store: OfflinePackageStore,
        installer: OfflinePackageInstaller? = nil,
        source: OfflinePackageSource? = nil,
        sourceResolver: (any OfflinePackageSourceResolving)? = nil,
        availableDistribution: OfflinePackageDistributionAvailability = .available,
        now: @escaping @Sendable () -> Date = { .now },
        activeStagingIdentifiers: @escaping @Sendable () async -> Set<String> = { [] }
    ) {
        self.packageID = packageID
        self.store = store
        self.installer = installer
        self.source = source
        self.sourceResolver = sourceResolver
        self.availableDistribution = availableDistribution
        self.now = now
        self.activeStagingIdentifiers = activeStagingIdentifiers
    }

    func refresh() async throws -> OfflinePackageManagementSnapshot {
        do {
            let cutoff = now().addingTimeInterval(-24 * 60 * 60)
            _ = try await store.discardOrphanedStagingDirectories(
                olderThan: cutoff,
                preserving: await activeStagingIdentifiers()
            )
            _ = try await store.recoverPendingInstall(packageID: packageID)
            if let installer, let source,
               try await store.resumableStagingDirectory(packageID: packageID) != nil {
                _ = try await installer.install(from: source)
            }
            let stored = try await store.activePackageSummary(packageID: packageID)
            return OfflinePackageManagementSnapshot(
                installedPackage: stored.map(Self.summary(from:)),
                distributionAvailability: distributionAvailability
            )
        } catch {
            throw Self.map(error)
        }
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        guard let installer else {
            throw OfflinePackageManagementFailure.distributionUnavailable
        }
        do {
            let source = try await resolvedSource()
            if let stored = try await store.activePackageSummary(packageID: packageID),
               let expectedContentVersion = source.expectedContentVersion,
               !isNewer(expectedContentVersion, than: stored.contentVersion) {
                return Self.summary(from: stored)
            }
            _ = try await installer.install(from: source, progress: progress)
            guard let stored = try await store.activePackageSummary(packageID: packageID) else {
                throw OfflinePackageManagementFailure.internalFailure
            }
            return Self.summary(from: stored)
        } catch {
            throw Self.map(error)
        }
    }

    func deleteInstalledPackage() async throws {
        do {
            try await store.deletePackage(packageID: packageID)
        } catch {
            throw Self.map(error)
        }
    }

    private var distributionAvailability: OfflinePackageDistributionAvailability {
        installer != nil && (source != nil || sourceResolver != nil)
            ? availableDistribution
            : .unavailable
    }

    private func resolvedSource() async throws -> OfflinePackageSource {
        if let source {
            return source
        }
        guard let sourceResolver else {
            throw OfflinePackageManagementFailure.distributionUnavailable
        }
        return try await sourceResolver.resolveSource()
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let installedParts = installed.split(separator: ".").compactMap { Int($0) }
        guard candidateParts.count == 3, installedParts.count == 3 else {
            return false
        }
        return candidateParts.lexicographicallyPrecedes(installedParts, by: >)
    }

    private nonisolated static func summary(
        from stored: StoredOfflinePackageSummary
    ) -> OfflinePackageSummary {
        OfflinePackageSummary(
            packageID: stored.packageID,
            contentVersion: stored.contentVersion,
            byteCount: stored.byteCount,
            createdAt: stored.createdAt
        )
    }

    private nonisolated static func map(_ error: Error) -> OfflinePackageManagementFailure {
        if let failure = error as? OfflinePackageManagementFailure {
            return failure
        }
        if let failure = error as? OfflinePackageDownloadError {
            switch failure {
            case .temporaryFailure:
                return .temporaryFailure
            case .cancelled:
                return .cancelled
            case .insufficientStorage:
                return .insufficientStorage(requiredBytes: nil, availableBytes: nil)
            case .responseTooLarge,
                 .invalidDownloadedFile:
                return .invalidData
            case .permanentFailure,
                 .invalidResponse:
                return .distributionUnavailable
            }
        }
        if let failure = error as? OfflinePackageInstallationError {
            switch failure {
            case .packageIdentityMismatch:
                return .invalidData
            case .packageVersionMismatch:
                return .invalidData
            case .insufficientStorage(let requiredBytes, let availableBytes):
                return .insufficientStorage(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes
                )
            }
        }
        if error is OfflinePackageValidationError {
            return .invalidData
        }
        return .internalFailure
    }
}

nonisolated struct UnavailableOfflinePackageManager: OfflinePackageManaging {
    func refresh() async throws -> OfflinePackageManagementSnapshot {
        OfflinePackageManagementSnapshot(
            installedPackage: nil,
            distributionAvailability: .unavailable
        )
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        throw OfflinePackageManagementFailure.distributionUnavailable
    }

    func deleteInstalledPackage() async throws {}
}
