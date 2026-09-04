import Foundation

actor FileCameraDiagnosticLogRepository: CameraDiagnosticLogRepository {
    private let directoryURL: URL?
    private let now: @Sendable () -> Date
    private let policy: CameraDiagnosticPolicy

    init(
        directoryURL: URL? = nil,
        policy: CameraDiagnosticPolicy = .default,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appending(path: "Diagnostics", directoryHint: .isDirectory)
        }
        self.policy = policy
        self.now = now
    }

    func fetchLogs() async throws -> [CameraDiagnosticLog] {
        let directoryURL = try preparedDirectoryURL()
        var logs = try decodedLogs(in: directoryURL)
        logs = try removeExpiredLogs(from: logs, in: directoryURL)
        return logs.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ log: CameraDiagnosticLog) async throws {
        guard
            log.schemaVersion == CameraDiagnosticLog.currentSchemaVersion,
            !log.samples.isEmpty,
            log.endedAt >= log.startedAt
        else {
            throw CameraDiagnosticLogStoreError.invalidLog
        }

        let directoryURL = try preparedDirectoryURL()
        try write(log, to: fileURL(for: log.id, in: directoryURL))
        let logs = try decodedLogs(in: directoryURL)
        _ = try removeExpiredLogs(from: logs, in: directoryURL)
    }

    func setRetained(_ isRetained: Bool, for id: UUID) async throws {
        let directoryURL = try preparedDirectoryURL()
        let url = fileURL(for: id, in: directoryURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CameraDiagnosticLogStoreError.logNotFound
        }
        let log = try decodeLog(at: url)
        try write(log.settingRetained(isRetained), to: url)
        let logs = try decodedLogs(in: directoryURL)
        _ = try removeExpiredLogs(from: logs, in: directoryURL)
    }

    func delete(id: UUID) async throws {
        let directoryURL = try preparedDirectoryURL()
        try removeFiles(for: id, in: directoryURL)
    }

    func deleteAll() async throws {
        let directoryURL = try preparedDirectoryURL()
        for url in try logFileURLs(in: directoryURL) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                continue
            }
            try removeFiles(for: id, in: directoryURL)
        }
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

    private func decodedLogs(in directoryURL: URL) throws -> [CameraDiagnosticLog] {
        try logFileURLs(in: directoryURL).map(decodeLog(at:))
    }

    private func logFileURLs(in directoryURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { $0.pathExtension == "json" }
    }

    private func decodeLog(at url: URL) throws -> CameraDiagnosticLog {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize <= policy.maximumLogByteCount else {
            throw CameraDiagnosticLogStoreError.invalidLog
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let log = try decoder.decode(CameraDiagnosticLog.self, from: data)
        guard
            log.schemaVersion >= CameraDiagnosticLog.minimumSupportedSchemaVersion,
            log.schemaVersion <= CameraDiagnosticLog.currentSchemaVersion
        else {
            throw CameraDiagnosticLogStoreError.unsupportedSchema
        }
        guard !log.samples.isEmpty, log.endedAt >= log.startedAt else {
            throw CameraDiagnosticLogStoreError.invalidLog
        }
        return log
    }

    private func write(_ log: CameraDiagnosticLog, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(log)
        guard data.count <= policy.maximumLogByteCount else {
            throw CameraDiagnosticLogStoreError.invalidLog
        }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func removeExpiredLogs(
        from logs: [CameraDiagnosticLog],
        in directoryURL: URL
    ) throws -> [CameraDiagnosticLog] {
        let currentDate = now()
        let unretained = logs
            .filter { !$0.isRetained }
            .sorted { $0.startedAt > $1.startedAt }
        let countOverflowIDs = Set(
            unretained.dropFirst(policy.maximumUnretainedLogCount).map(\.id)
        )
        let expiredIDs = Set(unretained.compactMap { log in
            currentDate.timeIntervalSince(log.startedAt) >= policy.maximumUnretainedLogAgeSeconds
                ? log.id
                : nil
        })
        let idsToDelete = countOverflowIDs.union(expiredIDs)

        for id in idsToDelete {
            try removeFiles(for: id, in: directoryURL)
        }
        return logs.filter { !idsToDelete.contains($0.id) }
    }

    private func fileURL(for id: UUID, in directoryURL: URL) -> URL {
        directoryURL.appending(path: id.uuidString.lowercased() + ".json")
    }

    private func removeFiles(for id: UUID, in directoryURL: URL) throws {
        for extensionName in ["json", "mov"] {
            let url = directoryURL.appending(path: id.uuidString.lowercased() + "." + extensionName)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
