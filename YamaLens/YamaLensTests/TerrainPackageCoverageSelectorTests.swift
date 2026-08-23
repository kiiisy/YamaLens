import Testing
@testable import YamaLens

struct TerrainPackageCoverageSelectorTests {
    @Test("現在地を含む詳細地形範囲を選ぶ")
    func selectsContainingCoverage() {
        let selector = TerrainPackageCoverageSelector()

        let selected = selector.select(
            for: GeoCoordinate(latitude: 35.97, longitude: 138.37),
            from: [senjogatake, yatsugatake]
        )

        #expect(selected?.packageID == yatsugatake.packageID)
    }

    @Test("範囲が重なる場合は中心に近いパックを選ぶ")
    func selectsNearestCenterForOverlap() {
        let selector = TerrainPackageCoverageSelector()
        let west = TerrainPackageCoverage(
            packageID: "west",
            displayName: "西",
            north: 36,
            south: 35,
            east: 139,
            west: 137
        )
        let east = TerrainPackageCoverage(
            packageID: "east",
            displayName: "東",
            north: 36,
            south: 35,
            east: 140,
            west: 138
        )

        let selected = selector.select(
            for: GeoCoordinate(latitude: 35.5, longitude: 138.8),
            from: [west, east]
        )

        #expect(selected?.packageID == east.packageID)
    }

    @Test("どの詳細地形範囲にも入らない場合は選択しない")
    func returnsNilOutsideCoverage() {
        let selector = TerrainPackageCoverageSelector()

        let selected = selector.select(
            for: GeoCoordinate(latitude: 34.7, longitude: 135.5),
            from: [senjogatake, yatsugatake]
        )

        #expect(selected == nil)
    }

    private var yatsugatake: TerrainPackageCoverage {
        TerrainPackageCoverage(
            packageID: "jp.yatsugatake.ar-test",
            displayName: "八ヶ岳",
            north: 36.11,
            south: 35.90,
            east: 138.43,
            west: 138.29
        )
    }

    private var senjogatake: TerrainPackageCoverage {
        TerrainPackageCoverage(
            packageID: "jp.southern-alps.senjogatake.ar-test",
            displayName: "仙丈ヶ岳",
            north: 35.82,
            south: 35.56,
            east: 138.32,
            west: 138.10
        )
    }
}
