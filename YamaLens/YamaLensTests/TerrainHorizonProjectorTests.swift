import Foundation
import Testing
@testable import YamaLens

struct TerrainHorizonProjectorTests {
    @Test("予測稜線をカメラ画面上の連続線へ投影する")
    func projectsVisibleHorizonSegment() throws {
        let projector = TerrainHorizonProjector()
        let samples = [-10.0, 0, 10].map {
            TerrainHorizonSample(bearingDegrees: $0, elevationAngleDegrees: 0)
        }

        let segments = projector.project(
            samples,
            camera: observation,
            manualHeadingCorrectionDegrees: 0
        )

        let segment = try #require(segments.first)
        #expect(segments.count == 1)
        #expect(segment.count == 3)
        #expect(segment[0].x < segment[1].x)
        #expect(segment[1].x < segment[2].x)
    }

    @Test("DEM欠損地点では予測線を接続しない")
    func splitsSegmentAtUnavailableSample() {
        let samples = [
            TerrainHorizonSample(bearingDegrees: -15, elevationAngleDegrees: 0),
            TerrainHorizonSample(bearingDegrees: -10, elevationAngleDegrees: 0),
            TerrainHorizonSample(bearingDegrees: 0, elevationAngleDegrees: nil),
            TerrainHorizonSample(bearingDegrees: 10, elevationAngleDegrees: 0),
            TerrainHorizonSample(bearingDegrees: 15, elevationAngleDegrees: 0),
        ]

        let segments = TerrainHorizonProjector().project(
            samples,
            camera: observation,
            manualHeadingCorrectionDegrees: 0
        )

        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.count == 2 })
    }

    private var observation: CameraPoseObservation {
        CameraPoseObservation(
            trueBearingDegrees: 0,
            pitchDegrees: 0,
            headingAccuracyDegrees: 5,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            trackingQuality: .normal,
            projectionGeometry: CameraProjectionGeometry(
                cameraRightInWorld: SpatialVector(x: 1, y: 0, z: 0),
                cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
                cameraBackInWorld: SpatialVector(x: 0, y: 0, z: 1),
                focalLengthXPixels: 300,
                focalLengthYPixels: 300,
                principalPointXPixels: 200,
                principalPointYPixels: 400,
                imageSizePixels: ViewportSize(width: 400, height: 800),
                normalizedImageToViewport: NormalizedImageTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: 1,
                    translationX: 0,
                    translationY: 0
                ),
                viewportSizePoints: ViewportSize(width: 400, height: 800),
                horizontalFieldOfViewDegrees: 70,
                verticalFieldOfViewDegrees: 100
            )
        )
    }
}
