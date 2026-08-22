import Foundation

nonisolated struct OfflinePackageManifest: Decodable, Equatable, Sendable {
    let formatVersion: Int
    let packageID: String
    let contentVersion: String
    let schemaVersion: Int
    let signatureAlgorithm: String
    let keyID: String
    let createdAt: String
    let minimumAppVersion: String
    let bounds: Bounds
    let sourceManifestIDs: [String]
    let files: [FileRecord]

    nonisolated struct Bounds: Decodable, Equatable, Sendable {
        let north: Double
        let south: Double
        let east: Double
        let west: Double
    }

    nonisolated struct FileRecord: Decodable, Equatable, Sendable {
        let path: String
        let byteCount: Int64
        let sha256: String
    }
}

nonisolated struct ValidatedOfflinePackage: Equatable, Sendable {
    let manifest: OfflinePackageManifest
    let directoryURL: URL
}
