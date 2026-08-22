import Foundation

nonisolated struct CameraDiagnosticReplayDifference: Equatable, Sendable {
    let mountainID: String
    let distancePoints: Double
}

nonisolated struct CameraDiagnosticReplayFrame: Equatable, Sendable {
    let sample: CameraDiagnosticSample
    let recordedLabels: [CameraDiagnosticCandidate]
    let recalculated: CameraCandidateProjection
    let differences: [CameraDiagnosticReplayDifference]

    var meanDifferencePoints: Double? {
        guard !differences.isEmpty else { return nil }
        return differences.map(\.distancePoints).reduce(0, +) / Double(differences.count)
    }

    var maximumDifferencePoints: Double? {
        differences.map(\.distancePoints).max()
    }
}

nonisolated struct CameraDiagnosticReplayCalculator: Sendable {
    private let projector: MountainCameraProjector
    private var stabilizer: CameraCandidateStabilizer

    init(
        projector: MountainCameraProjector,
        tuning: CandidateTuning = .default
    ) {
        self.projector = projector
        stabilizer = CameraCandidateStabilizer(tuning: tuning)
    }

    mutating func replay(
        samples: [CameraDiagnosticSample],
        mountains: [Mountain]
    ) -> [CameraDiagnosticReplayFrame] {
        stabilizer.reset()
        var retainedSheetMountainIDs: [String] = []

        return samples.map { sample in
            let rawProjection = projector.projectCandidates(
                location: sample.location,
                camera: sample.camera,
                mountains: mountains,
                retainedSheetMountainIDs: retainedSheetMountainIDs,
                manualHeadingCorrectionDegrees: sample.manualHeadingCorrectionDegrees,
                terrainVisibilityByMountainID: terrainVisibility(in: sample),
                now: sample.recordedAt
            )
            let recalculated = stabilizer.stabilize(
                rawProjection,
                evaluatedAt: sample.recordedAt
            )
            retainedSheetMountainIDs = recalculated.sheetCandidates.map(\.mountain.id)
            let recordedLabels = sample.candidates.filter(\.isLabelVisible)
            return CameraDiagnosticReplayFrame(
                sample: sample,
                recordedLabels: recordedLabels,
                recalculated: recalculated,
                differences: differences(
                    recordedLabels: recordedLabels,
                    recalculatedLabels: recalculated.labels
                )
            )
        }
    }

    private func terrainVisibility(
        in sample: CameraDiagnosticSample
    ) -> [String: TerrainVisibility] {
        Dictionary(uniqueKeysWithValues: sample.candidates.compactMap { candidate in
            guard let visibility = candidate.terrainVisibility else { return nil }
            let terrainVisibility: TerrainVisibility
            switch visibility {
            case .notOccluded:
                terrainVisibility = .notOccluded
            case .occluded:
                // 診断ログv1は遮蔽量を持たないが、順位付けに必要なのは遮蔽状態である。
                terrainVisibility = .occluded(maximumExcessHeightMeters: 0)
            case .unavailable:
                terrainVisibility = .unavailable
            }
            return (candidate.mountainID, terrainVisibility)
        })
    }

    private func differences(
        recordedLabels: [CameraDiagnosticCandidate],
        recalculatedLabels: [CameraMountainCandidate]
    ) -> [CameraDiagnosticReplayDifference] {
        let recalculatedByID = Dictionary(
            uniqueKeysWithValues: recalculatedLabels.map { ($0.mountain.id, $0) }
        )
        return recordedLabels.compactMap { recorded in
            guard let recalculated = recalculatedByID[recorded.mountainID] else {
                return nil
            }
            return CameraDiagnosticReplayDifference(
                mountainID: recorded.mountainID,
                distancePoints: hypot(
                    recorded.screenPoint.x - recalculated.screenPoint.x,
                    recorded.screenPoint.y - recalculated.screenPoint.y
                )
            )
        }
    }
}
