import Foundation
import Testing
@testable import YamaLens

@MainActor
struct LocationSessionModelTests {
    @Test("十分な精度の現在地を利用可能状態にする")
    func acceptsAccurateObservation() async {
        let observation = makeObservation(accuracy: 8)
        let model = makeModel(result: .success(observation))

        await model.requestLocation()

        #expect(model.state == .available(observation, quality: .good))
    }

    @Test("低精度だが利用可能な現在地を目安状態にする")
    func marksReducedAccuracy() async {
        let observation = makeObservation(accuracy: 50)
        let model = makeModel(result: .success(observation))

        await model.requestLocation()

        #expect(model.state == .available(observation, quality: .reduced))
    }

    @Test("100mを超える精度は利用しない")
    func rejectsInsufficientAccuracy() async {
        let model = makeModel(result: .success(makeObservation(accuracy: 101)))

        await model.requestLocation()

        #expect(model.state == .insufficientAccuracy)
    }

    @Test("位置情報拒否を回復可能な画面状態にする")
    func mapsDeniedPermission() async {
        let model = makeModel(result: .failure(.denied))

        await model.requestLocation()

        #expect(model.state == .denied)
    }

    @Test("設定で許可後にアプリへ戻ると現在地を再取得する")
    func refreshesAfterAuthorizationChangesInSettings() async {
        let provider = StubLocationObservationProvider(result: .failure(.denied))
        let model = LocationSessionModel(
            provider: provider,
            proximityCalculator: MountainProximityCalculator()
        )
        await model.requestLocation()
        #expect(model.state == .denied)

        let observation = makeObservation(accuracy: 8)
        provider.authorize(with: observation)
        await model.refreshAfterReturningFromSettings()

        #expect(model.state == .available(observation, quality: .good))
    }

    private func makeModel(
        result: Result<LocationObservation, LocationObservationFailure>
    ) -> LocationSessionModel {
        LocationSessionModel(
            provider: StubLocationObservationProvider(result: result),
            proximityCalculator: MountainProximityCalculator()
        )
    }

    private func makeObservation(accuracy: Double) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.47, longitude: 139.15),
            horizontalAccuracyMeters: accuracy,
            observedAt: Date(timeIntervalSince1970: 1_787_168_000)
        )
    }
}

@MainActor
private final class StubLocationObservationProvider: LocationObservationProvider {
    private var result: Result<LocationObservation, LocationObservationFailure>
    private var currentAuthorizationState: LocationAuthorizationState

    init(result: Result<LocationObservation, LocationObservationFailure>) {
        self.result = result
        switch result {
        case .success:
            currentAuthorizationState = .authorized
        case .failure(.denied):
            currentAuthorizationState = .denied
        case .failure(.restricted):
            currentAuthorizationState = .restricted
        case .failure:
            currentAuthorizationState = .unavailable
        }
    }

    func authorizationState() -> LocationAuthorizationState {
        currentAuthorizationState
    }

    func authorize(with observation: LocationObservation) {
        currentAuthorizationState = .authorized
        result = .success(observation)
    }

    func requestCurrentLocation() async -> Result<LocationObservation, LocationObservationFailure> {
        result
    }
}
