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

    func prepareStagingDirectory(identifier: String) throws -> URL {
        guard Self.isSafePathComponent(identifier) else {
            throw OfflinePackageStoreError.invalidStagingLocation
        }
        try ensureLayout()
        let directoryURL = stagingRootURL.appending(path: identifier, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            throw OfflinePackageStoreError.versionAlreadyExists
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        try applyOfflinePackageAttributes(to: directoryURL)
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
