import Foundation
import Observation

enum OfflinePackageScreenState: Equatable {
    case loading
    case notInstalled(distribution: OfflinePackageDistributionAvailability)
    case installed(
        OfflinePackageSummary,
        distribution: OfflinePackageDistributionAvailability
    )
    case downloading(
        completedBytes: Int64,
        totalBytes: Int64?,
        previousPackage: OfflinePackageSummary?
    )
    case verifying(previousPackage: OfflinePackageSummary?)
    case deleting(OfflinePackageSummary)
    case failed(
        OfflinePackageManagementFailure,
        previousPackage: OfflinePackageSummary?,
        distribution: OfflinePackageDistributionAvailability
    )
}

@MainActor
@Observable
final class OfflinePackageScreenModel {
    private let manager: any OfflinePackageManaging
    private var distributionAvailability: OfflinePackageDistributionAvailability = .unavailable
    private(set) var state: OfflinePackageScreenState = .loading

    init(manager: any OfflinePackageManaging) {
        self.manager = manager
    }

    func load() async {
        guard !isOperationInProgress else { return }
        state = .loading
        do {
            apply(try await manager.refresh())
        } catch {
            state = .failed(
                failure(from: error),
                previousPackage: nil,
                distribution: distributionAvailability
            )
        }
    }

    func install() async {
        guard !isOperationInProgress else { return }
        let previousPackage = installedPackage
        state = .downloading(
            completedBytes: 0,
            totalBytes: nil,
            previousPackage: previousPackage
        )
        do {
            let installed = try await manager.install { [weak self] progress in
                await self?.apply(progress, previousPackage: previousPackage)
            }
            state = .installed(
                installed,
                distribution: distributionAvailability
            )
        } catch {
            let failure = failure(from: error)
            if failure == .cancelled {
                restore(previousPackage)
            } else {
                state = .failed(
                    failure,
                    previousPackage: previousPackage,
                    distribution: distributionAvailability
                )
            }
        }
    }

    func deleteInstalledPackage() async {
        guard !isOperationInProgress, let installedPackage else { return }
        state = .deleting(installedPackage)
        do {
            try await manager.deleteInstalledPackage()
            apply(try await manager.refresh())
        } catch {
            state = .failed(
                failure(from: error),
                previousPackage: installedPackage,
                distribution: distributionAvailability
            )
        }
    }

    private var installedPackage: OfflinePackageSummary? {
        switch state {
        case .installed(let package, _),
             .deleting(let package):
            return package
        case .downloading(_, _, let previousPackage),
             .verifying(let previousPackage),
             .failed(_, let previousPackage, _):
            return previousPackage
        case .loading,
             .notInstalled:
            return nil
        }
    }

    private var isOperationInProgress: Bool {
        switch state {
        case .downloading,
             .verifying,
             .deleting:
            return true
        case .loading,
             .notInstalled,
             .installed,
             .failed:
            return false
        }
    }

    private func apply(_ snapshot: OfflinePackageManagementSnapshot) {
        distributionAvailability = snapshot.distributionAvailability
        if let installedPackage = snapshot.installedPackage {
            state = .installed(
                installedPackage,
                distribution: snapshot.distributionAvailability
            )
        } else {
            state = .notInstalled(distribution: snapshot.distributionAvailability)
        }
    }

    private func apply(
        _ progress: OfflinePackageOperationProgress,
        previousPackage: OfflinePackageSummary?
    ) {
        switch progress {
        case .downloading(let completedBytes, let totalBytes):
            state = .downloading(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                previousPackage: previousPackage
            )
        case .verifying:
            state = .verifying(previousPackage: previousPackage)
        }
    }

    private func restore(_ previousPackage: OfflinePackageSummary?) {
        if let previousPackage {
            state = .installed(
                previousPackage,
                distribution: distributionAvailability
            )
        } else {
            state = .notInstalled(distribution: distributionAvailability)
        }
    }

    private func failure(from error: Error) -> OfflinePackageManagementFailure {
        error as? OfflinePackageManagementFailure ?? .internalFailure
    }
}
