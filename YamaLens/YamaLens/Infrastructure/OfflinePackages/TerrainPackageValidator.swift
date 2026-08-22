import Compression
import CryptoKit
import Foundation
import SQLite3

nonisolated enum OfflinePackageValidationError: Error, Equatable, Sendable {
    case missingFile(String)
    case invalidFileType(String)
    case manifestTooLarge
    case invalidManifest
    case unsupportedFormatVersion
    case unsupportedSchemaVersion
    case minimumAppVersionUnsupported
    case unsupportedSignatureAlgorithm
    case unknownSigningKey
    case invalidSignature
    case invalidFileList
    case invalidDeclaredSize
    case packageTooLarge
    case fileSizeMismatch(String)
    case fileHashMismatch(String)
    case invalidCatalog
    case invalidTerrainHeader
    case unsupportedTerrainVersion
    case unsupportedTerrainFlags
    case invalidTerrainTile(String)
}

nonisolated struct OfflinePackageValidator: Sendable {
    private enum Limits {
        static let maximumManifestBytes = 256 * 1_024
        static let signatureBytes = 64
        static let maximumPackageBytes: Int64 = 1_000_000_000
        static let terrainHeaderBytes = 16
        static let terrainTileBytes = 256 * 256 * MemoryLayout<Int16>.size
        static let maximumCompressedTileBytes = 262_144
        static let maximumTerrainTiles = 100_000
        static let maximumSourceManifestIDs = 128
    }

    private let publicKeys: [String: Data]
    private let appVersion: String

    init(publicKeys: [String: Data], appVersion: String = "0.1.0") {
        self.publicKeys = publicKeys
        self.appVersion = appVersion
    }

    func validatePackage(at directoryURL: URL) throws -> ValidatedOfflinePackage {
        let manifestURL = directoryURL.appending(path: "manifest.json")
        let signatureURL = directoryURL.appending(path: "manifest.sig")
        let manifestData = try readRegularFile(
            at: manifestURL,
            named: "manifest.json",
            maximumBytes: Limits.maximumManifestBytes
        )
        let signatureData = try readRegularFile(
            at: signatureURL,
            named: "manifest.sig",
            maximumBytes: Limits.signatureBytes
        )
        guard signatureData.count == Limits.signatureBytes else {
            throw OfflinePackageValidationError.invalidSignature
        }

        let manifest = try decodeAndValidateManifest(manifestData)
        try validateSignature(signatureData, manifestData: manifestData, manifest: manifest)
        try validateFiles(in: directoryURL, manifest: manifest)

        let catalogURL = directoryURL.appending(path: "catalog.sqlite")
        let terrainURL = directoryURL.appending(path: "terrain.lzfse")
        let catalog = try validateCatalog(at: catalogURL, manifest: manifest)
        try validateTerrain(at: terrainURL, tiles: catalog.tiles)
        return ValidatedOfflinePackage(manifest: manifest, directoryURL: directoryURL)
    }

    private func decodeAndValidateManifest(_ data: Data) throws -> OfflinePackageManifest {
        let manifest: OfflinePackageManifest
        do {
            manifest = try JSONDecoder().decode(OfflinePackageManifest.self, from: data)
        } catch {
            throw OfflinePackageValidationError.invalidManifest
        }
        guard manifest.formatVersion == 1 else {
            throw OfflinePackageValidationError.unsupportedFormatVersion
        }
        guard manifest.schemaVersion == 1 else {
            throw OfflinePackageValidationError.unsupportedSchemaVersion
        }
        guard let minimumVersion = semanticVersionParts(manifest.minimumAppVersion),
              let supportedVersion = semanticVersionParts(appVersion) else {
            throw OfflinePackageValidationError.invalidManifest
        }
        guard !minimumVersion.lexicographicallyPrecedes(supportedVersion, by: >) else {
            throw OfflinePackageValidationError.minimumAppVersionUnsupported
        }
        guard manifest.signatureAlgorithm == "Ed25519" else {
            throw OfflinePackageValidationError.unsupportedSignatureAlgorithm
        }
        guard
            isSafeIdentifier(manifest.packageID, maximumLength: 128),
            isSemanticVersion(manifest.contentVersion),
            isSafeIdentifier(manifest.keyID, maximumLength: 128),
            ISO8601DateFormatter().date(from: manifest.createdAt) != nil,
            manifest.bounds.north.isFinite,
            manifest.bounds.south.isFinite,
            manifest.bounds.east.isFinite,
            manifest.bounds.west.isFinite,
            (-90...90).contains(manifest.bounds.north),
            (-90...90).contains(manifest.bounds.south),
            (-180...180).contains(manifest.bounds.east),
            (-180...180).contains(manifest.bounds.west),
            manifest.bounds.north > manifest.bounds.south,
            manifest.bounds.east > manifest.bounds.west,
            !manifest.sourceManifestIDs.isEmpty,
            manifest.sourceManifestIDs.count <= Limits.maximumSourceManifestIDs,
            manifest.sourceManifestIDs.allSatisfy({ isSafeIdentifier($0, maximumLength: 128) })
        else {
            throw OfflinePackageValidationError.invalidManifest
        }
        return manifest
    }

    private func validateSignature(
        _ signature: Data,
        manifestData: Data,
        manifest: OfflinePackageManifest
    ) throws {
        guard let keyData = publicKeys[manifest.keyID] else {
            throw OfflinePackageValidationError.unknownSigningKey
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw OfflinePackageValidationError.unknownSigningKey
        }
        guard publicKey.isValidSignature(signature, for: manifestData) else {
            throw OfflinePackageValidationError.invalidSignature
        }
    }

    private func validateFiles(
        in directoryURL: URL,
        manifest: OfflinePackageManifest
    ) throws {
        let expectedPaths = Set(["catalog.sqlite", "terrain.lzfse"])
        let declaredPaths = Set(manifest.files.map(\.path))
        guard manifest.files.count == 2, declaredPaths == expectedPaths else {
            throw OfflinePackageValidationError.invalidFileList
        }

        var totalBytes: Int64 = 0
        for record in manifest.files {
            guard record.byteCount > 0, isLowercaseSHA256(record.sha256) else {
                throw OfflinePackageValidationError.invalidDeclaredSize
            }
            let (newTotal, overflowed) = totalBytes.addingReportingOverflow(record.byteCount)
            guard !overflowed, newTotal <= Limits.maximumPackageBytes else {
                throw OfflinePackageValidationError.packageTooLarge
            }
            totalBytes = newTotal

            let fileURL = directoryURL.appending(path: record.path)
            let size = try regularFileSize(at: fileURL, named: record.path)
            guard size == record.byteCount else {
                throw OfflinePackageValidationError.fileSizeMismatch(record.path)
            }
            guard try sha256Hex(of: fileURL, maximumBytes: record.byteCount) == record.sha256 else {
                throw OfflinePackageValidationError.fileHashMismatch(record.path)
            }
        }
    }

    private func validateCatalog(
        at databaseURL: URL,
        manifest: OfflinePackageManifest
    ) throws -> CatalogValidationResult {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(
            database,
            "PRAGMA query_only=ON; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF;",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        guard try singleText("PRAGMA integrity_check;", database: database) == "ok" else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        guard try rowCount("PRAGMA foreign_key_check;", database: database) == 0 else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        guard
            try metadata("schema_version", database: database) == String(manifest.schemaVersion),
            try metadata("content_version", database: database) == manifest.contentVersion,
            try metadata("package_id", database: database) == manifest.packageID,
            try requiredTablesExist(database: database),
            try rowCount("SELECT 1 FROM mountains LIMIT 1;", database: database) == 1
        else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        return CatalogValidationResult(tiles: try loadTiles(database: database))
    }

    private func validateTerrain(at terrainURL: URL, tiles: [TerrainTileRecord]) throws {
        let fileSize = try regularFileSize(at: terrainURL, named: "terrain.lzfse")
        guard fileSize >= Int64(Limits.terrainHeaderBytes) else {
            throw OfflinePackageValidationError.invalidTerrainHeader
        }
        let file = try FileHandle(forReadingFrom: terrainURL)
        defer { try? file.close() }
        let header = try file.read(upToCount: Limits.terrainHeaderBytes) ?? Data()
        let bytes = [UInt8](header)
        guard bytes.count == Limits.terrainHeaderBytes, Array(bytes[0..<4]) == Array("YLTF".utf8) else {
            throw OfflinePackageValidationError.invalidTerrainHeader
        }
        guard littleEndianUInt16(bytes, offset: 4) == 1 else {
            throw OfflinePackageValidationError.unsupportedTerrainVersion
        }
        guard littleEndianUInt16(bytes, offset: 6) == UInt16(Limits.terrainHeaderBytes) else {
            throw OfflinePackageValidationError.invalidTerrainHeader
        }
        guard littleEndianUInt32(bytes, offset: 12) == 0 else {
            throw OfflinePackageValidationError.unsupportedTerrainFlags
        }
        guard !tiles.isEmpty,
              tiles.count <= Limits.maximumTerrainTiles,
              littleEndianUInt32(bytes, offset: 8) == UInt32(tiles.count) else {
            throw OfflinePackageValidationError.invalidTerrainHeader
        }

        var previousEndOffset = Int64(Limits.terrainHeaderBytes)
        for tile in tiles {
            guard
                tile.rowCount == 256,
                tile.columnCount == 256,
                tile.uncompressedBytes == Limits.terrainTileBytes,
                tile.offsetBytes >= Int64(Limits.terrainHeaderBytes),
                tile.offsetBytes >= previousEndOffset,
                tile.compressedBytes > 0,
                tile.compressedBytes <= Limits.maximumCompressedTileBytes,
                isLowercaseSHA256(tile.sha256)
            else {
                throw OfflinePackageValidationError.invalidTerrainTile(tile.id)
            }
            let (endOffset, overflowed) = tile.offsetBytes.addingReportingOverflow(
                Int64(tile.compressedBytes)
            )
            guard !overflowed, endOffset <= fileSize else {
                throw OfflinePackageValidationError.invalidTerrainTile(tile.id)
            }
            previousEndOffset = endOffset
            try file.seek(toOffset: UInt64(tile.offsetBytes))
            let compressed = try file.read(upToCount: tile.compressedBytes) ?? Data()
            guard compressed.count == tile.compressedBytes else {
                throw OfflinePackageValidationError.invalidTerrainTile(tile.id)
            }
            var decoded = [UInt8](repeating: 0, count: Limits.terrainTileBytes)
            let decodedCount = compressed.withUnsafeBytes { source in
                decoded.withUnsafeMutableBytes { destination in
                    guard
                        let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress,
                        let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress
                    else {
                        return 0
                    }
                    return compression_decode_buffer(
                        destinationAddress,
                        destination.count,
                        sourceAddress,
                        source.count,
                        nil,
                        COMPRESSION_LZFSE
                    )
                }
            }
            guard decodedCount == Limits.terrainTileBytes else {
                throw OfflinePackageValidationError.invalidTerrainTile(tile.id)
            }
            let hash = SHA256.hash(data: Data(decoded))
            guard hash.map({ String(format: "%02x", $0) }).joined() == tile.sha256 else {
                throw OfflinePackageValidationError.invalidTerrainTile(tile.id)
            }
        }
    }

    private func readRegularFile(
        at url: URL,
        named name: String,
        maximumBytes: Int
    ) throws -> Data {
        let size = try regularFileSize(at: url, named: name)
        guard size <= maximumBytes else {
            if name == "manifest.json" {
                throw OfflinePackageValidationError.manifestTooLarge
            }
            throw OfflinePackageValidationError.invalidSignature
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw OfflinePackageValidationError.missingFile(name)
        }
    }

    private func regularFileSize(at url: URL, named name: String) throws -> Int64 {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            throw OfflinePackageValidationError.missingFile(name)
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
            throw OfflinePackageValidationError.invalidFileType(name)
        }
        return Int64(size)
    }

    private func sha256Hex(of url: URL, maximumBytes: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var bytesRead: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            let (newBytesRead, overflowed) = bytesRead.addingReportingOverflow(Int64(chunk.count))
            guard !overflowed, newBytesRead <= maximumBytes else {
                throw OfflinePackageValidationError.invalidDeclaredSize
            }
            bytesRead = newBytesRead
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isSafeIdentifier(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumLength else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !value.contains("..")
            && !value.hasPrefix(".")
            && !value.hasSuffix(".")
    }

    private func isSemanticVersion(_ value: String) -> Bool {
        semanticVersionParts(value) != nil
    }

    private func semanticVersionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  (part.count == 1 || part.first != "0") else {
                return nil
            }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character)
        }
    }

    private func littleEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func littleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private func metadata(_ key: String, database: OpaquePointer) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM package_metadata WHERE key = ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }
        return try key.withCString { keyPointer in
            guard sqlite3_bind_text(statement, 1, keyPointer, -1, nil) == SQLITE_OK else {
                throw OfflinePackageValidationError.invalidCatalog
            }
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let value = sqlite3_column_text(statement, 0) else {
                throw OfflinePackageValidationError.invalidCatalog
            }
            return String(cString: value)
        }
    }

    private func singleText(_ query: String, database: OpaquePointer) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        return String(cString: value)
    }

    private func rowCount(_ query: String, database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }
        var count = 0
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                count += 1
            case SQLITE_DONE:
                return count
            default:
                throw OfflinePackageValidationError.invalidCatalog
            }
        }
    }

    private func loadTiles(database: OpaquePointer) throws -> [TerrainTileRecord] {
        let query = """
        SELECT id, row_count, column_count, offset_bytes, compressed_bytes,
               uncompressed_bytes, sha256
        FROM terrain_tiles ORDER BY offset_bytes;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }
        var tiles: [TerrainTileRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let idText = sqlite3_column_text(statement, 0),
                      let hashText = sqlite3_column_text(statement, 6) else {
                    throw OfflinePackageValidationError.invalidCatalog
                }
                tiles.append(
                    TerrainTileRecord(
                        id: String(cString: idText),
                        rowCount: Int(sqlite3_column_int64(statement, 1)),
                        columnCount: Int(sqlite3_column_int64(statement, 2)),
                        offsetBytes: sqlite3_column_int64(statement, 3),
                        compressedBytes: Int(sqlite3_column_int64(statement, 4)),
                        uncompressedBytes: Int(sqlite3_column_int64(statement, 5)),
                        sha256: String(cString: hashText)
                    )
                )
                guard tiles.count <= Limits.maximumTerrainTiles else {
                    throw OfflinePackageValidationError.invalidCatalog
                }
            case SQLITE_DONE:
                return tiles
            default:
                throw OfflinePackageValidationError.invalidCatalog
            }
        }
    }

    private func requiredTablesExist(database: OpaquePointer) throws -> Bool {
        let requiredTables = [
            "package_metadata",
            "regions",
            "mountains",
            "mountain_names",
            "points_of_interest",
            "mountain_points_of_interest",
            "source_links",
            "entity_sources",
            "terrain_tiles",
        ]
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw OfflinePackageValidationError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }
        for table in requiredTables {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            let exists = table.withCString { tablePointer in
                sqlite3_bind_text(statement, 1, tablePointer, -1, nil) == SQLITE_OK
                    && sqlite3_step(statement) == SQLITE_ROW
            }
            guard exists else { return false }
        }
        return true
    }
}

private nonisolated struct CatalogValidationResult: Sendable {
    let tiles: [TerrainTileRecord]
}

private nonisolated struct TerrainTileRecord: Sendable {
    let id: String
    let rowCount: Int
    let columnCount: Int
    let offsetBytes: Int64
    let compressedBytes: Int
    let uncompressedBytes: Int
    let sha256: String
}
