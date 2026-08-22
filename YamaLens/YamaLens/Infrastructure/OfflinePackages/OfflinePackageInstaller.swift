import Foundation

nonisolated enum OfflinePackageInstallationError: Error, Equatable, Sendable {
    case packageIdentityMismatch
}

nonisolated protocol OfflinePackageRetryWaiting: Sendable {
    func waitBeforeRetry() async throws
}

nonisolated struct OfflinePackageRetryWaiter: OfflinePackageRetryWaiting, Sendable {
    private let delay: Duration

    init(policy: OfflinePackageNetworkPolicy = .default) {
        delay = .seconds(policy.retryDelaySeconds)
    }

    func waitBeforeRetry() async throws {
        try await Task.sleep(for: delay)
    }
}

actor OfflinePackageInstaller {
    private let store: OfflinePackageStore
    private let validator: OfflinePackageValidator
    private let fileDownloader: any OfflinePackageFileDownloading
    private let retryWaiter: any OfflinePackageRetryWaiting
    private let policy: OfflinePackageNetworkPolicy
    private let makeIdentifier: @Sendable () -> UUID
    private var installationTasksByPackageID: [
        String: Task<InstalledOfflinePackage, Error>
    ] = [:]

    init(
        store: OfflinePackageStore,
        validator: OfflinePackageValidator,
        fileDownloader: any OfflinePackageFileDownloading,
        retryWaiter: any OfflinePackageRetryWaiting = OfflinePackageRetryWaiter(),
        policy: OfflinePackageNetworkPolicy = .default,
        makeIdentifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.store = store
        self.validator = validator
        self.fileDownloader = fileDownloader
        self.retryWaiter = retryWaiter
        self.policy = policy
        self.makeIdentifier = makeIdentifier
    }

    func install(from source: OfflinePackageSource) async throws -> InstalledOfflinePackage {
        if let currentTask = installationTasksByPackageID[source.packageID] {
            return try await currentTask.value
        }

        let stagingIdentifier = "download-\(makeIdentifier().uuidString.lowercased())"
        let task = Task {
            try await Self.performInstallation(
                from: source,
                stagingIdentifier: stagingIdentifier,
                store: store,
                validator: validator,
                fileDownloader: fileDownloader,
                retryWaiter: retryWaiter,
                policy: policy
            )
        }
        installationTasksByPackageID[source.packageID] = task
        do {
            let installed = try await task.value
            installationTasksByPackageID[source.packageID] = nil
            return installed
        } catch {
            installationTasksByPackageID[source.packageID] = nil
            throw error
        }
    }

    private nonisolated static func performInstallation(
        from source: OfflinePackageSource,
        stagingIdentifier: String,
        store: OfflinePackageStore,
        validator: OfflinePackageValidator,
        fileDownloader: any OfflinePackageFileDownloading,
        retryWaiter: any OfflinePackageRetryWaiting,
        policy: OfflinePackageNetworkPolicy
    ) async throws -> InstalledOfflinePackage {
        let stagingURL = try await store.prepareStagingDirectory(identifier: stagingIdentifier)
        do {
            try await store.setStagingState(.downloading, for: stagingURL)
            try await downloadMetadataFile(
                named: "manifest.json",
                maximumBytes: policy.maximumManifestBytes,
                source: source,
                stagingURL: stagingURL,
                fileDownloader: fileDownloader,
                retryWaiter: retryWaiter,
                policy: policy
            )
            try await downloadMetadataFile(
                named: "manifest.sig",
                maximumBytes: policy.signatureBytes,
                source: source,
                stagingURL: stagingURL,
                fileDownloader: fileDownloader,
                retryWaiter: retryWaiter,
                policy: policy
            )

            let manifest = try validator.validatePackageMetadata(at: stagingURL)
            guard manifest.packageID == source.packageID else {
                throw OfflinePackageInstallationError.packageIdentityMismatch
            }
            for file in manifest.files.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                try await fileDownloader.download(
                    from: source.urlForFile(named: file.path),
                    to: stagingURL.appending(path: file.path, directoryHint: .notDirectory),
                    maximumBytes: file.byteCount,
                    requestTimeoutSeconds: policy.packageRequestTimeoutSeconds
                )
            }
            try await store.setStagingState(.verifying, for: stagingURL)
            return try await store.install(stagedPackageURL: stagingURL)
        } catch {
            let installationError = error
            do {
                try await store.discardStagingDirectory(stagingURL)
            } catch {
                throw error
            }
            throw installationError
        }
    }

    private nonisolated static func downloadMetadataFile(
        named fileName: String,
        maximumBytes: Int64,
        source: OfflinePackageSource,
        stagingURL: URL,
        fileDownloader: any OfflinePackageFileDownloading,
        retryWaiter: any OfflinePackageRetryWaiting,
        policy: OfflinePackageNetworkPolicy
    ) async throws {
        let sourceURL = try source.urlForFile(named: fileName)
        let destinationURL = stagingURL.appending(path: fileName, directoryHint: .notDirectory)
        do {
            try await fileDownloader.download(
                from: sourceURL,
                to: destinationURL,
                maximumBytes: maximumBytes,
                requestTimeoutSeconds: policy.metadataRequestTimeoutSeconds
            )
        } catch OfflinePackageDownloadError.temporaryFailure {
            try await retryWaiter.waitBeforeRetry()
            try await fileDownloader.download(
                from: sourceURL,
                to: destinationURL,
                maximumBytes: maximumBytes,
                requestTimeoutSeconds: policy.metadataRequestTimeoutSeconds
            )
        }
    }
}
