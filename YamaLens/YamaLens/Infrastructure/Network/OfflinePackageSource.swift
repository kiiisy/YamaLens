import Foundation

nonisolated enum OfflinePackageSourceError: Error, Equatable, Sendable {
    case invalidPackageID
    case invalidBaseURL
    case URLTooLong
}

nonisolated struct OfflinePackageSource: Equatable, Sendable {
    let packageID: String
    let baseURL: URL
    let expectedContentVersion: String?
    private let allowsDevelopmentBundleURL: Bool

    init(
        packageID: String,
        baseURL: URL,
        expectedContentVersion: String? = nil
    ) throws {
        guard Self.isSafeIdentifier(packageID) else {
            throw OfflinePackageSourceError.invalidPackageID
        }
        guard Self.isAllowed(url: baseURL) else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        guard baseURL.absoluteString.utf8.count <= 2_048 else {
            throw OfflinePackageSourceError.URLTooLong
        }
        guard expectedContentVersion.map(Self.isSemanticVersion) ?? true else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        self.packageID = packageID
        self.baseURL = baseURL
        self.expectedContentVersion = expectedContentVersion
        allowsDevelopmentBundleURL = false
    }

#if DEBUG
    static func developmentBundle(
        packageID: String,
        directoryURL: URL
    ) throws -> Self {
        guard Self.isSafeIdentifier(packageID) else {
            throw OfflinePackageSourceError.invalidPackageID
        }
        let standardizedURL = directoryURL.standardizedFileURL
        guard standardizedURL.isFileURL,
              standardizedURL.absoluteString.utf8.count <= 2_048 else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        return Self(
            packageID: packageID,
            baseURL: standardizedURL,
            expectedContentVersion: nil,
            allowsDevelopmentBundleURL: true
        )
    }
#endif

    func urlForFile(named fileName: String) throws -> URL {
        let allowedNames = [
            "manifest.json",
            "manifest.sig",
            "catalog.sqlite",
            "terrain.lzfse",
        ]
        guard allowedNames.contains(fileName) else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        let url = baseURL.appending(path: fileName, directoryHint: .notDirectory)
        let isAllowedURL = allowsDevelopmentBundleURL
            ? Self.isAllowedDevelopmentBundleURL(url, below: baseURL)
            : Self.isAllowed(url: url)
        guard isAllowedURL else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        guard url.absoluteString.utf8.count <= 2_048 else {
            throw OfflinePackageSourceError.URLTooLong
        }
        return url
    }

    private init(
        packageID: String,
        baseURL: URL,
        expectedContentVersion: String?,
        allowsDevelopmentBundleURL: Bool
    ) {
        self.packageID = packageID
        self.baseURL = baseURL
        self.expectedContentVersion = expectedContentVersion
        self.allowsDevelopmentBundleURL = allowsDevelopmentBundleURL
    }

    private static func isAllowed(url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }

    private static func isAllowedDevelopmentBundleURL(
        _ url: URL,
        below directoryURL: URL
    ) -> Bool {
        url.isFileURL
            && url.standardizedFileURL.deletingLastPathComponent()
                == directoryURL.standardizedFileURL
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && value != "."
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }
}
