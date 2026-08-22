import Foundation

nonisolated enum OfflinePackageStoreError: Error, Equatable, Sendable {
    case invalidStagingLocation
    case versionAlreadyExists
    case invalidActiveVersion
    case invalidJournal
}

nonisolated struct InstalledOfflinePackage: Equatable, Sendable {
    let packageID: String
    let contentVersion: String
    let directoryURL: URL
}

nonisolated struct StoredOfflinePackageSummary: Equatable, Sendable {
    let packageID: String
    let contentVersion: String
    let byteCount: Int64
    let createdAt: Date
}

nonisolated enum OfflinePackageStagingState: String, Codable, Equatable, Sendable {
    case downloading
    case verifying
}

actor OfflinePackageStore {
    private let rootURL: URL
    private let validator: OfflinePackageValidator
    private let fileManager: FileManager

    init(
        rootURL: URL,
        validator: OfflinePackageValidator,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.validator = validator
        self.fileManager = fileManager
    }

    func prepareStagingDirectory(
        identifier: String,
        packageID: String? = nil
    ) throws -> URL {
        guard Self.isSafePathComponent(identifier),
              packageID.map(Self.isSafePathComponent) != false else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }
        try ensureLayout()
        let directoryURL = stagingRootURL.appending(path: identifier, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw OfflinePackageStoreError.versionAlreadyExists
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        try applyOfflinePackageAttributes(to: directoryURL)
        if let packageID {
            try writeStagingJournal(
                StagingJournal(
                    state: .downloading,
                    updatedAt: .now,
                    packageID: packageID
                ),
                to: directoryURL
            )
        }
        return directoryURL
    }

    func install(stagedPackageURL: URL) throws -> InstalledOfflinePackage {
        try ensureLayout()
        let stagedURL = stagedPackageURL.standardizedFileURL
        guard stagedURL.deletingLastPathComponent() == stagingRootURL else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }

        let validated = try validator.validatePackage(at: stagedURL)
        let manifest = validated.manifest
        try removeStagingJournal(from: stagedURL)
        try applyOfflinePackageAttributesRecursively(to: stagedURL)

        let packageRoot = installedRootURL
            .appending(path: manifest.packageID, directoryHint: .isDirectory)
        let versionsRoot = packageRoot.appending(path: "Versions", directoryHint: .isDirectory)
        try createProtectedDirectoryIfNeeded(packageRoot)
        try createProtectedDirectoryIfNeeded(versionsRoot)

        let versionURL = versionsRoot.appending(
            path: manifest.contentVersion,
            directoryHint: .isDirectory
        )
        guard !fileManager.fileExists(atPath: versionURL.path) else {
            throw OfflinePackageStoreError.versionAlreadyExists
        }

        let journal = InstallJournal(
            packageID: manifest.packageID,
            contentVersion: manifest.contentVersion,
            state: .readyToInstall
        )
        try writeJournal(journal, to: packageRoot)
        try fileManager.moveItem(at: stagedURL, to: versionURL)
        do {
            _ = try validator.validatePackage(at: versionURL)
            try writeActiveVersion(manifest.contentVersion, to: packageRoot)
            try removeJournal(from: packageRoot)
        } catch {
            // active-versionは最後にだけ置換するため、失敗時も直前版を参照し続ける。
            throw error
        }
        return InstalledOfflinePackage(
            packageID: manifest.packageID,
            contentVersion: manifest.contentVersion,
            directoryURL: versionURL
        )
    }

    func setStagingState(
        _ state: OfflinePackageStagingState,
        for directoryURL: URL
    ) throws {
        let stagedURL = directoryURL.standardizedFileURL
        guard stagedURL.deletingLastPathComponent() == stagingRootURL,
              fileManager.fileExists(atPath: stagedURL.path) else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }
        let existingJournal = try readStagingJournal(from: stagedURL)
        try writeStagingJournal(
            StagingJournal(
                state: state,
                updatedAt: .now,
                packageID: existingJournal?.packageID
            ),
            to: stagedURL
        )
    }

    func resumableStagingDirectory(packageID: String) throws -> URL? {
        guard Self.isSafePathComponent(packageID) else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }
        try ensureLayout()
        let entries = try fileManager.contentsOfDirectory(
            at: stagingRootURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var candidates: [(url: URL, updatedAt: Date)] = []
        for entry in entries {
            guard Self.isSafePathComponent(entry.lastPathComponent) else { continue }
            let values = try entry.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let journal = try readStagingJournal(from: entry),
                  journal.packageID == packageID else {
                continue
            }
            candidates.append((entry, journal.updatedAt))
        }
        return candidates.max(by: { $0.updatedAt < $1.updatedAt })?.url
    }

    func discardStagingDirectory(_ directoryURL: URL) throws {
        let stagedURL = directoryURL.standardizedFileURL
        guard stagedURL.deletingLastPathComponent() == stagingRootURL else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }
        guard fileManager.fileExists(atPath: stagedURL.path) else { return }
        try fileManager.removeItem(at: stagedURL)
    }

    func discardOrphanedStagingDirectories(
        olderThan cutoff: Date,
        preserving preservedIdentifiers: Set<String>
    ) throws -> Int {
        try ensureLayout()
        let entries = try fileManager.contentsOfDirectory(
            at: stagingRootURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var removedCount = 0
        for entry in entries {
            let identifier = entry.lastPathComponent
            guard Self.isSafePathComponent(identifier),
                  !preservedIdentifiers.contains(identifier) else {
                continue
            }
            let values = try entry.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let updatedAt = try stagingUpdatedAt(
                    directoryURL: entry,
                    fallback: values.contentModificationDate
                  ),
                  updatedAt < cutoff else {
                continue
            }
            try fileManager.removeItem(at: entry)
            removedCount += 1
        }
        return removedCount
    }

    func activePackageURL(packageID: String) throws -> URL? {
        guard Self.isSafePathComponent(packageID) else {
            throw OfflinePackageStoreError.invalidActiveVersion
        }
        let packageRoot = installedRootURL.appending(path: packageID, directoryHint: .isDirectory)
        let markerURL = packageRoot.appending(path: "active-version")
        guard fileManager.fileExists(atPath: markerURL.path) else { return nil }
        let markerData = try Data(contentsOf: markerURL)
        guard markerData.count <= 64,
              let version = String(data: markerData, encoding: .utf8),
              Self.isSafePathComponent(version) else {
            throw OfflinePackageStoreError.invalidActiveVersion
        }
        let versionURL = packageRoot
            .appending(path: "Versions", directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: versionURL.path) else {
            throw OfflinePackageStoreError.invalidActiveVersion
        }
        return versionURL
    }

    func activePackageSummary(packageID: String) throws -> StoredOfflinePackageSummary? {
        guard let packageURL = try activePackageURL(packageID: packageID) else { return nil }
        let manifestURL = packageURL.appending(path: "manifest.json")
        let manifestSize = try regularFileSize(at: manifestURL, named: "manifest.json")
        guard manifestSize <= 256 * 1_024 else {
            throw OfflinePackageValidationError.manifestTooLarge
        }
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let manifest: OfflinePackageManifest
        do {
            manifest = try JSONDecoder().decode(OfflinePackageManifest.self, from: manifestData)
        } catch {
            throw OfflinePackageValidationError.invalidManifest
        }
        guard manifest.packageID == packageID,
              manifest.contentVersion == packageURL.lastPathComponent,
              let createdAt = ISO8601DateFormatter().date(from: manifest.createdAt) else {
            throw OfflinePackageValidationError.invalidManifest
        }
        var byteCount: Int64 = 0
        for file in manifest.files {
            let (newValue, overflowed) = byteCount.addingReportingOverflow(file.byteCount)
            guard file.byteCount > 0,
                  !overflowed,
                  newValue <= 1_000_000_000 else {
                throw OfflinePackageValidationError.packageTooLarge
            }
            byteCount = newValue
        }
        return StoredOfflinePackageSummary(
            packageID: packageID,
            contentVersion: manifest.contentVersion,
            byteCount: byteCount,
            createdAt: createdAt
        )
    }

    func deletePackage(packageID: String) throws {
        guard Self.isSafePathComponent(packageID) else {
            throw OfflinePackageStoreError.invalidActiveVersion
        }
        let packageURL = installedRootURL.appending(
            path: packageID,
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: packageURL.path) else { return }
        try fileManager.removeItem(at: packageURL)
    }

    func recoverPendingInstall(packageID: String) throws -> InstalledOfflinePackage? {
        guard Self.isSafePathComponent(packageID) else {
            throw OfflinePackageStoreError.invalidJournal
        }
        try ensureLayout()
        let packageRoot = installedRootURL.appending(path: packageID, directoryHint: .isDirectory)
        let journalURL = packageRoot.appending(path: "install-journal.json")
        guard fileManager.fileExists(atPath: journalURL.path) else { return nil }

        let journalData = try Data(contentsOf: journalURL)
        let journal: InstallJournal
        do {
            journal = try JSONDecoder().decode(InstallJournal.self, from: journalData)
        } catch {
            throw OfflinePackageStoreError.invalidJournal
        }
        guard journal.packageID == packageID,
              journal.state == .readyToInstall,
              Self.isSafePathComponent(journal.contentVersion) else {
            throw OfflinePackageStoreError.invalidJournal
        }
        let versionURL = packageRoot
            .appending(path: "Versions", directoryHint: .isDirectory)
            .appending(path: journal.contentVersion, directoryHint: .isDirectory)
        let validated = try validator.validatePackage(at: versionURL)
        guard validated.manifest.packageID == packageID,
              validated.manifest.contentVersion == journal.contentVersion else {
            throw OfflinePackageStoreError.invalidJournal
        }
        try applyOfflinePackageAttributesRecursively(to: versionURL)
        try writeActiveVersion(journal.contentVersion, to: packageRoot)
        try removeJournal(from: packageRoot)
        return InstalledOfflinePackage(
            packageID: packageID,
            contentVersion: journal.contentVersion,
            directoryURL: versionURL
        )
    }

    private var stagingRootURL: URL {
        rootURL.appending(path: "Staging", directoryHint: .isDirectory)
    }

    private var installedRootURL: URL {
        rootURL.appending(path: "Installed", directoryHint: .isDirectory)
    }

    private func ensureLayout() throws {
        try createProtectedDirectoryIfNeeded(rootURL)
        try createProtectedDirectoryIfNeeded(stagingRootURL)
        try createProtectedDirectoryIfNeeded(installedRootURL)
    }

    private func createProtectedDirectoryIfNeeded(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try applyOfflinePackageAttributes(to: url)
    }

    private func applyOfflinePackageAttributesRecursively(to root: URL) throws {
        try applyOfflinePackageAttributes(to: root)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw OfflinePackageValidationError.invalidFileType(url.lastPathComponent)
            }
            try applyOfflinePackageAttributes(to: url)
        }
    }

    private func applyOfflinePackageAttributes(to url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func writeActiveVersion(_ version: String, to packageRoot: URL) throws {
        guard let data = version.data(using: .utf8) else {
            throw OfflinePackageStoreError.invalidActiveVersion
        }
        let markerURL = packageRoot.appending(path: "active-version")
        try data.write(to: markerURL, options: [.atomic])
        try applyOfflinePackageAttributes(to: markerURL)
    }

    private func writeJournal(_ journal: InstallJournal, to packageRoot: URL) throws {
        let data = try JSONEncoder().encode(journal)
        let journalURL = packageRoot.appending(path: "install-journal.json")
        try data.write(to: journalURL, options: [.atomic])
        try applyOfflinePackageAttributes(to: journalURL)
    }

    private func removeJournal(from packageRoot: URL) throws {
        let journalURL = packageRoot.appending(path: "install-journal.json")
        if fileManager.fileExists(atPath: journalURL.path) {
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func removeStagingJournal(from stagedURL: URL) throws {
        let journalURL = stagedURL.appending(path: "staging-journal.json")
        if fileManager.fileExists(atPath: journalURL.path) {
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func stagingUpdatedAt(
        directoryURL: URL,
        fallback: Date?
    ) throws -> Date? {
        let journalURL = directoryURL.appending(path: "staging-journal.json")
        guard fileManager.fileExists(atPath: journalURL.path) else { return fallback }
        let size = try regularFileSize(at: journalURL, named: "staging-journal.json")
        guard size <= 4_096 else { return fallback }
        let data = try Data(contentsOf: journalURL)
        do {
            return try JSONDecoder().decode(StagingJournal.self, from: data).updatedAt
        } catch {
            // 壊れた一時journalは実データとして使わず、ディレクトリ更新日時で保守的に判定する。
            return fallback
        }
    }

    private func readStagingJournal(from directoryURL: URL) throws -> StagingJournal? {
        let journalURL = directoryURL.appending(path: "staging-journal.json")
        guard fileManager.fileExists(atPath: journalURL.path) else { return nil }
        let size = try regularFileSize(at: journalURL, named: "staging-journal.json")
        guard size <= 4_096 else { return nil }
        let data = try Data(contentsOf: journalURL)
        do {
            return try JSONDecoder().decode(StagingJournal.self, from: data)
        } catch {
            return nil
        }
    }

    private func writeStagingJournal(
        _ journal: StagingJournal,
        to directoryURL: URL
    ) throws {
        let data = try JSONEncoder().encode(journal)
        let journalURL = directoryURL.appending(path: "staging-journal.json")
        try data.write(to: journalURL, options: [.atomic])
        try applyOfflinePackageAttributes(to: journalURL)
    }

    private func regularFileSize(at fileURL: URL, named fileName: String) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize >= 0 else {
            throw OfflinePackageValidationError.invalidFileType(fileName)
        }
        return Int64(fileSize)
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && value != "."
    }
}

private nonisolated struct InstallJournal: Codable, Sendable {
    let packageID: String
    let contentVersion: String
    let state: State

    nonisolated enum State: String, Codable, Sendable {
        case readyToInstall
    }
}

private nonisolated struct StagingJournal: Codable, Sendable {
    let state: OfflinePackageStagingState
    let updatedAt: Date
    let packageID: String?
}
