import Foundation

nonisolated enum OfflinePackageInstallationError: Error, Equatable, Sendable {
    case packageIdentityMismatch
    case packageVersionMismatch
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
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
    private let capacityChecker: any OfflinePackageStorageCapacityChecking
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
        capacityChecker: any OfflinePackageStorageCapacityChecking = VolumeOfflinePackageStorageCapacityChecker(),
        policy: OfflinePackageNetworkPolicy = .default,
        makeIdentifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.store = store
        self.validator = validator
        self.fileDownloader = fileDownloader
        self.retryWaiter = retryWaiter
        self.capacityChecker = capacityChecker
        self.policy = policy
        self.makeIdentifier = makeIdentifier
    }

    func install(
        from source: OfflinePackageSource,
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void = { _ in }
    ) async throws -> InstalledOfflinePackage {
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
                capacityChecker: capacityChecker,
                policy: policy,
                progress: progress
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
        capacityChecker: any OfflinePackageStorageCapacityChecking,
        policy: OfflinePackageNetworkPolicy,
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> InstalledOfflinePackage {
        let stagingURL: URL
        if let resumableURL = try await store.resumableStagingDirectory(
            packageID: source.packageID
        ) {
            stagingURL = resumableURL
        } else {
            stagingURL = try await store.prepareStagingDirectory(
                identifier: stagingIdentifier,
                packageID: source.packageID
            )
        }
        do {
            await progress(.downloading(completedBytes: 0, totalBytes: nil))
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
            if let expectedContentVersion = source.expectedContentVersion,
               manifest.contentVersion != expectedContentVersion {
                throw OfflinePackageInstallationError.packageVersionMismatch
            }
            let totalBytes = manifest.files.reduce(Int64(0)) { $0 + $1.byteCount }
            var completedBytes: Int64 = 0
            var downloadedFilePaths = Set<String>()
            for file in manifest.files {
                let destinationURL = stagingURL.appending(
                    path: file.path,
                    directoryHint: .notDirectory
                )
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try validator.validateDownloadedFile(file, in: stagingURL)
                    completedBytes += file.byteCount
                    downloadedFilePaths.insert(file.path)
                }
            }
            let requiredBytes = totalBytes - completedBytes
            let availableBytes = try capacityChecker.availableCapacity(at: stagingURL)
            guard availableBytes >= requiredBytes else {
                throw OfflinePackageInstallationError.insufficientStorage(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes
                )
            }
            await progress(
                .downloading(
                    completedBytes: completedBytes,
                    totalBytes: totalBytes
                )
            )
            for file in manifest.files.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                if downloadedFilePaths.contains(file.path) {
                    continue
                }
                let destinationURL = stagingURL.appending(
                    path: file.path,
                    directoryHint: .notDirectory
                )
                let completedBeforeFile = completedBytes
                try await downloadBodyFile(
                    file,
                    source: source,
                    destinationURL: destinationURL,
                    completedBeforeFile: completedBeforeFile,
                    totalBytes: totalBytes,
                    fileDownloader: fileDownloader,
                    policy: policy,
                    progress: progress
                )
                completedBytes += file.byteCount
                await progress(
                    .downloading(
                        completedBytes: completedBytes,
                        totalBytes: totalBytes
                    )
                )
            }
            await progress(.verifying)
            try await store.setStagingState(.verifying, for: stagingURL)
            return try await store.install(stagedPackageURL: stagingURL)
        } catch {
            let installationError = error
            if !shouldPreserveStaging(after: installationError) {
                do {
                    try await store.discardStagingDirectory(stagingURL)
                } catch {
                    throw error
                }
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
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }
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

    private nonisolated static func downloadBodyFile(
        _ file: OfflinePackageManifest.FileRecord,
        source: OfflinePackageSource,
        destinationURL: URL,
        completedBeforeFile: Int64,
        totalBytes: Int64,
        fileDownloader: any OfflinePackageFileDownloading,
        policy: OfflinePackageNetworkPolicy,
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws {
        let (stream, continuation) = AsyncStream<DownloadedByteProgress>.makeStream()
        let forwardingTask = Task {
            for await update in stream {
                await progress(
                    .downloading(
                        completedBytes: min(
                            completedBeforeFile + update.receivedBytes,
                            totalBytes
                        ),
                        totalBytes: totalBytes
                    )
                )
            }
        }
        do {
            try await fileDownloader.download(
                from: source.urlForFile(named: file.path),
                to: destinationURL,
                maximumBytes: file.byteCount,
                requestTimeoutSeconds: policy.packageRequestTimeoutSeconds
            ) { receivedBytes, expectedBytes in
                continuation.yield(
                    DownloadedByteProgress(
                        receivedBytes: receivedBytes,
                        expectedBytes: expectedBytes
                    )
                )
            }
            continuation.finish()
            await forwardingTask.value
        } catch {
            continuation.finish()
            await forwardingTask.value
            throw error
        }
    }

    private nonisolated static func shouldPreserveStaging(after error: Error) -> Bool {
        error is OfflinePackageDownloadError || error is CancellationError
    }
}

private nonisolated struct DownloadedByteProgress: Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64?
}
