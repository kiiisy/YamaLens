import Foundation
import Testing
@testable import YamaLens

struct ActiveOfflinePackageTerrainVisibilityResolverTests {
    @Test("詳細パック未導入時は地形未確認へ縮退する")
    func returnsUnavailableWithoutInstalledPackage() async throws {
        let rootURL = try makeTemporaryDirectory(named: "missing")
        defer { removeTemporaryDirectory(rootURL) }
        let store = OfflinePackageStore(
            rootURL: rootURL.appending(path: "OfflinePackages"),
            validator: OfflinePackageValidator(publicKeys: [:])
        )
        let resolver = ActiveOfflinePackageTerrainVisibilityResolver(store: store)

        let result = try await resolver.resolveVisibility(
            from: location,
            to: [mountain]
        )

        #expect(result[mountain.id] == .unavailable)
    }

    @Test("activeの詳細パックを地形見通し判定へ接続する")
    func usesActivePackageTerrain() async throws {
        let rootURL = try makeTemporaryDirectory(named: "active")
        defer { removeTemporaryDirectory(rootURL) }
        let storeRootURL = rootURL.appending(path: "OfflinePackages")
        let stagingURL = storeRootURL
            .appending(path: "Staging")
            .appending(path: "fixture")
        let fixture = try OfflinePackageFixture.make(at: stagingURL)
        let store = OfflinePackageStore(
            rootURL: storeRootURL,
            validator: OfflinePackageValidator(publicKeys: fixture.publicKeys)
        )
        _ = try await store.install(stagedPackageURL: stagingURL)
        let resolver = ActiveOfflinePackageTerrainVisibilityResolver(store: store)

        let result = try await resolver.resolveVisibility(
            from: location,
            to: [mountain]
        )

        #expect(result[mountain.id] == .notOccluded)
    }

    @Test("activeの詳細パックから予測稜線を生成する")
    func resolvesHorizonFromActivePackageTerrain() async throws {
        let rootURL = try makeTemporaryDirectory(named: "horizon")
        defer { removeTemporaryDirectory(rootURL) }
        let storeRootURL = rootURL.appending(path: "OfflinePackages")
        let stagingURL = storeRootURL
            .appending(path: "Staging")
            .appending(path: "fixture")
        let fixture = try OfflinePackageFixture.make(at: stagingURL)
        let store = OfflinePackageStore(
            rootURL: storeRootURL,
            validator: OfflinePackageValidator(publicKeys: fixture.publicKeys)
        )
        _ = try await store.install(stagedPackageURL: stagingURL)
        let resolver = ActiveOfflinePackageTerrainVisibilityResolver(store: store)

        let samples = try await resolver.resolveHorizon(
            from: location,
            centerBearingDegrees: 0,
            horizontalFieldOfViewDegrees: 50
        )

        #expect(!samples.isEmpty)
        #expect(samples.contains { $0.elevationAngleDegrees != nil })
    }

    private var location: LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.41, longitude: 139.15),
            altitudeMeters: 0,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 5,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private var mountain: Mountain {
        Mountain(
            id: "test-north",
            name: "テスト北峰",
            aliases: [],
            regionName: "丹沢山地",
            prefectureName: "神奈川県",
            elevationMeters: 1_000,
            coordinate: GeoCoordinate(latitude: 35.49, longitude: 139.15)
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ActiveOfflinePackageTerrainVisibilityResolverTests")
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
}
