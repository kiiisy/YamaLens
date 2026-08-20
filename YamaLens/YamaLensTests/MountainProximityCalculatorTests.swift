import Testing
@testable import YamaLens

struct MountainProximityCalculatorTests {
    private let calculator = MountainProximityCalculator()

    @Test("水平精度の境界を品質へ変換する")
    func classifiesLocationAccuracyBoundaries() {
        #expect(calculator.locationQuality(horizontalAccuracyMeters: 25) == .good)
        #expect(calculator.locationQuality(horizontalAccuracyMeters: 25.01) == .reduced)
        #expect(calculator.locationQuality(horizontalAccuracyMeters: 100) == .reduced)
        #expect(calculator.locationQuality(horizontalAccuracyMeters: 100.01) == nil)
        #expect(calculator.locationQuality(horizontalAccuracyMeters: -1) == nil)
    }

    @Test("北にある地点の距離と真方位を計算する")
    func calculatesNorthwardDistanceAndBearing() throws {
        let proximity = try #require(
            calculator.proximity(
                from: GeoCoordinate(latitude: 35, longitude: 139),
                to: GeoCoordinate(latitude: 36, longitude: 139)
            )
        )

        #expect(abs(proximity.distance.meters - 111_195) < 100)
        #expect(try #require(proximity.bearing).degrees == 0)
        #expect(proximity.direction == .north)
    }

    @Test("同じ地点では距離だけを返し方角を断定しない")
    func omitsBearingAtSameCoordinate() throws {
        let coordinate = GeoCoordinate(latitude: 35.5, longitude: 139.2)
        let proximity = try #require(calculator.proximity(from: coordinate, to: coordinate))

        #expect(proximity.distance.meters == 0)
        #expect(proximity.bearing == nil)
        #expect(proximity.direction == nil)
    }

    @Test("不正な座標は計算しない")
    func rejectsInvalidCoordinates() {
        let proximity = calculator.proximity(
            from: GeoCoordinate(latitude: 91, longitude: 139),
            to: GeoCoordinate(latitude: 35, longitude: 139)
        )

        #expect(proximity == nil)
    }

    @Test("150km以内だけを距離順で返す")
    func filtersAndSortsNearbyMountains() {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let near = mountain(id: "near", latitude: 35.1, longitude: 139)
        let middle = mountain(id: "middle", latitude: 36, longitude: 139)
        let outside = mountain(id: "outside", latitude: 37, longitude: 139)

        let results = calculator.nearbyMountains(
            from: origin,
            mountains: [outside, middle, near]
        )

        #expect(results.map(\.mountain.id) == ["near", "middle"])
    }

    @Test("同距離の山はID順で安定して並ぶ")
    func sortsEqualDistancesDeterministically() {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let mountainB = mountain(id: "b", latitude: 35.1, longitude: 139)
        let mountainA = mountain(id: "a", latitude: 35.1, longitude: 139)

        let results = calculator.nearbyMountains(
            from: origin,
            mountains: [mountainB, mountainA]
        )

        #expect(results.map(\.mountain.id) == ["a", "b"])
    }

    private func mountain(id: String, latitude: Double, longitude: Double) -> Mountain {
        Mountain(
            id: id,
            name: id,
            aliases: [],
            regionName: "テスト山域",
            prefectureName: "神奈川県",
            elevationMeters: 1_000,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude)
        )
    }
}
