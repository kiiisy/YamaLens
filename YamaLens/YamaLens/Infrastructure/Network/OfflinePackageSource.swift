import Foundation

nonisolated enum OfflinePackageSourceError: Error, Equatable, Sendable {
    case invalidPackageID
    case invalidBaseURL
    case URLTooLong
}

nonisolated struct OfflinePackageSource: Equatable, Sendable {
    let packageID: String
    let baseURL: URL

    init(packageID: String, baseURL: URL) throws {
        guard Self.isSafeIdentifier(packageID) else {
            throw OfflinePackageSourceError.invalidPackageID
        }
        guard Self.isAllowed(url: baseURL) else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        guard baseURL.absoluteString.utf8.count <= 2_048 else {
            throw OfflinePackageSourceError.URLTooLong
        }
        self.packageID = packageID
        self.baseURL = baseURL
    }

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
        guard Self.isAllowed(url: url) else {
            throw OfflinePackageSourceError.invalidBaseURL
        }
        guard url.absoluteString.utf8.count <= 2_048 else {
            throw OfflinePackageSourceError.URLTooLong
        }
        return url
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

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
        )
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && value != "."
    }
}
