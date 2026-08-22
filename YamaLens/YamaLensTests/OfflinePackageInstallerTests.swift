import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageInstallerTests {
    @Test("署名済み4ファイルを取得して検証後にactiveへ切り替える")
    func downloadsValidatesAndInstallsPackage() async throws {
        let context = try makeContext(named: "success")
        defer { removeTemporaryDirectory(context.rootURL) }

        let installed = try await context.installer.install(from: context.source)
        let activeURL = try await context.store.activePackageURL(
            packageID: context.fixture.packageID
        )

        #expect(installed.contentVersion == context.fixture.contentVersion)
        #expect(activeURL == installed.directoryURL)
        #expect(await context.downloader.requestCount == 4)
        #expect(
            !FileManager.default.fileExists(
                atPath: installed.directoryURL.appending(path: "staging-journal.json").path
            )
        )
    }

    @Test("同じパックの同時要求は1回のダウンロードへ集約する")
    func coalescesConcurrentInstallRequests() async throws {
        let context = try makeContext(named: "coalesced")
        defer { removeTemporaryDirectory(context.rootURL) }

        async let first = context.installer.install(from: context.source)
        async let second = context.installer.install(from: context.source)
        let results = try await [first, second]

        #expect(results[0].directoryURL == results[1].directoryURL)
        #expect(await context.downloader.requestCount == 4)
    }

    @Test("manifestの一時的失敗だけ2秒待機相当後に1回再試行する")
    func retriesTemporaryMetadataFailureOnce() async throws {
        let context = try makeContext(
            named: "retry",
            temporaryFailures: ["manifest.json": 1]
        )
        defer { removeTemporaryDirectory(context.rootURL) }

        _ = try await context.installer.install(from: context.source)

        #expect(await context.downloader.requestCount == 5)
        #expect(await context.retryWaiter.waitCount == 1)
    }

    @Test("大容量ファイルの一時的失敗は先頭から自動再取得しない")
    func doesNotRetryPackageBodyFromBeginning() async throws {
        let context = try makeContext(
            named: "body-no-retry",
            temporaryFailures: ["catalog.sqlite": 1]
        )
        defer { removeTemporaryDirectory(context.rootURL) }

        await #expect(throws: OfflinePackageDownloadError.temporaryFailure) {
            try await context.installer.install(from: context.source)
        }

        #expect(await context.downloader.requestCount == 3)
        #expect(await context.retryWaiter.waitCount == 0)
    }

    @Test("署名不正では導入せず一時ファイルを破棄する")
    func discardsStagingAfterInvalidSignature() async throws {
        let context = try makeContext(named: "invalid-signature")
        defer { removeTemporaryDirectory(context.rootURL) }
        try Data(repeating: 0, count: 64).write(to: context.fixture.signatureURL)

        await #expect(throws: OfflinePackageValidationError.invalidSignature) {
            try await context.installer.install(from: context.source)
        }

        let stagingURL = context.storeRootURL.appending(path: "Staging")
        let entries = try FileManager.default.contentsOfDirectory(
            at: stagingURL,
            includingPropertiesForKeys: nil
        )
        #expect(entries.isEmpty)
        #expect(
            try await context.store.activePackageURL(packageID: context.fixture.packageID) == nil
        )
    }

    @Test("HTTPや認証情報入りURLを配布元として受け付けない")
    func rejectsUnsafeSourceURLs() throws {
        let HTTPURL = try #require(URL(string: "http://example.com/tanzawa/1.0.0/"))
        let credentialURL = try #require(
            URL(string: "https://user:password@example.com/tanzawa/1.0.0/")
        )

        #expect(throws: OfflinePackageSourceError.invalidBaseURL) {
            try OfflinePackageSource(packageID: "jp.kanagawa.tanzawa", baseURL: HTTPURL)
        }
        #expect(throws: OfflinePackageSourceError.invalidBaseURL) {
            try OfflinePackageSource(
                packageID: "jp.kanagawa.tanzawa",
                baseURL: credentialURL
            )
        }
    }

    private func makeContext(
        named name: String,
        temporaryFailures: [String: Int] = [:]
    ) throws -> InstallerTestContext {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensOfflinePackageInstallerTests")
            .appending(path: name)
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
        let sourceDirectoryURL = rootURL.appending(path: "Source")
        let fixture = try OfflinePackageFixture.make(at: sourceDirectoryURL)
        let storeRootURL = rootURL.appending(path: "OfflinePackages")
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)
        let store = OfflinePackageStore(rootURL: storeRootURL, validator: validator)
        let downloader = CopyingOfflinePackageFileDownloader(
            sourceDirectoryURL: sourceDirectoryURL,
            temporaryFailures: temporaryFailures
        )
        let retryWaiter = ImmediateOfflinePackageRetryWaiter()
        let installer = OfflinePackageInstaller(
            store: store,
            validator: validator,
            fileDownloader: downloader,
            retryWaiter: retryWaiter,
            makeIdentifier: {
                UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            }
        )
        let baseURL = try #require(
            URL(string: "https://packages.example.com/tanzawa/1.0.0/")
        )
        let source = try OfflinePackageSource(
            packageID: fixture.packageID,
            baseURL: baseURL
        )
        return InstallerTestContext(
            rootURL: rootURL,
            storeRootURL: storeRootURL,
            fixture: fixture,
            store: store,
            downloader: downloader,
            retryWaiter: retryWaiter,
            installer: installer,
            source: source
        )
    }

    private func removeTemporaryDirectory(_ url: URL) {
        // テスト専用領域の後始末であり、失敗しても検証結果へ影響しない。
        try? FileManager.default.removeItem(at: url)
    }
}

private struct InstallerTestContext {
    let rootURL: URL
    let storeRootURL: URL
    let fixture: OfflinePackageFixture
    let store: OfflinePackageStore
    let downloader: CopyingOfflinePackageFileDownloader
    let retryWaiter: ImmediateOfflinePackageRetryWaiter
    let installer: OfflinePackageInstaller
    let source: OfflinePackageSource
}

private actor CopyingOfflinePackageFileDownloader: OfflinePackageFileDownloading {
    private let sourceDirectoryURL: URL
    private var temporaryFailures: [String: Int]
    private(set) var requestCount = 0

    init(sourceDirectoryURL: URL, temporaryFailures: [String: Int]) {
        self.sourceDirectoryURL = sourceDirectoryURL
        self.temporaryFailures = temporaryFailures
    }

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval
    ) async throws {
        requestCount += 1
        let fileName = sourceURL.lastPathComponent
        if let remainingFailures = temporaryFailures[fileName], remainingFailures > 0 {
            temporaryFailures[fileName] = remainingFailures - 1
            throw OfflinePackageDownloadError.temporaryFailure
        }
        let localSourceURL = sourceDirectoryURL.appending(path: fileName)
        let size = try localSourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, Int64(size) <= maximumBytes else {
            throw OfflinePackageDownloadError.responseTooLarge
        }
        try FileManager.default.copyItem(at: localSourceURL, to: destinationURL)
    }
}

private actor ImmediateOfflinePackageRetryWaiter: OfflinePackageRetryWaiting {
    private(set) var waitCount = 0

    func waitBeforeRetry() async throws {
        waitCount += 1
    }
}
