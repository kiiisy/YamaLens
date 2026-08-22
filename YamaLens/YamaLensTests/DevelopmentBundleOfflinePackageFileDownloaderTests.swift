#if DEBUG
import Foundation
import Synchronization
import Testing
@testable import YamaLens

struct DevelopmentBundleOfflinePackageFileDownloaderTests {
    @Test("開発用Bundleの許可ファイルを一時領域へ複製する")
    func copiesAllowedFile() async throws {
        let rootURL = temporaryDirectory(named: "success")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceDirectoryURL = rootURL.appending(path: "Source", directoryHint: .isDirectory)
        let destinationDirectoryURL = rootURL.appending(
            path: "Destination",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: sourceDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationDirectoryURL,
            withIntermediateDirectories: true
        )
        let sourceURL = sourceDirectoryURL.appending(path: "manifest.json")
        let destinationURL = destinationDirectoryURL.appending(path: "manifest.json")
        let sourceData = Data("signed manifest".utf8)
        try sourceData.write(to: sourceURL)
        let downloader = DevelopmentBundleOfflinePackageFileDownloader(
            sourceDirectoryURL: sourceDirectoryURL
        )
        let progressValue = Mutex<(Int64, Int64?)?>(nil)

        try await downloader.download(
            from: sourceURL,
            to: destinationURL,
            maximumBytes: 256 * 1_024,
            requestTimeoutSeconds: 15
        ) { receivedBytes, totalBytes in
            progressValue.withLock { value in
                value = (receivedBytes, totalBytes)
            }
        }

        #expect(try Data(contentsOf: destinationURL) == sourceData)
        let recordedValue = progressValue.withLock { $0 }
        #expect(recordedValue?.0 == Int64(sourceData.count))
        #expect(recordedValue?.1 == Int64(sourceData.count))
    }

    @Test("開発用Bundleの対象外ディレクトリを拒否する")
    func rejectsFileOutsideSourceDirectory() async throws {
        let rootURL = temporaryDirectory(named: "outside")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let sourceDirectoryURL = rootURL.appending(path: "Source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: sourceDirectoryURL,
            withIntermediateDirectories: true
        )
        let outsideURL = rootURL.appending(path: "manifest.json")
        try Data("outside".utf8).write(to: outsideURL)
        let downloader = DevelopmentBundleOfflinePackageFileDownloader(
            sourceDirectoryURL: sourceDirectoryURL
        )

        await #expect(throws: OfflinePackageDownloadError.invalidDownloadedFile) {
            try await downloader.download(
                from: outsideURL,
                to: rootURL.appending(path: "copied-manifest.json"),
                maximumBytes: 256 * 1_024,
                requestTimeoutSeconds: 15
            )
        }
    }

    @Test("通常の配布元初期化でfile URLを受け付けない")
    func remoteSourceRejectsFileURL() throws {
        #expect(throws: OfflinePackageSourceError.invalidBaseURL) {
            try OfflinePackageSource(
                packageID: "jp.kanagawa.tanzawa",
                baseURL: URL(filePath: "/tmp/tanzawa")
            )
        }
    }

    private func temporaryDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "DevelopmentBundleOfflinePackageFileDownloaderTests")
            .appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
#endif
