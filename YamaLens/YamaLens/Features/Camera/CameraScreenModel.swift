import Foundation
import Observation

enum CameraScreenState: Equatable {
    case idle
    case starting
    case waitingForSensors
    case active(
        CameraPoseObservation,
        candidates: [HeadingCandidate],
        quality: CameraEstimateQuality
    )
    case cameraDenied
    case cameraRestricted
    case unsupported
    case unavailable
}

enum CameraEstimateQuality: Equatable {
    case good
    case reduced
    case unavailable
}

@MainActor
@Observable
final class CameraScreenModel {
    private let provider: any CameraObservationProvider
    private let mountains: [Mountain]
    private let selector: HeadingCandidateSelector
    private let tuning: CandidateTuning
    private let now: @MainActor () -> Date
    private var locationState: CurrentLocationState = .notRequested
    private var lastObservation: CameraPoseObservation?
    private var observationTask: Task<Void, Never>?

    private(set) var state: CameraScreenState = .idle

    init(
        provider: any CameraObservationProvider,
        mountains: [Mountain],
        selector: HeadingCandidateSelector,
        tuning: CandidateTuning = .default,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.provider = provider
        self.mountains = mountains
        self.selector = selector
        self.tuning = tuning
        self.now = now
    }

    func start() async {
        guard state == .idle || state == .cameraDenied || state == .unavailable else { return }
        state = .starting

        switch await provider.start() {
        case .success:
            state = .waitingForSensors
            observationTask?.cancel()
            observationTask = Task { [weak self, provider] in
                for await observation in provider.observations() {
                    guard !Task.isCancelled else { return }
                    self?.receive(observation)
                }
            }
        case .failure(let failure):
            state = state(for: failure)
        }
    }

    func updateLocationState(_ locationState: CurrentLocationState) {
        self.locationState = locationState
        guard let observation = lastObservation else { return }
        receive(observation)
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        provider.stop()
        lastObservation = nil
        state = .idle
    }

    func receive(_ observation: CameraPoseObservation) {
        lastObservation = observation
        guard case .available(let location, let locationQuality) = locationState else {
            state = .waitingForSensors
            return
        }

        let locationAge = now().timeIntervalSince(location.observedAt)
        guard locationAge >= -1, locationAge <= tuning.maximumLocationAgeSeconds else {
            state = .waitingForSensors
            return
        }
        let poseAge = now().timeIntervalSince(observation.observedAt)

        guard
            poseAge >= -1,
            poseAge <= tuning.maximumPoseAgeSeconds,
            observation.headingAccuracyDegrees.isFinite,
            observation.headingAccuracyDegrees >= 0,
            observation.headingAccuracyDegrees <= tuning.maximumHeadingAccuracyDegrees,
            observation.trackingQuality != .unavailable
        else {
            state = .active(observation, candidates: [], quality: .unavailable)
            return
        }

        let candidates = selector.candidates(
            from: location.coordinate,
            facing: observation.trueBearingDegrees,
            mountains: mountains,
            maximumCount: tuning.maximumSheetCandidateCount
        )
        let isGood = locationQuality == .good
            && locationAge <= tuning.freshLocationAgeSeconds
            && poseAge <= tuning.freshPoseAgeSeconds
            && observation.headingAccuracyDegrees <= tuning.goodHeadingAccuracyDegrees
            && observation.trackingQuality == .normal
        state = .active(
            observation,
            candidates: candidates,
            quality: isGood ? .good : .reduced
        )
    }

    private func state(for failure: CameraSessionFailure) -> CameraScreenState {
        switch failure {
        case .denied:
            return .cameraDenied
        case .restricted:
            return .cameraRestricted
        case .unsupported:
            return .unsupported
        case .unavailable:
            return .unavailable
        }
    }
}
