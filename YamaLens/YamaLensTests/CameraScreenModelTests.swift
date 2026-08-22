import Foundation
import Testing
@testable import YamaLens

@MainActor
struct CameraScreenModelTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("有効な現在地と方位から候補を表示する")
    func producesCandidatesFromValidObservations() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))

        model.receive(pose(age: 0, headingAccuracy: 5))

        guard case .active(_, _, let candidates, let quality) = model.state else {
            Issue.record("候補表示状態ではありません")
            return
        }
        #expect(!candidates.isEmpty)
        #expect(quality == .good)
    }

    @Test("方位が一時的に利用不能になると候補を消し、復帰後に再表示する")
    func recoversAfterHeadingBecomesAvailableAgain() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))

        model.receive(.temporarilyUnavailable)

        guard case .active(_, let labels, let candidates, let quality) = model.state else {
            Issue.record("方位利用不能状態を表示できません")
            return
        }
        #expect(labels.isEmpty)
        #expect(candidates.isEmpty)
        #expect(quality == .unavailable)

        model.receive(.pose(pose(age: 0, headingAccuracy: 5)))

        guard case .active(_, _, let recovered, let recoveredQuality) = model.state else {
            Issue.record("方位復帰後に候補表示へ戻れません")
            return
        }
        #expect(!recovered.isEmpty)
        #expect(recoveredQuality == .good)
    }

    @Test("方位復帰待ちの間に15秒を超えた現在地を先に更新する")
    func refreshesAgingLocationWhileHeadingIsUnavailable() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 15.01), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))

        model.receive(.temporarilyUnavailable)
        model.receive(.temporarilyUnavailable)

        #expect(model.locationRefreshRequestID == 1)
    }

    @Test("25度を超える方位精度では候補を重畳しない")
    func suppressesCandidatesForInvalidHeadingAccuracy() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))

        model.receive(pose(age: 0, headingAccuracy: 25.01))

        guard case .active(_, _, let candidates, let quality) = model.state else {
            Issue.record("精度低下状態を表示できません")
            return
        }
        #expect(candidates.isEmpty)
        #expect(quality == .unavailable)
    }

    @Test("3秒を超えた姿勢は候補に使用しない")
    func suppressesCandidatesForStalePose() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))

        model.receive(pose(age: 3.01, headingAccuracy: 5))

        guard case .active(_, _, let candidates, let quality) = model.state else {
            Issue.record("古い姿勢の状態を表示できません")
            return
        }
        #expect(candidates.isEmpty)
        #expect(quality == .unavailable)
    }

    @Test("15秒を超え60秒以内の現在地は精度低下を明示して候補を表示する")
    func marksStaleButUsableLocationAsReduced() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 15.01), quality: .good))

        model.receive(pose(age: 0, headingAccuracy: 5))

        guard case .active(_, _, let candidates, let quality) = model.state else {
            Issue.record("精度低下状態を表示できません")
            return
        }
        #expect(!candidates.isEmpty)
        #expect(quality == .reduced)
    }

    @Test("60秒を超えた現在地ではセンサー待機へ戻る")
    func waitsForFreshLocation() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 60.01), quality: .good))

        model.receive(pose(age: 0, headingAccuracy: 5))

        #expect(model.state == .waitingForSensors)
        #expect(model.locationRefreshRequestID == 1)

        model.updateLocationState(.available(location(age: 0), quality: .good))

        guard case .active = model.state else {
            Issue.record("新しい現在地で候補表示へ復帰できません")
            return
        }
    }

    @Test("手動方位補正を1度刻みで反映し左右30度に制限する")
    func adjustsAndClampsManualHeadingCorrection() throws {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))
        guard case .active(_, let initialLabels, _, _) = model.state else {
            Issue.record("候補表示状態ではありません")
            return
        }
        let initialX = try #require(initialLabels.first?.screenPoint.x)

        model.beginManualHeadingAdjustment()
        model.adjustManualHeadingByStep(1)

        #expect(model.isManualHeadingAdjustmentActive)
        #expect(model.manualHeadingCorrectionDegrees == 1)
        guard case .active(_, let adjustedLabels, _, _) = model.state else {
            Issue.record("補正後の候補表示状態ではありません")
            return
        }
        let adjustedX = try #require(adjustedLabels.first?.screenPoint.x)
        #expect(adjustedX > initialX)

        model.adjustManualHeadingByStep(100)
        #expect(model.manualHeadingCorrectionDegrees == 30)
        model.adjustManualHeadingByStep(-200)
        #expect(model.manualHeadingCorrectionDegrees == -30)

        model.resetManualHeadingCorrection()
        #expect(model.manualHeadingCorrectionDegrees == 0)
    }

    @Test("詳細への一時停止では補正を保持しカメラ終了で破棄する")
    func retainsCorrectionOnlyWhileCameraSessionContinues() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))
        model.setManualHeadingCorrection(degrees: 7)

        model.pauseForDetail()

        #expect(model.manualHeadingCorrectionDegrees == 7)
        #expect(!model.isManualHeadingAdjustmentActive)

        model.stop()

        #expect(model.manualHeadingCorrectionDegrees == 0)
    }

    @Test("非同期の地形遮蔽判定をカメラ候補へ反映する")
    func appliesAsynchronousTerrainVisibility() async {
        let resolver = FixedTerrainVisibilityResolver(
            result: ["north": .occluded(maximumExcessHeightMeters: 80)]
        )
        let model = makeModel(terrainVisibilityResolver: resolver)
        model.updateLocationState(.available(location(age: 0), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))

        for _ in 0..<100 {
            if case .active(_, _, let candidates, _) = model.state,
               candidates.first?.terrainVisibility
                == .occluded(maximumExcessHeightMeters: 80) {
                #expect(candidates.first?.score != candidates.first?.unpenalizedScore)
                return
            }
            await Task.yield()
        }
        Issue.record("地形判定がカメラ候補へ反映されませんでした")
    }

    @Test("方位復帰待ちを古い地形判定結果で上書きしない")
    func keepsHeadingUnavailableAfterTerrainEvaluationCompletes() async {
        let resolver = FixedTerrainVisibilityResolver(
            result: ["north": .occluded(maximumExcessHeightMeters: 80)]
        )
        let model = makeModel(terrainVisibilityResolver: resolver)
        model.updateLocationState(.available(location(age: 0), quality: .good))
        model.receive(pose(age: 0, headingAccuracy: 5))

        model.receive(.temporarilyUnavailable)
        for _ in 0..<20 {
            await Task.yield()
        }

        guard case .active(_, let labels, let candidates, let quality) = model.state else {
            Issue.record("方位利用不能状態を維持できません")
            return
        }
        #expect(labels.isEmpty)
        #expect(candidates.isEmpty)
        #expect(quality == .unavailable)
    }

    private func makeModel(
        terrainVisibilityResolver: (any TerrainVisibilityResolving)? = nil
    ) -> CameraScreenModel {
        CameraScreenModel(
            provider: InertCameraObservationProvider(),
            mountains: [testMountain],
            projector: MountainCameraProjector(),
            terrainVisibilityResolver: terrainVisibilityResolver,
            now: { fixedNow }
        )
    }

    private func location(age: TimeInterval) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.47, longitude: 139.145),
            altitudeMeters: 300,
            horizontalAccuracyMeters: 8,
            verticalAccuracyMeters: 8,
            observedAt: fixedNow.addingTimeInterval(-age)
        )
    }

    private func pose(age: TimeInterval, headingAccuracy: Double) -> CameraPoseObservation {
        CameraPoseObservation(
            trueBearingDegrees: 0,
            pitchDegrees: 0,
            headingAccuracyDegrees: headingAccuracy,
            observedAt: fixedNow.addingTimeInterval(-age),
            trackingQuality: .normal,
            projectionGeometry: projectionGeometry(facingDegrees: 0)
        )
    }

    private var testMountain: Mountain {
        Mountain(
            id: "north",
            name: "北の山",
            aliases: [],
            regionName: "テスト山域",
            prefectureName: "神奈川県",
            elevationMeters: 300,
            coordinate: GeoCoordinate(latitude: 35.48, longitude: 139.145)
        )
    }

    private func projectionGeometry(facingDegrees: Double) -> CameraProjectionGeometry {
        let radians = facingDegrees * .pi / 180
        let viewport = ViewportSize(width: 400, height: 800)
        return CameraProjectionGeometry(
            cameraRightInWorld: SpatialVector(
                x: cos(radians),
                y: 0,
                z: sin(radians)
            ),
            cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
            cameraBackInWorld: SpatialVector(
                x: -sin(radians),
                y: 0,
                z: cos(radians)
            ),
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
}

private nonisolated struct FixedTerrainVisibilityResolver: TerrainVisibilityResolving {
    let result: [String: TerrainVisibility]

    func resolveVisibility(
        from location: LocationObservation,
        to mountains: [Mountain]
    ) async throws -> [String: TerrainVisibility] {
        result
    }
}

@MainActor
private final class InertCameraObservationProvider: CameraObservationProvider {
    func start() async -> Result<Void, CameraSessionFailure> { .success(()) }
    func observations() -> AsyncStream<CameraObservationUpdate> { AsyncStream { _ in } }
    func stop() {}
}
