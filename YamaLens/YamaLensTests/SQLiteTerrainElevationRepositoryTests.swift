import Foundation
import SQLite3
import Testing
@testable import YamaLens

struct SQLiteTerrainElevationRepositoryTests {
    @Test("緯度経度を北西原点の256角グリッドへ対応付けて標高を読む")
    func readsElevationFromMatchingGridCell() async throws {
        let root = try makeTemporaryDirectory(named: "matching-cell")
        defer { removeTemporaryDirectory(root) }
        var elevations = [Int16](repeating: 100, count: 256 * 256)
        elevations[64 * 256 + 128] = 1_491
        try TerrainPackageFixture.make(
            at: root,
            tiles: [tile(id: "detail", resolutionMeters: 10, elevations: elevations)]
        )
        let repository = try SQLiteTerrainElevationRepository(packageDirectoryURL: root)
        let latitude = 35.5 - (64.5 / 256) * 0.1
        let longitude = 139.1 + (128.5 / 256) * 0.1

        let result = try await repository.elevations(
            at: [GeoCoordinate(latitude: latitude, longitude: longitude)]
        )

        #expect(result.count == 1)
        #expect(result[0]?.meters == 1_491)
    }

    @Test("詳細タイルの欠損セルでは同範囲の粗いタイルへ縮退する")
    func fallsBackToCoarserTileForMissingCell() async throws {
        let root = try makeTemporaryDirectory(named: "resolution-fallback")
        defer { removeTemporaryDirectory(root) }
        let detailed = [Int16](repeating: .min, count: 256 * 256)
        let coarse = [Int16](repeating: 850, count: 256 * 256)
        try TerrainPackageFixture.make(
            at: root,
            tiles: [
                tile(id: "coarse", resolutionMeters: 50, elevations: coarse),
                tile(id: "detail", resolutionMeters: 10, elevations: detailed),
            ]
        )
        let repository = try SQLiteTerrainElevationRepository(packageDirectoryURL: root)

        let result = try await repository.elevations(
            at: [GeoCoordinate(latitude: 35.45, longitude: 139.15)]
        )

        #expect(result[0]?.meters == 850)
    }

    @Test("収録範囲外と全解像度の欠損を未取得として返す")
    func returnsNilOutsideCoverageAndForMissingElevation() async throws {
        let root = try makeTemporaryDirectory(named: "missing")
        defer { removeTemporaryDirectory(root) }
        let elevations = [Int16](repeating: .min, count: 256 * 256)
        try TerrainPackageFixture.make(
            at: root,
            tiles: [tile(id: "detail", resolutionMeters: 10, elevations: elevations)]
        )
        let repository = try SQLiteTerrainElevationRepository(packageDirectoryURL: root)

        let result = try await repository.elevations(
            at: [
                GeoCoordinate(latitude: 35.45, longitude: 139.15),
                GeoCoordinate(latitude: 36, longitude: 140),
            ]
        )

        #expect(result.count == 2)
        #expect(result[0] == nil)
        #expect(result[1] == nil)
    }

    @Test("展開後SHA-256が索引と異なるタイルを使用しない")
    func rejectsTileWithHashMismatch() async throws {
        let root = try makeTemporaryDirectory(named: "hash-mismatch")
        defer { removeTemporaryDirectory(root) }
        let elevations = [Int16](repeating: 100, count: 256 * 256)
        try TerrainPackageFixture.make(
            at: root,
            tiles: [tile(id: "detail", resolutionMeters: 10, elevations: elevations)]
        )
        try executeCatalogSQL(
            "UPDATE terrain_tiles SET sha256 = '\(String(repeating: "0", count: 64))';",
            at: root.appending(path: "catalog.sqlite")
        )
        let repository = try SQLiteTerrainElevationRepository(packageDirectoryURL: root)

        await #expect(throws: TerrainElevationRepositoryError.invalidTile("detail")) {
            _ = try await repository.elevations(
                at: [GeoCoordinate(latitude: 35.45, longitude: 139.15)]
            )
        }
    }

    private func tile(
        id: String,
        resolutionMeters: Double,
        elevations: [Int16]
    ) -> TerrainTileFixture {
        TerrainTileFixture(
            id: id,
            north: 35.5,
            south: 35.4,
            east: 139.2,
            west: 139.1,
            resolutionMeters: resolutionMeters,
            elevations: elevations
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensTerrainElevationRepositoryTests")
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

    private func executeCatalogSQL(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw TestDatabaseError.sqlite
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestDatabaseError.sqlite
        }
    }

    private enum TestDatabaseError: Error {
        case sqlite
    }
}
