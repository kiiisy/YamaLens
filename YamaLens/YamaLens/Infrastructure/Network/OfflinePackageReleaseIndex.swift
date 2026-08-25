import CryptoKit
import Foundation

nonisolated enum OfflinePackageReleaseIndexError: Error, Equatable, Sendable {
    case invalidURL
    case requestFailed
    case responseTooLarge
    case invalidResponse
    case invalidIndex
    case unsupportedSignatureAlgorithm
    case unknownSigningKey
    case invalidSignature
}

nonisolated protocol OfflinePackageSourceResolving: Sendable {
    func resolveSource() async throws -> OfflinePackageSource
}

nonisolated struct OfflinePackageReleaseIndex: Decodable, Equatable, Sendable {
    let formatVersion: Int
    let packageID: String
    let contentVersion: String
    let signatureAlgorithm: String
    let keyID: String
}

actor RemoteOfflinePackageSourceResolver: OfflinePackageSourceResolving {
    private let releaseIndexURL: URL
    private let releaseSignatureURL: URL
    private let expectedPackageID: String
    private let packageBaseURL: URL
    private let validator: OfflinePackageReleaseIndexValidator

    init(
        releaseIndexURL: URL,
        releaseSignatureURL: URL,
        expectedPackageID: String,
        packageBaseURL: URL,
        publicKeys: [String: Data]
    ) throws {
        guard Self.isAllowedURL(releaseIndexURL),
              Self.isAllowedURL(releaseSignatureURL),
              Self.isAllowedURL(packageBaseURL) else {
            throw OfflinePackageReleaseIndexError.invalidURL
        }
        self.releaseIndexURL = releaseIndexURL
        self.releaseSignatureURL = releaseSignatureURL
        self.expectedPackageID = expectedPackageID
        self.packageBaseURL = packageBaseURL
        validator = OfflinePackageReleaseIndexValidator(publicKeys: publicKeys)
    }

    func resolveSource() async throws -> OfflinePackageSource {
        async let indexData = Self.download(
            from: releaseIndexURL,
            maximumBytes: 256 * 1_024
        )
        async let signatureData = Self.download(
            from: releaseSignatureURL,
            maximumBytes: 64
        )
        let sourceIndex = try await validator.validate(
            indexData: indexData,
            signatureData: signatureData,
            expectedPackageID: expectedPackageID
        )
        let packageURL = packageBaseURL.appending(
            path: sourceIndex.contentVersion,
            directoryHint: .isDirectory
        )
        return try OfflinePackageSource(
            packageID: sourceIndex.packageID,
            baseURL: packageURL,
            expectedContentVersion: sourceIndex.contentVersion
        )
    }

    private static func download(from url: URL, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw OfflinePackageReleaseIndexError.invalidResponse
        }
        if let declaredLength = response.value(forHTTPHeaderField: "Content-Length"),
           let length = Int(declaredLength), length > maximumBytes {
            throw OfflinePackageReleaseIndexError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw OfflinePackageReleaseIndexError.responseTooLarge
            }
            data.append(byte)
        }
        return data
    }

    private static func isAllowedURL(_ url: URL) -> Bool {
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
}

nonisolated struct OfflinePackageReleaseIndexValidator: Sendable {
    private let publicKeys: [String: Data]

    init(publicKeys: [String: Data]) {
        self.publicKeys = publicKeys
    }

    func validate(
        indexData: Data,
        signatureData: Data,
        expectedPackageID: String
    ) throws -> OfflinePackageReleaseIndex {
        guard indexData.count <= 256 * 1_024,
              signatureData.count == 64 else {
            throw OfflinePackageReleaseIndexError.invalidIndex
        }
        let index: OfflinePackageReleaseIndex
        do {
            index = try JSONDecoder().decode(OfflinePackageReleaseIndex.self, from: indexData)
        } catch {
            throw OfflinePackageReleaseIndexError.invalidIndex
        }
        guard index.formatVersion == 1,
              index.packageID == expectedPackageID,
              Self.isSafeIdentifier(index.packageID),
              Self.isSemanticVersion(index.contentVersion),
              Self.isSafeIdentifier(index.keyID) else {
            throw OfflinePackageReleaseIndexError.invalidIndex
        }
        guard index.signatureAlgorithm == "Ed25519" else {
            throw OfflinePackageReleaseIndexError.unsupportedSignatureAlgorithm
        }
        guard let keyData = publicKeys[index.keyID] else {
            throw OfflinePackageReleaseIndexError.unknownSigningKey
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw OfflinePackageReleaseIndexError.unknownSigningKey
        }
        guard publicKey.isValidSignature(signatureData, for: indexData) else {
            throw OfflinePackageReleaseIndexError.invalidSignature
        }
        return index
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
