import Foundation
import Testing
@testable import YamaLens

struct BackgroundOfflinePackageFileDownloaderTests {
    @Test("taskDescriptionから安全な一時保存先を復元する")
    func restoresValidatedTaskDescriptor() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensDescriptorTests")
        let destinationURL = rootURL
            .appending(path: "Staging", directoryHint: .isDirectory)
            .appending(path: "download-123", directoryHint: .isDirectory)
            .appending(path: "terrain.lzfse")
        let descriptor = try BackgroundDownloadTaskDescriptor(
            destinationURL: destinationURL,
            rootURL: rootURL,
            maximumBytes: 42_000
        )

        let restored = try #require(
            BackgroundDownloadTaskDescriptor(encoded: try descriptor.encoded())
        )

        #expect(restored == descriptor)
        #expect(restored.destinationURL(rootURL: rootURL) == destinationURL)
    }

    @Test("一時領域外と未知のファイル名をtaskDescriptionへ登録しない")
    func rejectsUnsafeTaskDestinations() {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensDescriptorTests")
        let outsideURL = rootURL.appending(path: "outside.sqlite")
        let unknownURL = rootURL
            .appending(path: "Staging", directoryHint: .isDirectory)
            .appending(path: "download-123", directoryHint: .isDirectory)
            .appending(path: "unknown.bin")

        #expect(throws: OfflinePackageDownloadError.invalidDownloadedFile) {
            try BackgroundDownloadTaskDescriptor(
                destinationURL: outsideURL,
                rootURL: rootURL,
                maximumBytes: 100
            )
        }
        #expect(throws: OfflinePackageDownloadError.invalidDownloadedFile) {
            try BackgroundDownloadTaskDescriptor(
                destinationURL: unknownURL,
                rootURL: rootURL,
                maximumBytes: 100
            )
        }
    }
}
