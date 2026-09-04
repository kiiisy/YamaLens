import Foundation
import OSLog

actor FileCameraDiagnosticShareFileProvider: CameraDiagnosticShareFileProviding {
    private let directoryURL: URL?
    private let now: @Sendable () -> Date
    private let maximumAge: TimeInterval
    private let diagnosticDirectoryURL: URL?

    init(
        directoryURL: URL? = nil,
        diagnosticDirectoryURL: URL? = nil,
        maximumAge: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appending(path: "DiagnosticShares", directoryHint: .isDirectory)
        }
        self.maximumAge = maximumAge
        self.now = now
        self.diagnosticDirectoryURL = diagnosticDirectoryURL
    }

    func prepareShareFile(
        for log: CameraDiagnosticLog,
        format: CameraDiagnosticShareFormat
    ) async throws -> CameraDiagnosticShareFile {
        let directoryURL = try preparedDirectoryURL()
        try removeExpiredShareFiles(in: directoryURL)

        let data: Data
        switch format {
        case .anonymizedSummary:
            data = try encodedData(CameraDiagnosticAnonymizedSummary(log: log))
        case .replayLogWithExactLocation:
            data = try encodedData(log)
        }

        let fileURL = directoryURL.appending(
            path: "\(UUID().uuidString.lowercased())-\(format.fileName)"
        )
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
        var additionalURLs: [URL] = []
        if case .replayLogWithExactLocation = format,
           let attachment = log.videoAttachment,
           let sourceURL = diagnosticVideoURL(named: attachment.fileName),
           FileManager.default.fileExists(atPath: sourceURL.path) {
            let videoURL = directoryURL.appending(
                path: "\(UUID().uuidString.lowercased())-\(attachment.fileName)"
            )
            try FileManager.default.copyItem(at: sourceURL, to: videoURL)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: videoURL.path
            )
            additionalURLs.append(videoURL)
        }
        return CameraDiagnosticShareFile(
            url: fileURL,
            additionalURLs: additionalURLs,
            format: format
        )
    }

    func removeShareFile(_ shareFile: CameraDiagnosticShareFile) async {
        for url in shareFile.allURLs where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger(subsystem: "com.kiiisy.YamaLens", category: "Diagnostics")
                    .error("A diagnostic share file could not be removed")
            }
        }
    }

    func removeExpiredShareFiles() async {
        guard let directoryURL else { return }
        do {
            try removeExpiredShareFiles(in: directoryURL)
        } catch {
            Logger(subsystem: "com.kiiisy.YamaLens", category: "Diagnostics")
                .error("Expired diagnostic share files could not be removed")
        }
    }

    func videoURL(for log: CameraDiagnosticLog) async -> URL? {
        guard let attachment = log.videoAttachment,
              let url = diagnosticVideoURL(named: attachment.fileName),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        return url
    }

    private func preparedDirectoryURL() throws -> URL {
        guard let directoryURL else {
            throw CameraDiagnosticLogStoreError.storageUnavailable
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directoryURL.path
        )
        var protectedURL = directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedURL.setResourceValues(resourceValues)
        return directoryURL
    }

    private func removeExpiredShareFiles(in directoryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        for fileURL in fileURLs {
            let values = try fileURL.resourceValues(forKeys: [.creationDateKey])
            guard
                let creationDate = values.creationDate,
                now().timeIntervalSince(creationDate) >= maximumAge
            else {
                continue
            }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func encodedData<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func diagnosticVideoURL(named fileName: String) -> URL? {
        guard !fileName.contains("/"), !fileName.contains("..") else { return nil }
        let directoryURL = diagnosticDirectoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appending(path: "Diagnostics", directoryHint: .isDirectory)
        return directoryURL?.appending(path: fileName)
    }
}
