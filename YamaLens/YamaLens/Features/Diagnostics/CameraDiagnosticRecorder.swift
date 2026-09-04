import Foundation
import Observation

@MainActor
@Observable
final class CameraDiagnosticRecorder {
    private struct Session {
        let id: UUID
        let startedAt: Date
        var samples: [CameraDiagnosticSample]
        var events: [CameraDiagnosticEvent]
        var confirmedMountainID: String?
    }

    private let repository: any CameraDiagnosticLogRepository
    private let device: CameraDiagnosticDevice
    private let now: @MainActor () -> Date
    private let makeID: @MainActor () -> UUID
    private let policy: CameraDiagnosticPolicy
    private var bufferedSamples: [CameraDiagnosticSample] = []
    private var session: Session?

    private(set) var isRecording = false
    private(set) var isSaving = false
    private(set) var didReachSampleLimit = false
    private(set) var lastSavedAt: Date?
    private(set) var errorMessage: String?

    var sampleCount: Int { session?.samples.count ?? 0 }
    var confirmedMountainID: String? { session?.confirmedMountainID }

    init(
        repository: any CameraDiagnosticLogRepository,
        device: CameraDiagnosticDevice,
        policy: CameraDiagnosticPolicy = .default,
        now: @escaping @MainActor () -> Date = { .now },
        makeID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.device = device
        self.policy = policy
        self.now = now
        self.makeID = makeID
    }

    func observe(
        location: LocationObservation,
        locationQuality: LocationObservationQuality,
        camera: CameraPoseObservation,
        labels: [CameraMountainCandidate],
        candidates: [CameraMountainCandidate],
        quality: CameraEstimateQuality,
        manualHeadingCorrectionDegrees: Double,
        force: Bool = false
    ) {
        let recordedAt = now()
        let sample = makeSample(
            recordedAt: recordedAt,
            elapsedSeconds: 0,
            location: location,
            locationQuality: locationQuality,
            camera: camera,
            labels: labels,
            candidates: candidates,
            quality: quality,
            manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees
        )
        appendToBuffer(sample, force: force)
        appendToSession(sample, force: force)
    }

    @discardableResult
    func startRecording() -> UUID? {
        guard !isRecording, !isSaving else { return nil }
        let currentDate = now()
        let buffered = bufferedSamples.filter {
            currentDate.timeIntervalSince($0.recordedAt) <= policy.inMemoryBufferSeconds
        }
        let startedAt = buffered.first?.recordedAt ?? currentDate
        session = Session(
            id: makeID(),
            startedAt: startedAt,
            samples: buffered.map { sample in
                settingElapsedSeconds(
                    sample.recordedAt.timeIntervalSince(startedAt),
                    on: sample
                )
            },
            events: [],
            confirmedMountainID: nil
        )
        isRecording = true
        didReachSampleLimit = false
        errorMessage = nil
        lastSavedAt = nil
        return session?.id
    }

    func markIssue(_ kind: CameraDiagnosticEventKind) {
        guard isRecording, var session else { return }
        let recordedAt = now()
        session.events.append(
            CameraDiagnosticEvent(
                id: makeID(),
                recordedAt: recordedAt,
                elapsedSeconds: max(0, recordedAt.timeIntervalSince(session.startedAt)),
                kind: kind
            )
        )
        self.session = session
    }

    func setConfirmedMountainID(_ mountainID: String?) {
        guard isRecording, var session else { return }
        session.confirmedMountainID = mountainID
        self.session = session
    }

    func discardRecording() {
        session = nil
        isRecording = false
        isSaving = false
        didReachSampleLimit = false
        errorMessage = nil
    }

    @discardableResult
    func saveRecording(
        videoAttachment: CameraDiagnosticVideoAttachment? = nil
    ) async -> Bool {
        guard isRecording, !isSaving, let session else { return false }
        guard !session.samples.isEmpty else {
            errorMessage = "位置と姿勢の観測後に保存してください。"
            return false
        }

        isSaving = true
        isRecording = false
        let endedAt = now()
        let log = CameraDiagnosticLog(
            schemaVersion: CameraDiagnosticLog.currentSchemaVersion,
            id: session.id,
            startedAt: session.startedAt,
            endedAt: max(endedAt, session.startedAt),
            isRetained: false,
            device: device,
            samples: session.samples,
            events: session.events,
            confirmedMountainID: session.confirmedMountainID,
            videoAttachment: videoAttachment
        )

        do {
            try await repository.save(log)
            self.session = nil
            isSaving = false
            didReachSampleLimit = false
            lastSavedAt = endedAt
            errorMessage = nil
            return true
        } catch {
            self.session = session
            isRecording = true
            isSaving = false
            errorMessage = "診断ログを保存できませんでした。もう一度お試しください。"
            return false
        }
    }

    private func appendToBuffer(_ sample: CameraDiagnosticSample, force: Bool) {
        if !force, let last = bufferedSamples.last,
           sample.recordedAt.timeIntervalSince(last.recordedAt) < policy.samplingIntervalSeconds {
            return
        }
        bufferedSamples.append(sample)
        let cutoff = sample.recordedAt.addingTimeInterval(-policy.inMemoryBufferSeconds)
        bufferedSamples.removeAll { $0.recordedAt < cutoff }
    }

    private func appendToSession(_ sample: CameraDiagnosticSample, force: Bool) {
        guard isRecording, var session, !didReachSampleLimit else { return }
        if !force, let last = session.samples.last,
           sample.recordedAt.timeIntervalSince(last.recordedAt) < policy.samplingIntervalSeconds {
            return
        }
        guard session.samples.count < policy.maximumSampleCount else {
            didReachSampleLimit = true
            return
        }
        session.samples.append(
            settingElapsedSeconds(
                max(0, sample.recordedAt.timeIntervalSince(session.startedAt)),
                on: sample
            )
        )
        self.session = session
    }

    private func makeSample(
        recordedAt: Date,
        elapsedSeconds: TimeInterval,
        location: LocationObservation,
        locationQuality: LocationObservationQuality,
        camera: CameraPoseObservation,
        labels: [CameraMountainCandidate],
        candidates: [CameraMountainCandidate],
        quality: CameraEstimateQuality,
        manualHeadingCorrectionDegrees: Double
    ) -> CameraDiagnosticSample {
        let labelIDs = Set(labels.map(\.mountain.id))
        var candidatesByID = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.mountain.id, $0) }
        )
        for label in labels {
            candidatesByID[label.mountain.id] = label
        }
        let snapshots = candidatesByID.values
            .sorted { $0.mountain.id < $1.mountain.id }
            .map { candidate in
                CameraDiagnosticCandidate(
                    mountainID: candidate.mountain.id,
                    screenPoint: candidate.screenPoint,
                    score: candidate.score,
                    isLabelVisible: labelIDs.contains(candidate.mountain.id),
                    terrainVisibility: diagnosticTerrainVisibility(
                        candidate.terrainVisibility
                    )
                )
            }
        return CameraDiagnosticSample(
            recordedAt: recordedAt,
            elapsedSeconds: elapsedSeconds,
            location: location,
            locationQuality: locationQuality,
            camera: camera,
            estimateQuality: diagnosticQuality(quality),
            manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees,
            candidates: snapshots
        )
    }

    private func settingElapsedSeconds(
        _ elapsedSeconds: TimeInterval,
        on sample: CameraDiagnosticSample
    ) -> CameraDiagnosticSample {
        CameraDiagnosticSample(
            recordedAt: sample.recordedAt,
            elapsedSeconds: elapsedSeconds,
            location: sample.location,
            locationQuality: sample.locationQuality,
            camera: sample.camera,
            estimateQuality: sample.estimateQuality,
            manualHeadingCorrectionDegrees: sample.manualHeadingCorrectionDegrees,
            candidates: sample.candidates
        )
    }

    private func diagnosticQuality(
        _ quality: CameraEstimateQuality
    ) -> CameraDiagnosticEstimateQuality {
        switch quality {
        case .good:
            return .good
        case .reduced:
            return .reduced
        case .unavailable:
            return .unavailable
        }
    }

    private func diagnosticTerrainVisibility(
        _ visibility: TerrainVisibility
    ) -> CameraDiagnosticTerrainVisibility {
        switch visibility {
        case .notOccluded:
            return .notOccluded
        case .occluded:
            return .occluded
        case .unavailable:
            return .unavailable
        }
    }
}
