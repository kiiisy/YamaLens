import CryptoKit
import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageValidatorTests {
    @Test("署名・ハッシュ・SQLite・LZFSE地形が正しいパックを受理する")
    func acceptsValidPackage() throws {
        let root = try makeTemporaryDirectory(named: "valid")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        let validated = try validator.validatePackage(at: fixture.directoryURL)

        #expect(validated.manifest.packageID == "jp.kanagawa.tanzawa")
        #expect(validated.manifest.contentVersion == "1.0.0")
    }

    @Test("未知の署名鍵を拒否する")
    func rejectsUnknownSigningKey() throws {
        let root = try makeTemporaryDirectory(named: "unknown-key")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        let validator = OfflinePackageValidator(publicKeys: [:])

        #expect(throws: OfflinePackageValidationError.unknownSigningKey) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("manifestの生バイトに一致しない署名を拒否する")
    func rejectsInvalidSignature() throws {
        let root = try makeTemporaryDirectory(named: "invalid-signature")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        try Data(repeating: 0, count: 64).write(to: fixture.signatureURL)
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.invalidSignature) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("宣言されたSHA-256と異なるファイルを拒否する")
    func rejectsFileHashMismatch() throws {
        let root = try makeTemporaryDirectory(named: "hash-mismatch")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        var terrain = try Data(contentsOf: fixture.terrainURL)
        terrain.append(0)
        try terrain.write(to: fixture.terrainURL)
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.fileSizeMismatch("terrain.lzfse")) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("地形headerの未知のflagsを署名済みでも拒否する")
    func rejectsUnknownTerrainFlags() throws {
        let root = try makeTemporaryDirectory(named: "terrain-flags")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        var terrain = try Data(contentsOf: fixture.terrainURL)
        terrain[12] = 1
        try terrain.write(to: fixture.terrainURL)
        try fixture.rewriteManifestAndSignature()
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.unsupportedTerrainFlags) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("対応アプリ版より新しいパックを拒否する")
    func rejectsUnsupportedMinimumAppVersion() throws {
        let root = try makeTemporaryDirectory(named: "minimum-app-version")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        try rewriteSignedManifest(fixture) { manifest in
            manifest["minimumAppVersion"] = "9.0.0"
        }
        let validator = OfflinePackageValidator(
            publicKeys: fixture.publicKeys,
            appVersion: "0.1.0"
        )

        #expect(throws: OfflinePackageValidationError.minimumAppVersionUnsupported) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("パス移動を含む未知のファイル名を拒否する")
    func rejectsUnsafeFilePath() throws {
        let root = try makeTemporaryDirectory(named: "unsafe-path")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        try rewriteSignedManifest(fixture) { manifest in
            guard var files = manifest["files"] as? [[String: Any]] else { return }
            files[1]["path"] = "../terrain.lzfse"
            manifest["files"] = files
        }
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.invalidFileList) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("256KiBを超えるmanifestを読み込まない")
    func rejectsOversizedManifest() throws {
        let root = try makeTemporaryDirectory(named: "oversized-manifest")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        try Data(repeating: 0, count: 256 * 1_024 + 1).write(to: fixture.manifestURL)
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.manifestTooLarge) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    @Test("圧縮済み地形タイルの上限超過を展開前に拒否する")
    func rejectsOversizedCompressedTileDeclaration() throws {
        let root = try makeTemporaryDirectory(named: "oversized-tile")
        defer { removeTemporaryDirectory(root) }
        let fixture = try OfflinePackageFixture.make(at: root.appending(path: "package"))
        try fixture.executeCatalogSQL(
            "UPDATE terrain_tiles SET compressed_bytes = 262145 WHERE id = 'tile-1';"
        )
        try fixture.rewriteManifestAndSignature()
        let validator = OfflinePackageValidator(publicKeys: fixture.publicKeys)

        #expect(throws: OfflinePackageValidationError.invalidTerrainTile("tile-1")) {
            try validator.validatePackage(at: fixture.directoryURL)
        }
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensOfflinePackageValidatorTests")
            .appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        // テスト専用領域の後始末であり、失敗しても検証結果へ影響しない。
        try? FileManager.default.removeItem(at: url)
    }

    private func rewriteSignedManifest(
        _ fixture: OfflinePackageFixture,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        let existing = try Data(contentsOf: fixture.manifestURL)
        guard var manifest = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
            throw TestFixtureMutationError.invalidManifest
        }
        mutation(&manifest)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: fixture.manifestURL)
        try fixture.privateKey.signature(for: data).write(to: fixture.signatureURL)
    }

    private enum TestFixtureMutationError: Error {
        case invalidManifest
    }
}
