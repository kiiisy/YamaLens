import Foundation
import Testing
@testable import YamaLens

struct CameraCandidateStabilizerTests {
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("静止時の小さな画面座標ノイズを抑える")
    func reducesSmallScreenPointNoise() throws {
        var stabilizer = CameraCandidateStabilizer()
        let rawXValues = [200.0, 204, 196, 203, 197, 202]
        var stabilizedXValues: [Double] = []

        for (index, x) in rawXValues.enumerated() {
            let projection = stabilizer.stabilize(
                projection(x: x),
                evaluatedAt: startedAt.addingTimeInterval(Double(index) * 0.1)
            )
            stabilizedXValues.append(try #require(projection.labels.first?.screenPoint.x))
        }

        let rawRange = try #require(rawXValues.max()) - #require(rawXValues.min())
        let stabilizedRange = try #require(stabilizedXValues.max())
            - #require(stabilizedXValues.min())
        #expect(stabilizedRange < rawRange * 0.5)
    }

    @Test("大きなパン操作には遅延させず追従する")
    func followsLargeMovementImmediately() throws {
        var stabilizer = CameraCandidateStabilizer()
        _ = stabilizer.stabilize(projection(x: 200), evaluatedAt: startedAt)

        let moved = stabilizer.stabilize(
            projection(x: 280),
            evaluatedAt: startedAt.addingTimeInterval(0.1)
        )

        #expect(try #require(moved.labels.first?.screenPoint.x) == 280)
    }

    @Test("同じ観測の非同期再計算では表示位置を二重に進めない")
    func doesNotAdvanceForRepeatedEvaluationTime() throws {
        var stabilizer = CameraCandidateStabilizer()
        _ = stabilizer.stabilize(projection(x: 200), evaluatedAt: startedAt)
        let first = stabilizer.stabilize(
            projection(x: 210),
            evaluatedAt: startedAt.addingTimeInterval(0.1)
        )
        let repeated = stabilizer.stabilize(
            projection(x: 210),
            evaluatedAt: startedAt.addingTimeInterval(0.1)
        )

        #expect(repeated.labels.first?.screenPoint == first.labels.first?.screenPoint)
    }

    @Test("観測間隔が空いた場合は古い位置へ引っ張られない")
    func resetsAfterLongObservationGap() throws {
        var stabilizer = CameraCandidateStabilizer()
        _ = stabilizer.stabilize(projection(x: 200), evaluatedAt: startedAt)

        let resumed = stabilizer.stabilize(
            projection(x: 220),
            evaluatedAt: startedAt.addingTimeInterval(0.51)
        )

        #expect(try #require(resumed.labels.first?.screenPoint.x) == 220)
    }

    private func projection(x: Double) -> CameraCandidateProjection {
        let candidate = CameraMountainCandidate(
            mountain: Mountain(
                id: "tonodake",
                name: "塔ノ岳",
                aliases: [],
                regionName: "丹沢",
                prefectureName: "神奈川県",
                elevationMeters: 1_491,
                coordinate: GeoCoordinate(latitude: 35.4548, longitude: 139.1636)
            ),
            proximity: MountainProximity(
                distance: MountainDistance(meters: 2_400),
                bearing: TrueBearing(degrees: 137),
                direction: .southeast
            ),
            screenPoint: ViewportPoint(x: x, y: 360),
            elevationAngleDegrees: 8,
            unpenalizedScore: 0.9,
            score: 0.9,
            strength: .strong,
            terrainVisibility: .notOccluded
        )
        return CameraCandidateProjection(
            labels: [candidate],
            sheetCandidates: [candidate]
        )
    }
}
