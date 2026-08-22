import Foundation
import Testing
@testable import YamaLens

struct TerrainVisibilityResolverTests {
    @Test("途中地形が視線を30m以上上回る候補を遮蔽と判定する")
    func resolvesOcclusion() async throws {
        let repository = ConstantTerrainElevationRepository(elevationMeters: 1_100)
        let resolver = TerrainVisibilityResolver(elevationRepository: repository)

        let results = try await resolver.resolveVisibility(
            from: location(altitudeMeters: 1_000, verticalAccuracyMeters: 5),
            to: [mountain]
        )

        guard case .occluded(let excessHeight) = results[mountain.id] else {
            Issue.record("遮蔽判定になりませんでした")
            return
        }
        #expect(excessHeight >= 30)
    }

    @Test("高度が利用できない場合はDEMを読まず地形未確認にする")
    func avoidsTerrainReadWithoutUsableAltitude() async throws {
        let repository = ConstantTerrainElevationRepository(elevationMeters: 1_100)
        let resolver = TerrainVisibilityResolver(elevationRepository: repository)

        let results = try await resolver.resolveVisibility(
            from: location(altitudeMeters: nil, verticalAccuracyMeters: nil),
            to: [mountain]
        )

        #expect(results[mountain.id] == .unavailable)
        #expect(await repository.requestCount == 0)
    }

    private func location(
        altitudeMeters: Double?,
        verticalAccuracyMeters: Double?
    ) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35, longitude: 139),
            altitudeMeters: altitudeMeters,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: verticalAccuracyMeters,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private var mountain: Mountain {
        Mountain(
            id: "north",
            name: "北の山",
            aliases: [],
            regionName: "テスト山域",
            prefectureName: "神奈川県",
            elevationMeters: 1_000,
            coordinate: GeoCoordinate(latitude: 35.01, longitude: 139)
        )
    }
}

private actor ConstantTerrainElevationRepository: TerrainElevationRepository {
    private let elevation: TerrainElevation?
    private(set) var requestCount = 0

    init(elevationMeters: Double) {
        elevation = TerrainElevation(meters: elevationMeters)
    }

    func elevations(at coordinates: [GeoCoordinate]) async throws -> [TerrainElevation?] {
        requestCount += 1
        return Array(repeating: elevation, count: coordinates.count)
    }
}
