import Foundation
import Testing
@testable import YamaLens

struct TerrainLineOfSightEvaluatorTests {
    private let evaluator = TerrainLineOfSightEvaluator()

    @Test("途中地形が視線より30m高い境界で遮蔽候補とする")
    func marksThirtyMeterBoundaryAsOccluded() throws {
        let sightLineElevationMeters = midpointSightLineElevation(
            observerElevationMeters: 1_000,
            summitElevationMeters: 2_000,
            summitDistanceMeters: 10_000
        )
        let result = evaluator.evaluate(
            observerElevation: try #require(TerrainElevation(meters: 1_000)),
            summitElevation: try #require(TerrainElevation(meters: 2_000)),
            summitDistance: MountainDistance(meters: 10_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 5_000),
                    elevation: try #require(
                        TerrainElevation(meters: sightLineElevationMeters + 30)
                    )
                ),
            ]
        )

        guard case .occluded(let excessHeightMeters) = result else {
            Issue.record("30m境界が遮蔽候補になっていません")
            return
        }
        #expect(abs(excessHeightMeters - 30) < 0.000_001)
    }

    @Test("途中地形が視線より30m未満なら遮蔽候補にしない")
    func keepsCandidateBelowClearanceBoundary() throws {
        let sightLineElevationMeters = midpointSightLineElevation(
            observerElevationMeters: 1_000,
            summitElevationMeters: 2_000,
            summitDistanceMeters: 10_000
        )
        let result = evaluator.evaluate(
            observerElevation: try #require(TerrainElevation(meters: 1_000)),
            summitElevation: try #require(TerrainElevation(meters: 2_000)),
            summitDistance: MountainDistance(meters: 10_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 5_000),
                    elevation: try #require(
                        TerrainElevation(meters: sightLineElevationMeters + 29.99)
                    )
                ),
            ]
        )

        #expect(result == .notOccluded)
    }

    @Test("既知地点で遮蔽を検出した場合は別地点の欠損より優先する")
    func detectsOcclusionDespiteAnotherMissingSample() throws {
        let sightLineElevationMeters = midpointSightLineElevation(
            observerElevationMeters: 1_000,
            summitElevationMeters: 2_000,
            summitDistanceMeters: 10_000
        )
        let result = evaluator.evaluate(
            observerElevation: try #require(TerrainElevation(meters: 1_000)),
            summitElevation: try #require(TerrainElevation(meters: 2_000)),
            summitDistance: MountainDistance(meters: 10_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 2_500),
                    elevation: nil
                ),
                TerrainProfileSample(
                    distance: MountainDistance(meters: 5_000),
                    elevation: try #require(
                        TerrainElevation(meters: sightLineElevationMeters + 40)
                    )
                ),
            ]
        )

        guard case .occluded(let excessHeightMeters) = result else {
            Issue.record("既知地点の遮蔽を検出していません")
            return
        }
        #expect(abs(excessHeightMeters - 40) < 0.000_001)
    }

    @Test("遠方の見通しでは地球曲率を考慮する")
    func accountsForEarthCurvature() throws {
        let result = evaluator.evaluate(
            observerElevation: try #require(TerrainElevation(meters: 0)),
            summitElevation: try #require(TerrainElevation(meters: 0)),
            summitDistance: MountainDistance(meters: 50_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 25_000),
                    elevation: try #require(TerrainElevation(meters: -10))
                ),
            ]
        )

        guard case .occluded(let excessHeightMeters) = result else {
            Issue.record("地球曲率による途中地形の遮蔽を検出していません")
            return
        }
        #expect(excessHeightMeters > 30)
    }

    @Test("地形断面に欠損があれば見えていると推測しない")
    func returnsUnavailableForIncompleteProfile() throws {
        let result = evaluator.evaluate(
            observerElevation: try #require(TerrainElevation(meters: 1_000)),
            summitElevation: try #require(TerrainElevation(meters: 2_000)),
            summitDistance: MountainDistance(meters: 10_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 5_000),
                    elevation: nil
                ),
            ]
        )

        #expect(result == .unavailable)
    }

    @Test("観測地点の標高が未取得なら0mで代用しない")
    func returnsUnavailableWithoutObserverElevation() throws {
        let result = evaluator.evaluate(
            observerElevation: nil,
            summitElevation: try #require(TerrainElevation(meters: 2_000)),
            summitDistance: MountainDistance(meters: 10_000),
            samples: [
                TerrainProfileSample(
                    distance: MountainDistance(meters: 5_000),
                    elevation: try #require(TerrainElevation(meters: 1_500))
                ),
            ]
        )

        #expect(result == .unavailable)
    }

    private func midpointSightLineElevation(
        observerElevationMeters: Double,
        summitElevationMeters: Double,
        summitDistanceMeters: Double
    ) -> Double {
        let earthRadiusMeters = 6_371_008.8
        let observerRadius = earthRadiusMeters + observerElevationMeters
        let summitRadius = earthRadiusMeters + summitElevationMeters
        let summitAngle = summitDistanceMeters / earthRadiusMeters
        let midpointAngle = summitAngle / 2
        let denominator = summitRadius * sin(midpointAngle)
            + observerRadius * sin(midpointAngle)
        return observerRadius * summitRadius * sin(summitAngle) / denominator
            - earthRadiusMeters
    }
}
