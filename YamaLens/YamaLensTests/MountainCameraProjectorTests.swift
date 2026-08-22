import Foundation
import Testing
@testable import YamaLens

struct MountainCameraProjectorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let projector = MountainCameraProjector()

    @Test("正面の山を画面中央へ投影する")
    func projectsMountainInFront() throws {
        let result = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        let candidate = try #require(result.labels.first)
        #expect(abs(candidate.screenPoint.x - 200) < 1)
        #expect(abs(candidate.screenPoint.y - 400) < 5)
    }

    @Test("手動方位補正を東西の画面位置へ反映する")
    func appliesManualHeadingCorrection() throws {
        let eastward = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            manualHeadingCorrectionDegrees: 10,
            now: now
        )
        let westward = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            manualHeadingCorrectionDegrees: -10,
            now: now
        )

        let eastwardCandidate = try #require(eastward.labels.first)
        let westwardCandidate = try #require(westward.labels.first)
        #expect(eastwardCandidate.screenPoint.x > 200)
        #expect(westwardCandidate.screenPoint.x < 200)
    }

    @Test("背面の山を候補へ表示しない")
    func excludesMountainBehindCamera() {
        let result = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingSouth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        #expect(result.labels.isEmpty)
        #expect(result.sheetCandidates.isEmpty)
    }

    @Test("真上を向いた場合は水平線上の山を表示しない")
    func excludesMountainWhenLookingUp() {
        let result = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingUp()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        #expect(result.labels.isEmpty)
        #expect(result.sheetCandidates.isEmpty)
    }

    @Test("高度が未取得でも0mと仮定せず精度を下げて水平候補へ縮退する")
    func degradesWithoutAltitude() throws {
        let location = LocationObservation(
            coordinate: GeoCoordinate(latitude: 35, longitude: 139),
            horizontalAccuracyMeters: 5,
            observedAt: now
        )
        let result = projector.projectCandidates(
            location: location,
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        let candidate = try #require(result.sheetCandidates.first)
        #expect(candidate.elevationAngleDegrees == nil)
        #expect(candidate.strength == .candidate)
    }

    @Test("垂直精度が75mを超える高度は投影へ使用しない")
    func ignoresAltitudeWithUnusableVerticalAccuracy() throws {
        let location = LocationObservation(
            coordinate: GeoCoordinate(latitude: 35, longitude: 139),
            altitudeMeters: 1_000,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 75.01,
            observedAt: now
        )
        let result = projector.projectCandidates(
            location: location,
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        let candidate = try #require(result.sheetCandidates.first)
        #expect(candidate.elevationAngleDegrees == nil)
        #expect(candidate.strength == .candidate)
    }

    @Test("画面ラベルは5件、画角内候補は10件を上限とする")
    func limitsVisibleCandidateCounts() {
        let mountains = (0..<12).map { index in
            mountain(
                id: "north-\(index)",
                latitude: 35.01 + Double(index) * 0.000_01,
                longitude: 139 + Double(index - 6) * 0.000_01
            )
        }
        let result = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: mountains,
            retainedSheetMountainIDs: [],
            now: now
        )

        #expect(result.labels.count == 5)
        #expect(result.sheetCandidates.count == 10)
    }

    @Test("地形遮蔽候補は0.75倍へ減点しても候補シートから削除しない")
    func penalizesOccludedCandidateWithoutRemovingIt() throws {
        let mountain = mountain(id: "north", latitude: 35.01, longitude: 139)
        let baseline = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain],
            retainedSheetMountainIDs: [],
            now: now
        )
        let occluded = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain],
            retainedSheetMountainIDs: [],
            terrainVisibilityByMountainID: [
                mountain.id: .occluded(maximumExcessHeightMeters: 80),
            ],
            now: now
        )

        let baselineCandidate = try #require(baseline.sheetCandidates.first)
        let occludedCandidate = try #require(occluded.sheetCandidates.first)
        #expect(abs(occludedCandidate.score - baselineCandidate.score * 0.75) < 0.000_001)
        #expect(occludedCandidate.unpenalizedScore == baselineCandidate.score)
        #expect(occludedCandidate.terrainVisibility == .occluded(maximumExcessHeightMeters: 80))
    }

    @Test("地形未確認は候補scoreを変更しない")
    func leavesScoreUnchangedWhenTerrainIsUnavailable() throws {
        let result = projector.projectCandidates(
            location: location(),
            camera: camera(geometry: geometryFacingNorth()),
            mountains: [mountain(id: "north", latitude: 35.01, longitude: 139)],
            retainedSheetMountainIDs: [],
            now: now
        )

        let candidate = try #require(result.sheetCandidates.first)
        #expect(candidate.score == candidate.unpenalizedScore)
        #expect(candidate.terrainVisibility == .unavailable)
    }

    private func location() -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35, longitude: 139),
            altitudeMeters: 1_000,
            horizontalAccuracyMeters: 5,
            verticalAccuracyMeters: 5,
            observedAt: now
        )
    }

    private func camera(geometry: CameraProjectionGeometry) -> CameraPoseObservation {
        CameraPoseObservation(
            trueBearingDegrees: 0,
            pitchDegrees: 0,
            headingAccuracyDegrees: 5,
            observedAt: now,
            trackingQuality: .normal,
            projectionGeometry: geometry
        )
    }

    private func geometryFacingNorth() -> CameraProjectionGeometry {
        geometry(
            right: SpatialVector(x: 1, y: 0, z: 0),
            up: SpatialVector(x: 0, y: 1, z: 0),
            back: SpatialVector(x: 0, y: 0, z: 1)
        )
    }

    private func geometryFacingSouth() -> CameraProjectionGeometry {
        geometry(
            right: SpatialVector(x: -1, y: 0, z: 0),
            up: SpatialVector(x: 0, y: 1, z: 0),
            back: SpatialVector(x: 0, y: 0, z: -1)
        )
    }

    private func geometryFacingUp() -> CameraProjectionGeometry {
        geometry(
            right: SpatialVector(x: 1, y: 0, z: 0),
            up: SpatialVector(x: 0, y: 0, z: -1),
            back: SpatialVector(x: 0, y: -1, z: 0)
        )
    }

    private func geometry(
        right: SpatialVector,
        up: SpatialVector,
        back: SpatialVector
    ) -> CameraProjectionGeometry {
        let viewport = ViewportSize(width: 400, height: 800)
        return CameraProjectionGeometry(
            cameraRightInWorld: right,
            cameraUpInWorld: up,
            cameraBackInWorld: back,
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
    }

    private func mountain(
        id: String,
        latitude: Double,
        longitude: Double
    ) -> Mountain {
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
