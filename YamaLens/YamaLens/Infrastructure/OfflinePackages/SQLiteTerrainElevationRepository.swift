import Compression
import CryptoKit
import Foundation
import SQLite3

nonisolated enum TerrainElevationRepositoryError: Error, Equatable, Sendable {
    case invalidCatalog
    case invalidTerrainFile
    case invalidTile(String)
}

actor SQLiteTerrainElevationRepository: TerrainElevationRepository {
    private enum Limits {
        static let terrainHeaderBytes = 16
        static let terrainTileRows = 256
        static let terrainTileColumns = 256
        static let terrainTileBytes = terrainTileRows
            * terrainTileColumns
            * MemoryLayout<Int16>.size
        static let maximumCompressedTileBytes = 262_144
        static let maximumTerrainTiles = 100_000
        static let maximumTerrainFileBytes = 1_000_000_000
        static let missingElevation = Int16.min
        static let cachedTileCount = 8
    }

    private let terrainFile: FileHandle
    private let terrainFileSize: Int64
    private let tiles: [TileRecord]
    private var cachedElevationsByTileID: [String: [Int16]] = [:]
    private var cachedTileIDsByRecency: [String] = []

    init(packageDirectoryURL: URL) throws {
        let catalogURL = packageDirectoryURL.appending(path: "catalog.sqlite")
        let terrainURL = packageDirectoryURL.appending(path: "terrain.lzfse")
        let terrainFile = try Self.openTerrainFile(at: terrainURL)
        let terrainHeader: Data
        do {
            terrainHeader = try terrainFile.handle.read(upToCount: Limits.terrainHeaderBytes)
                ?? Data()
        } catch {
            throw TerrainElevationRepositoryError.invalidTerrainFile
        }
        let tiles = try Self.loadTiles(from: catalogURL)
        try Self.validateTerrainLayout(
            terrainHeader,
            terrainFileSize: terrainFile.size,
            tiles: tiles
        )
        self.terrainFile = terrainFile.handle
        self.terrainFileSize = terrainFile.size
        self.tiles = tiles.sorted {
            if $0.resolutionMeters == $1.resolutionMeters {
                return $0.id < $1.id
            }
            return $0.resolutionMeters < $1.resolutionMeters
        }
    }

    deinit {
        terrainFile.closeFile()
    }

    func elevations(at coordinates: [GeoCoordinate]) async throws -> [TerrainElevation?] {
        var elevations: [TerrainElevation?] = []
        elevations.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            try Task.checkCancellation()
            elevations.append(try elevation(at: coordinate))
        }
        return elevations
    }

    private func elevation(at coordinate: GeoCoordinate) throws -> TerrainElevation? {
        guard Self.isValid(coordinate) else { return nil }
        let matchingTiles = tiles.filter { $0.contains(coordinate) }
        for tile in matchingTiles {
            let values = try decodedElevations(for: tile)
            let index = tile.elevationIndex(for: coordinate)
            let value = values[index]
            guard value != Limits.missingElevation else { continue }
            return TerrainElevation(meters: Double(value))
        }
        return nil
    }

    private func decodedElevations(for tile: TileRecord) throws -> [Int16] {
        if let cached = cachedElevationsByTileID[tile.id] {
            markRecentlyUsed(tile.id)
            return cached
        }

        let (endOffset, overflowed) = tile.offsetBytes.addingReportingOverflow(
            tile.compressedBytes
        )
        guard
            !overflowed,
            tile.offsetBytes >= Int64(Limits.terrainHeaderBytes),
            endOffset <= terrainFileSize
        else {
            throw TerrainElevationRepositoryError.invalidTile(tile.id)
        }
        let compressed: Data
        do {
            try terrainFile.seek(toOffset: UInt64(tile.offsetBytes))
            compressed = try terrainFile.read(upToCount: Int(tile.compressedBytes)) ?? Data()
        } catch {
            throw TerrainElevationRepositoryError.invalidTile(tile.id)
        }
        guard compressed.count == Int(tile.compressedBytes) else {
            throw TerrainElevationRepositoryError.invalidTile(tile.id)
        }
        var decoded = [UInt8](repeating: 0, count: Limits.terrainTileBytes)
        let decodedCount = compressed.withUnsafeBytes { source in
            decoded.withUnsafeMutableBytes { destination in
                guard
                    let sourceAddress = source.bindMemory(to: UInt8.self).baseAddress,
                    let destinationAddress = destination.bindMemory(to: UInt8.self).baseAddress
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
            throw TerrainElevationRepositoryError.invalidTile(tile.id)
        }
        let decodedData = Data(decoded)
        guard Self.sha256Hex(decodedData) == tile.sha256 else {
            throw TerrainElevationRepositoryError.invalidTile(tile.id)
        }

        var values: [Int16] = []
        values.reserveCapacity(Limits.terrainTileRows * Limits.terrainTileColumns)
        for byteOffset in stride(from: 0, to: decoded.count, by: 2) {
            let bits = UInt16(decoded[byteOffset]) | UInt16(decoded[byteOffset + 1]) << 8
            values.append(Int16(bitPattern: bits))
        }
        cache(values, for: tile.id)
        return values
    }

    private func cache(_ elevations: [Int16], for tileID: String) {
        cachedElevationsByTileID[tileID] = elevations
        markRecentlyUsed(tileID)
        while cachedTileIDsByRecency.count > Limits.cachedTileCount {
            let removedID = cachedTileIDsByRecency.removeFirst()
            cachedElevationsByTileID.removeValue(forKey: removedID)
        }
    }

    private func markRecentlyUsed(_ tileID: String) {
        cachedTileIDsByRecency.removeAll { $0 == tileID }
        cachedTileIDsByRecency.append(tileID)
    }

    private static func openTerrainFile(at url: URL) throws -> TerrainFile {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            throw TerrainElevationRepositoryError.invalidTerrainFile
        }
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize,
            size >= Limits.terrainHeaderBytes,
            size <= Limits.maximumTerrainFileBytes
        else {
            throw TerrainElevationRepositoryError.invalidTerrainFile
        }
        do {
            return TerrainFile(
                handle: try FileHandle(forReadingFrom: url),
                size: Int64(size)
            )
        } catch {
            throw TerrainElevationRepositoryError.invalidTerrainFile
        }
    }

    private static func loadTiles(from catalogURL: URL) throws -> [TileRecord] {
        var database: OpaquePointer?
        let openResult = catalogURL.path.withCString { path in
            sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        }
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw TerrainElevationRepositoryError.invalidCatalog
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT id, north, south, east, west, resolution_m, row_count, column_count,
               offset_bytes, compressed_bytes, uncompressed_bytes, sha256
        FROM terrain_tiles ORDER BY offset_bytes;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw TerrainElevationRepositoryError.invalidCatalog
        }
        defer { sqlite3_finalize(statement) }

        var tiles: [TileRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard
                    let idText = sqlite3_column_text(statement, 0),
                    let hashText = sqlite3_column_text(statement, 11)
                else {
                    throw TerrainElevationRepositoryError.invalidCatalog
                }
                let tile = TileRecord(
                    id: String(cString: idText),
                    north: sqlite3_column_double(statement, 1),
                    south: sqlite3_column_double(statement, 2),
                    east: sqlite3_column_double(statement, 3),
                    west: sqlite3_column_double(statement, 4),
                    resolutionMeters: sqlite3_column_double(statement, 5),
                    rowCount: sqlite3_column_int64(statement, 6),
                    columnCount: sqlite3_column_int64(statement, 7),
                    offsetBytes: sqlite3_column_int64(statement, 8),
                    compressedBytes: sqlite3_column_int64(statement, 9),
                    uncompressedBytes: sqlite3_column_int64(statement, 10),
                    sha256: String(cString: hashText)
                )
                guard tile.isValid else {
                    throw TerrainElevationRepositoryError.invalidCatalog
                }
                tiles.append(tile)
                guard tiles.count <= Limits.maximumTerrainTiles else {
                    throw TerrainElevationRepositoryError.invalidCatalog
                }
            case SQLITE_DONE:
                guard !tiles.isEmpty else {
                    throw TerrainElevationRepositoryError.invalidCatalog
                }
                return tiles
            default:
                throw TerrainElevationRepositoryError.invalidCatalog
            }
        }
    }

    private static func validateTerrainLayout(
        _ header: Data,
        terrainFileSize: Int64,
        tiles: [TileRecord]
    ) throws {
        let bytes = [UInt8](header)
        guard
            bytes.count == Limits.terrainHeaderBytes,
            Array(bytes[0..<4]) == Array("YLTF".utf8),
            littleEndianUInt16(bytes, offset: 4) == 1,
            littleEndianUInt16(bytes, offset: 6) == UInt16(Limits.terrainHeaderBytes),
            littleEndianUInt32(bytes, offset: 8) == UInt32(tiles.count),
            littleEndianUInt32(bytes, offset: 12) == 0
        else {
            throw TerrainElevationRepositoryError.invalidTerrainFile
        }

        var previousEndOffset = Int64(Limits.terrainHeaderBytes)
        for tile in tiles.sorted(by: { $0.offsetBytes < $1.offsetBytes }) {
            let (endOffset, overflowed) = tile.offsetBytes.addingReportingOverflow(
                Int64(tile.compressedBytes)
            )
            guard
                !overflowed,
                tile.offsetBytes >= previousEndOffset,
                endOffset <= terrainFileSize
            else {
                throw TerrainElevationRepositoryError.invalidTile(tile.id)
            }
            previousEndOffset = endOffset
        }
    }

    private static func isValid(_ coordinate: GeoCoordinate) -> Bool {
        coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude)
            && (-180...180).contains(coordinate.longitude)
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated struct TerrainFile: Sendable {
    let handle: FileHandle
    let size: Int64
}

private nonisolated struct TileRecord: Sendable {
    let id: String
    let north: Double
    let south: Double
    let east: Double
    let west: Double
    let resolutionMeters: Double
    let rowCount: Int64
    let columnCount: Int64
    let offsetBytes: Int64
    let compressedBytes: Int64
    let uncompressedBytes: Int64
    let sha256: String

    var isValid: Bool {
        !id.isEmpty
            && id.utf8.count <= 128
            && north.isFinite
            && south.isFinite
            && east.isFinite
            && west.isFinite
            && (-90...90).contains(north)
            && (-90...90).contains(south)
            && (-180...180).contains(east)
            && (-180...180).contains(west)
            && north > south
            && east > west
            && resolutionMeters.isFinite
            && resolutionMeters > 0
            && rowCount == 256
            && columnCount == 256
            && offsetBytes >= 16
            && compressedBytes > 0
            && compressedBytes <= 262_144
            && uncompressedBytes == 131_072
            && sha256.count == 64
            && sha256.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
    }

    func contains(_ coordinate: GeoCoordinate) -> Bool {
        coordinate.latitude <= north
            && coordinate.latitude >= south
            && coordinate.longitude <= east
            && coordinate.longitude >= west
    }

    func elevationIndex(for coordinate: GeoCoordinate) -> Int {
        let latitudeProgress = (north - coordinate.latitude) / (north - south)
        let longitudeProgress = (coordinate.longitude - west) / (east - west)
        let row = min(max(Int(latitudeProgress * Double(rowCount)), 0), Int(rowCount) - 1)
        let column = min(
            max(Int(longitudeProgress * Double(columnCount)), 0),
            Int(columnCount) - 1
        )
        return row * Int(columnCount) + column
    }
}
