import Compression
import CryptoKit
import Foundation
import SQLite3

struct OfflinePackageFixture {
    let directoryURL: URL
    let privateKey: Curve25519.Signing.PrivateKey
    let packageID = "jp.kanagawa.tanzawa"
    let keyID = "test-key-1"
    let contentVersion: String

    var publicKeys: [String: Data] {
        [keyID: privateKey.publicKey.rawRepresentation]
    }

    static func make(at directoryURL: URL, contentVersion: String = "1.0.0") throws -> Self {
        let privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data((1...32).map(UInt8.init))
        )
        let fixture = Self(
            directoryURL: directoryURL,
            privateKey: privateKey,
            contentVersion: contentVersion
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let uncompressed = Data(repeating: 0, count: 256 * 256 * MemoryLayout<Int16>.size)
        let compressed = try compressLZFSE(uncompressed)
        var terrain = Data("YLTF".utf8)
        appendLittleEndianUInt16(1, to: &terrain)
        appendLittleEndianUInt16(16, to: &terrain)
        appendLittleEndianUInt32(1, to: &terrain)
        appendLittleEndianUInt32(0, to: &terrain)
        terrain.append(compressed)
        try terrain.write(to: fixture.terrainURL)
        try fixture.createCatalog(
            compressedBytes: compressed.count,
            uncompressedHash: sha256Hex(uncompressed)
        )
        try fixture.rewriteManifestAndSignature()
        return fixture
    }

    var manifestURL: URL { directoryURL.appending(path: "manifest.json") }
    var signatureURL: URL { directoryURL.appending(path: "manifest.sig") }
    var catalogURL: URL { directoryURL.appending(path: "catalog.sqlite") }
    var terrainURL: URL { directoryURL.appending(path: "terrain.lzfse") }

    func rewriteManifestAndSignature() throws {
        let files: [[String: Any]] = [
            fileRecord(path: "catalog.sqlite", url: catalogURL),
            fileRecord(path: "terrain.lzfse", url: terrainURL),
        ]
        let object: [String: Any] = [
            "formatVersion": 1,
            "packageID": packageID,
            "contentVersion": contentVersion,
            "schemaVersion": 1,
            "signatureAlgorithm": "Ed25519",
            "keyID": keyID,
            "createdAt": "2026-08-22T00:00:00Z",
            "minimumAppVersion": "0.1.0",
            "bounds": [
                "north": 35.9,
                "south": 34.8,
                "east": 139.4,
                "west": 138.7,
            ],
            "sourceManifestIDs": ["test-source-v1"],
            "files": files,
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL)
        try privateKey.signature(for: manifestData).write(to: signatureURL)
    }

    func executeCatalogSQL(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(catalogURL.path, &database) == SQLITE_OK, let database else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
    }

    private func createCatalog(compressedBytes: Int, uncompressedHash: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(catalogURL.path, &database) == SQLITE_OK, let database else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let schema = """
        PRAGMA foreign_keys=ON;
        CREATE TABLE package_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE regions(id TEXT PRIMARY KEY, name TEXT NOT NULL, prefecture_name TEXT NOT NULL);
        CREATE TABLE mountains(id TEXT PRIMARY KEY, region_id TEXT NOT NULL REFERENCES regions(id), canonical_name TEXT NOT NULL, search_name TEXT NOT NULL, coverage_role TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, elevation_m INTEGER NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE mountain_names(mountain_id TEXT NOT NULL REFERENCES mountains(id), name TEXT NOT NULL, search_name TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(mountain_id, name));
        CREATE TABLE points_of_interest(id TEXT PRIMARY KEY, region_id TEXT NOT NULL REFERENCES regions(id), type TEXT NOT NULL, name TEXT NOT NULL);
        CREATE TABLE mountain_points_of_interest(mountain_id TEXT NOT NULL REFERENCES mountains(id), point_of_interest_id TEXT NOT NULL REFERENCES points_of_interest(id), PRIMARY KEY(mountain_id, point_of_interest_id));
        CREATE TABLE source_links(id TEXT PRIMARY KEY, provider TEXT NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, checked_at TEXT NOT NULL, is_primary INTEGER NOT NULL, attribution_text TEXT NOT NULL);
        CREATE TABLE entity_sources(entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES source_links(id), PRIMARY KEY(entity_type, entity_id, source_id));
        CREATE TABLE terrain_tiles(id TEXT PRIMARY KEY, north REAL NOT NULL, south REAL NOT NULL, east REAL NOT NULL, west REAL NOT NULL, resolution_m REAL NOT NULL, row_count INTEGER NOT NULL, column_count INTEGER NOT NULL, offset_bytes INTEGER NOT NULL, compressed_bytes INTEGER NOT NULL, uncompressed_bytes INTEGER NOT NULL, sha256 TEXT NOT NULL);
        INSERT INTO package_metadata VALUES('schema_version', '1');
        INSERT INTO package_metadata VALUES('content_version', '\(contentVersion)');
        INSERT INTO package_metadata VALUES('package_id', '\(packageID)');
        INSERT INTO regions VALUES('jp.kanagawa.tanzawa', '丹沢山地', '神奈川県');
        INSERT INTO mountains VALUES('塔ノ岳', 'jp.kanagawa.tanzawa', '塔ノ岳', 'とうのだけ', 'core', 35.4743, 139.1486, 1491, '2026-08-22T00:00:00Z');
        INSERT INTO mountain_names VALUES('塔ノ岳', '塔ノ岳', 'とうのだけ', 'canonical');
        INSERT INTO terrain_tiles VALUES('tile-1', 35.5, 35.4, 139.2, 139.1, 10, 256, 256, 16, \(compressedBytes), 131072, '\(uncompressedHash)');
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
    }

    private func fileRecord(path: String, url: URL) -> [String: Any] {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return [
            "path": path,
            "byteCount": data.count,
            "sha256": Self.sha256Hex(data),
        ]
    }

    private static func compressLZFSE(_ source: Data) throws -> Data {
        var destination = [UInt8](repeating: 0, count: source.count + 1_024)
        let encodedCount = source.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard
                    let sourceAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                    let destinationAddress = destinationBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                return compression_encode_buffer(
                    destinationAddress,
                    destinationBuffer.count,
                    sourceAddress,
                    sourceBuffer.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard encodedCount > 0 else { throw FixtureError.compression }
        return Data(destination.prefix(encodedCount))
    }

    private static func appendLittleEndianUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendLittleEndianUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum FixtureError: Error {
        case compression
        case sqlite
    }
}
