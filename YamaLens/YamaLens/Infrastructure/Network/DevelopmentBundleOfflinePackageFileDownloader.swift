#if DEBUG
import Foundation

actor DevelopmentBundleOfflinePackageFileDownloader: OfflinePackageFileDownloading {
    private static let allowedFileNames = Set([
        "manifest.json",
        "manifest.sig",
        "catalog.sqlite",
        "terrain.lzfse",
    ])

    private let sourceDirectoryURL: URL
    private let fileManager: FileManager

    init(
        sourceDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.sourceDirectoryURL = sourceDirectoryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func download(
        from sourceURL: URL,
        to destinationURL: URL,
        maximumBytes: Int64,
        requestTimeoutSeconds: TimeInterval,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws {
        try Task.checkCancellation()
        let standardizedSourceURL = sourceURL.standardizedFileURL
        guard sourceURL.isFileURL,
              standardizedSourceURL.deletingLastPathComponent() == sourceDirectoryURL,
              Self.allowedFileNames.contains(standardizedSourceURL.lastPathComponent),
              maximumBytes > 0,
              !fileManager.fileExists(atPath: destinationURL.path) else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        let values = try standardizedSourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              Int64(fileSize) <= maximumBytes else {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }

        do {
            try fileManager.copyItem(at: standardizedSourceURL, to: destinationURL)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destinationURL.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDestinationURL = destinationURL
            try mutableDestinationURL.setResourceValues(resourceValues)
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            throw OfflinePackageDownloadError.insufficientStorage
        } catch {
            throw OfflinePackageDownloadError.invalidDownloadedFile
        }
        try Task.checkCancellation()
        progress(Int64(fileSize), Int64(fileSize))
    }
}
#endif
