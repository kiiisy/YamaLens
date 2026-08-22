import Foundation
import Testing
@testable import YamaLens

struct TerrainHorizonResolverTests {
    @Test("画角と手動補正範囲を含むDEM予測稜線を生成する")
    func resolvesTerrainHorizonAcrossCameraSpan() async throws {
        let repository = HorizonElevationRepository(elevationMeters: 1_300)
        let resolver = TerrainHorizonResolver(elevationRepository: repository)

        let samples = try await resolver.resolveHorizon(
            from: location(altitudeMeters: 1_000, verticalAccuracyMeters: 5),
            centerBearingDegrees: 0,
            horizontalFieldOfViewDegrees: 70
        )

        #expect(samples.count == 69)
        #expect(samples.allSatisfy { $0.elevationAngleDegrees?.isFinite == true })
        #expect(samples.contains { sample in
            sample.bearingDegrees > 350 && sample.elevationAngleDegrees != nil
        })
        #expect(samples.contains { sample in
            sample.bearingDegrees < 10 && sample.elevationAngleDegrees != nil
        })
        #expect(await repository.requestedCoordinateCount == 69 * 250)
    }

    @Test("DEMが全地点で欠損する方角は線を推測しない")
    func preservesUnavailableHorizonSamples() async throws {
        let repository = HorizonElevationRepository(elevationMeters: nil)
        let resolver = TerrainHorizonResolver(elevationRepository: repository)

        let samples = try await resolver.resolveHorizon(
            from: location(altitudeMeters: 1_000, verticalAccuracyMeters: 5),
            centerBearingDegrees: 180,
            horizontalFieldOfViewDegrees: 50
        )

        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.elevationAngleDegrees == nil })
    }

    @Test("観測地点の高度が利用できない場合はDEMを読まない")
    func avoidsTerrainReadWithoutObserverElevation() async throws {
        let repository = HorizonElevationRepository(elevationMeters: 1_300)
        let resolver = TerrainHorizonResolver(elevationRepository: repository)

        let samples = try await resolver.resolveHorizon(
            from: location(altitudeMeters: nil, verticalAccuracyMeters: nil),
            centerBearingDegrees: 0,
            horizontalFieldOfViewDegrees: 70
        )

        #expect(samples.isEmpty)
        #expect(await repository.requestedCoordinateCount == 0)
    }

    private func location(
        altitudeMeters: Double?,
        verticalAccuracyMeters: Double?
    ) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.47, longitude: 139.15),
            altitudeMeters: altitudeMeters,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: verticalAccuracyMeters,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private actor HorizonElevationRepository: TerrainElevationRepository {
    private let elevation: TerrainElevation?
    private(set) var requestedCoordinateCount = 0

    init(elevationMeters: Double?) {
        if let elevationMeters {
            elevation = TerrainElevation(meters: elevationMeters)
        } else {
            elevation = nil
        }
    }

    func elevations(at coordinates: [GeoCoordinate]) async throws -> [TerrainElevation?] {
        requestedCoordinateCount += coordinates.count
        return Array(repeating: elevation, count: coordinates.count)
    }
}
