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

        guard case .active(_, let candidates, let quality) = model.state else {
            Issue.record("候補表示状態ではありません")
            return
        }
        #expect(!candidates.isEmpty)
        #expect(quality == .good)
    }

    @Test("25度を超える方位精度では候補を重畳しない")
    func suppressesCandidatesForInvalidHeadingAccuracy() {
        let model = makeModel()
        model.updateLocationState(.available(location(age: 0), quality: .good))

        model.receive(pose(age: 0, headingAccuracy: 25.01))

        guard case .active(_, let candidates, let quality) = model.state else {
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

        guard case .active(_, let candidates, let quality) = model.state else {
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

        guard case .active(_, let candidates, let quality) = model.state else {
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
    }

    private func makeModel() -> CameraScreenModel {
        CameraScreenModel(
            provider: InertCameraObservationProvider(),
            mountains: BootstrapMountainRepository().fetchMountains(),
            selector: HeadingCandidateSelector(),
            now: { fixedNow }
        )
    }

    private func location(age: TimeInterval) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.47, longitude: 139.145),
            horizontalAccuracyMeters: 8,
            observedAt: fixedNow.addingTimeInterval(-age)
        )
    }

    private func pose(age: TimeInterval, headingAccuracy: Double) -> CameraPoseObservation {
        CameraPoseObservation(
            trueBearingDegrees: 20,
            pitchDegrees: 2,
            headingAccuracyDegrees: headingAccuracy,
            observedAt: fixedNow.addingTimeInterval(-age),
            trackingQuality: .normal
        )
    }
}

@MainActor
private final class InertCameraObservationProvider: CameraObservationProvider {
    func start() async -> Result<Void, CameraSessionFailure> { .success(()) }
    func observations() -> AsyncStream<CameraPoseObservation> { AsyncStream { _ in } }
    func stop() {}
}
