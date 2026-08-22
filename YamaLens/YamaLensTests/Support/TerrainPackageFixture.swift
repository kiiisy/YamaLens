import Compression
import CryptoKit
import Foundation
import SQLite3

struct TerrainTileFixture: Sendable {
    let id: String
    let north: Double
    let south: Double
    let east: Double
    let west: Double
    let resolutionMeters: Double
    let elevations: [Int16]
}

enum TerrainPackageFixture {
    static func make(at directoryURL: URL, tiles: [TerrainTileFixture]) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        var terrainData = Data("YLTF".utf8)
        appendLittleEndianUInt16(1, to: &terrainData)
        appendLittleEndianUInt16(16, to: &terrainData)
        appendLittleEndianUInt32(UInt32(tiles.count), to: &terrainData)
        appendLittleEndianUInt32(0, to: &terrainData)

        var catalogRows: [CatalogRow] = []
        for tile in tiles {
            guard tile.elevations.count == 256 * 256 else {
                throw FixtureError.invalidElevationCount
            }
            let decoded = encodedElevations(tile.elevations)
            let compressed = try compressLZFSE(decoded)
            catalogRows.append(
                CatalogRow(
                    tile: tile,
                    offsetBytes: terrainData.count,
                    compressedBytes: compressed.count,
                    sha256: sha256Hex(decoded)
                )
            )
            terrainData.append(compressed)
        }

        try terrainData.write(to: directoryURL.appending(path: "terrain.lzfse"))
        try createCatalog(
            at: directoryURL.appending(path: "catalog.sqlite"),
            rows: catalogRows
        )
    }

    private static func createCatalog(at url: URL, rows: [CatalogRow]) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        let schema = """
        CREATE TABLE terrain_tiles(
            id TEXT PRIMARY KEY,
            north REAL NOT NULL,
            south REAL NOT NULL,
            east REAL NOT NULL,
            west REAL NOT NULL,
            resolution_m REAL NOT NULL,
            row_count INTEGER NOT NULL,
            column_count INTEGER NOT NULL,
            offset_bytes INTEGER NOT NULL,
            compressed_bytes INTEGER NOT NULL,
            uncompressed_bytes INTEGER NOT NULL,
            sha256 TEXT NOT NULL
        );
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }

        for row in rows {
            let tile = row.tile
            let sql = """
            INSERT INTO terrain_tiles VALUES(
                '\(escaped(tile.id))',
                \(tile.north),
                \(tile.south),
                \(tile.east),
                \(tile.west),
                \(tile.resolutionMeters),
                256,
                256,
                \(row.offsetBytes),
                \(row.compressedBytes),
                131072,
                '\(row.sha256)'
            );
            """
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw FixtureError.sqlite
            }
        }
    }

    private static func encodedElevations(_ elevations: [Int16]) -> Data {
        var data = Data()
        data.reserveCapacity(elevations.count * MemoryLayout<Int16>.size)
        for elevation in elevations {
            let bits = UInt16(bitPattern: elevation)
            data.append(UInt8(bits & 0xFF))
            data.append(UInt8((bits >> 8) & 0xFF))
        }
        return data
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

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private struct CatalogRow {
        let tile: TerrainTileFixture
        let offsetBytes: Int
        let compressedBytes: Int
        let sha256: String
    }

    private enum FixtureError: Error {
        case compression
        case invalidElevationCount
        case sqlite
    }
}
