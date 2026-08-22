import Foundation
import Testing
@testable import YamaLens

struct CameraDiagnosticReplayCalculatorTests {
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let projector = MountainCameraProjector()

    @Test("診断ログを先頭から処理してラベル安定化状態を引き継ぐ")
    func replaysStabilizationChronologically() throws {
        let samples = [
            sample(elapsedSeconds: 0, manualCorrectionDegrees: 0),
            sample(elapsedSeconds: 0.2, manualCorrectionDegrees: 2),
        ]
        let mountain = mountain()
        var calculator = CameraDiagnosticReplayCalculator(projector: projector)

        let frames = calculator.replay(samples: samples, mountains: [mountain])
        let initialX = try #require(frames.first?.recalculated.labels.first?.screenPoint.x)
        let stabilizedX = try #require(frames.last?.recalculated.labels.first?.screenPoint.x)
        let rawX = try #require(
            projector.projectCandidates(
                location: location(at: startedAt.addingTimeInterval(0.2)),
                camera: camera(at: startedAt.addingTimeInterval(0.2)),
                mountains: [mountain],
                retainedSheetMountainIDs: [mountain.id],
                manualHeadingCorrectionDegrees: 2,
                now: startedAt.addingTimeInterval(0.2)
            ).labels.first?.screenPoint.x
        )

        #expect(abs(stabilizedX - initialX) < abs(rawX - initialX))
        #expect(abs(stabilizedX - rawX) > 0.1)
    }

    @Test("記録時と再計算後の同じ候補について画面上の位置差を算出する")
    func calculatesRecordedPositionDifference() throws {
        let recordedPoint = ViewportPoint(x: 212, y: 400)
        let replaySample = sample(
            elapsedSeconds: 0,
            manualCorrectionDegrees: 0,
            candidates: [
                CameraDiagnosticCandidate(
                    mountainID: mountain().id,
                    screenPoint: recordedPoint,
                    score: 0.9,
                    isLabelVisible: true,
                    terrainVisibility: .notOccluded
                ),
            ]
        )
        var calculator = CameraDiagnosticReplayCalculator(projector: projector)

        let frame = try #require(
            calculator.replay(samples: [replaySample], mountains: [mountain()]).first
        )
        let recalculatedPoint = try #require(frame.recalculated.labels.first?.screenPoint)
        let expectedDifference = hypot(
            recordedPoint.x - recalculatedPoint.x,
            recordedPoint.y - recalculatedPoint.y
        )

        #expect(frame.differences.count == 1)
        #expect(abs(try #require(frame.meanDifferencePoints) - expectedDifference) < 0.000_001)
        #expect(frame.maximumDifferencePoints == frame.meanDifferencePoints)
    }

    @Test("ログに保存された地形遮蔽状態を現在の順位付けへ反映する")
    func restoresTerrainVisibility() throws {
        let replaySample = sample(
            elapsedSeconds: 0,
            manualCorrectionDegrees: 0,
            candidates: [
                CameraDiagnosticCandidate(
                    mountainID: mountain().id,
                    screenPoint: ViewportPoint(x: 200, y: 400),
                    score: 0.7,
                    isLabelVisible: true,
                    terrainVisibility: .occluded
                ),
            ]
        )
        var calculator = CameraDiagnosticReplayCalculator(projector: projector)

        let candidate = try #require(
            calculator.replay(samples: [replaySample], mountains: [mountain()])
                .first?.recalculated.sheetCandidates.first
        )

        #expect(candidate.terrainVisibility == .occluded(maximumExcessHeightMeters: 0))
        #expect(abs(candidate.score - candidate.unpenalizedScore * 0.75) < 0.000_001)
    }

    private func sample(
        elapsedSeconds: TimeInterval,
        manualCorrectionDegrees: Double,
        candidates: [CameraDiagnosticCandidate] = []
    ) -> CameraDiagnosticSample {
        let date = startedAt.addingTimeInterval(elapsedSeconds)
        return CameraDiagnosticSample(
            recordedAt: date,
            elapsedSeconds: elapsedSeconds,
            location: location(at: date),
            locationQuality: .good,
            camera: camera(at: date),
            estimateQuality: .good,
            manualHeadingCorrectionDegrees: manualCorrectionDegrees,
            candidates: candidates
        )
    }

    private func location(at date: Date) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35, longitude: 139),
            altitudeMeters: 1_000,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 5,
            observedAt: date
        )
    }

    private func camera(at date: Date) -> CameraPoseObservation {
        let viewport = ViewportSize(width: 400, height: 800)
        return CameraPoseObservation(
            trueBearingDegrees: 0,
            pitchDegrees: 0,
            headingAccuracyDegrees: 5,
            observedAt: date,
            trackingQuality: .normal,
            projectionGeometry: CameraProjectionGeometry(
                cameraRightInWorld: SpatialVector(x: 1, y: 0, z: 0),
                cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
                cameraBackInWorld: SpatialVector(x: 0, y: 0, z: 1),
                focalLengthXPixels: 300,
                focalLengthYPixels: 300,
                principalPointXPixels: 200,
                principalPointYPixels: 400,
                imageSizePixels: viewport,
                normalizedImageToViewport: NormalizedImageTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: 1,
                    translationX: 0,
                    translationY: 0
                ),
                viewportSizePoints: viewport,
                horizontalFieldOfViewDegrees: 70,
                verticalFieldOfViewDegrees: 100
            )
        )
    }

    private func mountain() -> Mountain {
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
