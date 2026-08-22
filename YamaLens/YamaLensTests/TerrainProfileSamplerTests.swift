import Foundation
import Testing
@testable import YamaLens

struct TerrainProfileSamplerTests {
    private let sampler = TerrainProfileSampler()
    private let proximityCalculator = MountainProximityCalculator()

    @Test("近距離の断面を端点を除く約50m間隔で生成する")
    func samplesShortProfile() throws {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let destination = GeoCoordinate(latitude: 35.01, longitude: 139)
        let distance = try #require(
            proximityCalculator.proximity(from: origin, to: destination)?.distance
        )

        let points = try #require(
            sampler.points(from: origin, to: destination, summitDistance: distance)
        )

        #expect(!points.isEmpty)
        #expect(points.count < 512)
        #expect(points.first?.distance.meters ?? 0 > 0)
        #expect(points.last?.distance.meters ?? .infinity < distance.meters)
        #expect(points.allSatisfy { abs($0.coordinate.longitude - 139) < 0.000_001 })
    }

    @Test("遠距離の断面は512点を超えない")
    func capsLongProfile() throws {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let destination = GeoCoordinate(latitude: 36.3, longitude: 139)
        let distance = try #require(
            proximityCalculator.proximity(from: origin, to: destination)?.distance
        )

        let points = try #require(
            sampler.points(from: origin, to: destination, summitDistance: distance)
        )

        #expect(points.count == 512)
    }
}
