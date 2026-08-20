import Observation

@MainActor
@Observable
final class LocationSessionModel {
    private let provider: any LocationObservationProvider
    private let proximityCalculator: MountainProximityCalculator

    private(set) var state: CurrentLocationState = .notRequested

    init(
        provider: any LocationObservationProvider,
        proximityCalculator: MountainProximityCalculator
    ) {
        self.provider = provider
        self.proximityCalculator = proximityCalculator
    }

    func requestLocation() async {
        guard state != .loading else { return }
        state = .loading

        let result = await provider.requestCurrentLocation()
        guard !Task.isCancelled else {
            state = .notRequested
            return
        }

        switch result {
        case .success(let observation):
            guard let quality = proximityCalculator.locationQuality(
                horizontalAccuracyMeters: observation.horizontalAccuracyMeters
            ) else {
                state = .insufficientAccuracy
                return
            }
            state = .available(observation, quality: quality)
        case .failure(let failure):
            state = state(for: failure)
        }
    }

    func refreshAfterReturningFromSettings() async {
        guard state == .denied || state == .restricted else { return }
        guard provider.authorizationState() == .authorized else { return }
        await requestLocation()
    }

    private func state(for failure: LocationObservationFailure) -> CurrentLocationState {
        switch failure {
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .servicesDisabled, .invalidObservation, .unavailable, .requestInProgress:
            return .unavailable
        }
    }
}
