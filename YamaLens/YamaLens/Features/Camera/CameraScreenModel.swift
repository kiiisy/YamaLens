import Foundation
import Observation

enum CameraScreenState: Equatable {
    case idle
    case starting
    case waitingForSensors
    case active(
        CameraPoseObservation,
        labels: [CameraMountainCandidate],
        candidates: [CameraMountainCandidate],
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
    private let projector: MountainCameraProjector
    private let terrainVisibilityResolver: (any TerrainVisibilityResolving)?
    private let tuning: CandidateTuning
    private let now: @MainActor () -> Date
    let diagnosticRecorder: CameraDiagnosticRecorder?
    private var locationState: CurrentLocationState = .notRequested
    private var lastObservation: CameraPoseObservation?
    private var lastObservationEvaluationDate: Date?
    private var observationTask: Task<Void, Never>?
    private var retainedSheetMountainIDs: [String] = []
    private var locationTimestampRequestedForRefresh: Date?
    private var terrainVisibilityByMountainID: [String: TerrainVisibility] = [:]
    private var terrainLocationObservedAt: Date?
    private var terrainTask: Task<Void, Never>?
    private var terrainRequestGeneration = 0

    private(set) var state: CameraScreenState = .idle
    private(set) var locationRefreshRequestID = 0
    private(set) var manualHeadingCorrectionDegrees: Double = 0
    private(set) var isManualHeadingAdjustmentActive = false

    init(
        provider: any CameraObservationProvider,
        mountains: [Mountain],
        projector: MountainCameraProjector,
        tuning: CandidateTuning = .default,
        terrainVisibilityResolver: (any TerrainVisibilityResolving)? = nil,
        diagnosticRecorder: CameraDiagnosticRecorder? = nil,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.provider = provider
        self.mountains = mountains
        self.projector = projector
        self.tuning = tuning
        self.terrainVisibilityResolver = terrainVisibilityResolver
        self.diagnosticRecorder = diagnosticRecorder
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
                for await update in provider.observations() {
                    guard !Task.isCancelled else { return }
                    self?.receive(update)
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
        pauseForDetail()
        manualHeadingCorrectionDegrees = 0
        diagnosticRecorder?.discardRecording()
    }

    func pauseForDetail() {
        observationTask?.cancel()
        observationTask = nil
        provider.stop()
        lastObservation = nil
        lastObservationEvaluationDate = nil
        retainedSheetMountainIDs = []
        locationTimestampRequestedForRefresh = nil
        resetTerrainEvaluation()
        isManualHeadingAdjustmentActive = false
        state = .idle
    }

    func beginManualHeadingAdjustment() {
        guard case .active(_, _, _, let quality) = state, quality != .unavailable else { return }
        isManualHeadingAdjustmentActive = true
    }

    func finishManualHeadingAdjustment() {
        isManualHeadingAdjustmentActive = false
        recordCurrentDiagnosticSnapshot()
    }

    func adjustManualHeadingByStep(_ stepCount: Int) {
        let change = Double(stepCount) * tuning.manualHeadingCorrectionStepDegrees
        setManualHeadingCorrection(degrees: manualHeadingCorrectionDegrees + change)
    }

    func setManualHeadingCorrection(degrees: Double) {
        guard degrees.isFinite else { return }
        manualHeadingCorrectionDegrees = min(
            max(degrees, -tuning.maximumManualHeadingCorrectionDegrees),
            tuning.maximumManualHeadingCorrectionDegrees
        )
        reprojectLastObservation()
    }

    func resetManualHeadingCorrection() {
        setManualHeadingCorrection(degrees: 0)
    }

    func receive(_ observation: CameraPoseObservation) {
        receive(observation, evaluatedAt: now())
    }

    private func receive(
        _ observation: CameraPoseObservation,
        evaluatedAt evaluationDate: Date
    ) {
        lastObservation = observation
        lastObservationEvaluationDate = evaluationDate
        guard case .available(let location, let locationQuality) = locationState else {
            resetTerrainEvaluation()
            state = .waitingForSensors
            return
        }
        prepareTerrainEvaluation(for: location)

        let locationAge = evaluationDate.timeIntervalSince(location.observedAt)
        guard locationAge >= -1, locationAge <= tuning.maximumLocationAgeSeconds else {
            state = .waitingForSensors
            requestLocationRefreshIfNeeded(for: location.observedAt)
            return
        }
        locationTimestampRequestedForRefresh = nil
        let poseAge = evaluationDate.timeIntervalSince(observation.observedAt)

        guard
            poseAge >= -1,
            poseAge <= tuning.maximumPoseAgeSeconds,
            observation.headingAccuracyDegrees.isFinite,
            observation.headingAccuracyDegrees >= 0,
            observation.headingAccuracyDegrees <= tuning.maximumHeadingAccuracyDegrees,
            observation.trackingQuality != .unavailable
        else {
            retainedSheetMountainIDs = []
            setActiveState(
                observation,
                labels: [],
                candidates: [],
                quality: .unavailable
            )
            return
        }

        let projection = projector.projectCandidates(
            location: location,
            camera: observation,
            mountains: mountains,
            retainedSheetMountainIDs: retainedSheetMountainIDs,
            manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees,
            terrainVisibilityByMountainID: terrainVisibilityByMountainID,
            now: evaluationDate
        )
        retainedSheetMountainIDs = projection.sheetCandidates.map(\.mountain.id)
        let isGood = locationQuality == .good
            && locationAge <= tuning.freshLocationAgeSeconds
            && poseAge <= tuning.freshPoseAgeSeconds
            && observation.headingAccuracyDegrees <= tuning.goodHeadingAccuracyDegrees
            && observation.trackingQuality == .normal
            && hasGoodAltitude(location)
        setActiveState(
            observation,
            labels: projection.labels,
            candidates: projection.sheetCandidates,
            quality: isGood ? .good : .reduced
        )
        scheduleTerrainEvaluationIfNeeded(
            location: location,
            projection: projection
        )
    }

    func receive(_ update: CameraObservationUpdate) {
        switch update {
        case .pose(let observation):
            receive(observation)
        case .temporarilyUnavailable:
            retainedSheetMountainIDs = []
            if case .available(let location, _) = locationState {
                let locationAge = now().timeIntervalSince(location.observedAt)
                if locationAge > tuning.freshLocationAgeSeconds {
                    requestLocationRefreshIfNeeded(for: location.observedAt)
                }
            }
            guard let lastObservation else {
                state = .waitingForSensors
                return
            }
            setActiveState(
                lastObservation,
                labels: [],
                candidates: [],
                quality: .unavailable
            )
        }
    }

    private func requestLocationRefreshIfNeeded(for observedAt: Date) {
        guard locationTimestampRequestedForRefresh != observedAt else { return }
        locationTimestampRequestedForRefresh = observedAt
        locationRefreshRequestID += 1
    }

    func startDiagnosticRecording() {
        diagnosticRecorder?.startRecording()
    }

    func saveDiagnosticRecording() async {
        recordCurrentDiagnosticSnapshot()
        await diagnosticRecorder?.saveRecording()
    }

    func discardDiagnosticRecording() {
        diagnosticRecorder?.discardRecording()
    }

    func markDiagnosticIssue(_ kind: CameraDiagnosticEventKind) {
        diagnosticRecorder?.markIssue(kind)
    }

    func setDiagnosticConfirmedMountain(_ mountainID: String?) {
        diagnosticRecorder?.setConfirmedMountainID(mountainID)
    }

    private func reprojectLastObservation() {
        reprojectLastObservation(preservingRetainedCandidates: false)
    }

    private func reprojectLastObservation(preservingRetainedCandidates: Bool) {
        if !preservingRetainedCandidates {
            retainedSheetMountainIDs = []
        }
        guard let lastObservation, let lastObservationEvaluationDate else { return }
        receive(lastObservation, evaluatedAt: lastObservationEvaluationDate)
    }

    private func prepareTerrainEvaluation(for location: LocationObservation) {
        guard terrainLocationObservedAt != location.observedAt else { return }
        resetTerrainEvaluation()
        terrainLocationObservedAt = location.observedAt
    }

    private func scheduleTerrainEvaluationIfNeeded(
        location: LocationObservation,
        projection: CameraCandidateProjection
    ) {
        guard let terrainVisibilityResolver, terrainTask == nil else { return }
        let candidateMountains = uniqueMountains(
            projection.labels.map(\.mountain) + projection.sheetCandidates.map(\.mountain)
        ).filter { terrainVisibilityByMountainID[$0.id] == nil }
        guard !candidateMountains.isEmpty else { return }

        terrainRequestGeneration += 1
        let requestGeneration = terrainRequestGeneration
        let locationObservedAt = location.observedAt
        terrainTask = Task { [weak self, terrainVisibilityResolver] in
            let result: [String: TerrainVisibility]
            do {
                result = try await terrainVisibilityResolver.resolveVisibility(
                    from: location,
                    to: candidateMountains
                )
            } catch {
                result = Dictionary(
                    uniqueKeysWithValues: candidateMountains.map { ($0.id, .unavailable) }
                )
            }
            guard !Task.isCancelled else { return }
            self?.applyTerrainVisibility(
                result,
                locationObservedAt: locationObservedAt,
                requestGeneration: requestGeneration
            )
        }
    }

    private func applyTerrainVisibility(
        _ result: [String: TerrainVisibility],
        locationObservedAt: Date,
        requestGeneration: Int
    ) {
        guard
            terrainLocationObservedAt == locationObservedAt,
            terrainRequestGeneration == requestGeneration
        else {
            return
        }
        terrainTask = nil
        terrainVisibilityByMountainID.merge(result) { _, new in new }
        reprojectLastObservation(preservingRetainedCandidates: true)
    }

    private func resetTerrainEvaluation() {
        terrainRequestGeneration += 1
        terrainTask?.cancel()
        terrainTask = nil
        terrainVisibilityByMountainID = [:]
        terrainLocationObservedAt = nil
    }

    private func uniqueMountains(_ mountains: [Mountain]) -> [Mountain] {
        var seenIDs: Set<String> = []
        return mountains.filter { seenIDs.insert($0.id).inserted }
    }

    private func setActiveState(
        _ observation: CameraPoseObservation,
        labels: [CameraMountainCandidate],
        candidates: [CameraMountainCandidate],
        quality: CameraEstimateQuality
    ) {
        state = .active(
            observation,
            labels: labels,
            candidates: candidates,
            quality: quality
        )
        guard case .available(let location, let locationQuality) = locationState else { return }
        diagnosticRecorder?.observe(
            location: location,
            locationQuality: locationQuality,
            camera: observation,
            labels: labels,
            candidates: candidates,
            quality: quality,
            manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees
        )
    }

    private func recordCurrentDiagnosticSnapshot() {
        guard
            case .active(let observation, let labels, let candidates, let quality) = state,
            case .available(let location, let locationQuality) = locationState
        else {
            return
        }
        diagnosticRecorder?.observe(
            location: location,
            locationQuality: locationQuality,
            camera: observation,
            labels: labels,
            candidates: candidates,
            quality: quality,
            manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees,
            force: true
        )
    }

    private func hasGoodAltitude(_ location: LocationObservation) -> Bool {
        guard
            location.altitudeMeters?.isFinite == true,
            let verticalAccuracy = location.verticalAccuracyMeters,
            verticalAccuracy.isFinite,
            verticalAccuracy >= 0
        else {
            return false
        }
        return verticalAccuracy <= tuning.goodVerticalAccuracyMeters
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
