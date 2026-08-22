import Foundation

nonisolated struct CameraCandidateStabilizer: Sendable {
    private struct StablePoint: Sendable {
        let point: ViewportPoint
        let updatedAt: Date
    }

    private let tuning: CandidateTuning
    private var stablePointsByMountainID: [String: StablePoint] = [:]

    init(tuning: CandidateTuning = .default) {
        self.tuning = tuning
    }

    mutating func stabilize(
        _ projection: CameraCandidateProjection,
        evaluatedAt: Date
    ) -> CameraCandidateProjection {
        let candidates = uniqueCandidates(
            projection.labels + projection.sheetCandidates
        )
        let activeIDs = Set(candidates.map(\.mountain.id))
        stablePointsByMountainID = stablePointsByMountainID.filter {
            activeIDs.contains($0.key)
        }

        var pointsByMountainID: [String: ViewportPoint] = [:]
        for candidate in candidates {
            let mountainID = candidate.mountain.id
            let point = stabilizedPoint(
                candidate.screenPoint,
                previous: stablePointsByMountainID[mountainID],
                evaluatedAt: evaluatedAt
            )
            stablePointsByMountainID[mountainID] = StablePoint(
                point: point,
                updatedAt: evaluatedAt
            )
            pointsByMountainID[mountainID] = point
        }

        return CameraCandidateProjection(
            labels: projection.labels.map {
                replacingScreenPoint(
                    of: $0,
                    with: pointsByMountainID[$0.mountain.id] ?? $0.screenPoint
                )
            },
            sheetCandidates: projection.sheetCandidates.map {
                replacingScreenPoint(
                    of: $0,
                    with: pointsByMountainID[$0.mountain.id] ?? $0.screenPoint
                )
            }
        )
    }

    mutating func reset() {
        stablePointsByMountainID = [:]
    }

    private func stabilizedPoint(
        _ current: ViewportPoint,
        previous: StablePoint?,
        evaluatedAt: Date
    ) -> ViewportPoint {
        guard let previous else { return current }
        let elapsedSeconds = evaluatedAt.timeIntervalSince(previous.updatedAt)
        guard
            elapsedSeconds.isFinite,
            elapsedSeconds > 0,
            elapsedSeconds <= tuning.maximumLabelStabilizationGapSeconds
        else {
            return elapsedSeconds == 0 ? previous.point : current
        }

        let displacement = hypot(
            current.x - previous.point.x,
            current.y - previous.point.y
        )
        guard displacement.isFinite else { return current }
        if displacement <= tuning.labelStabilizationDeadbandPoints {
            return previous.point
        }
        if displacement >= tuning.labelStabilizationFastFollowDistancePoints {
            return current
        }

        let progress = displacement / tuning.labelStabilizationFastFollowDistancePoints
        let timeConstant = tuning.labelStabilizationStationaryTimeConstantSeconds
            + (
                tuning.labelStabilizationMovingTimeConstantSeconds
                    - tuning.labelStabilizationStationaryTimeConstantSeconds
            ) * progress
        let blend = 1 - exp(-elapsedSeconds / timeConstant)
        return ViewportPoint(
            x: previous.point.x + (current.x - previous.point.x) * blend,
            y: previous.point.y + (current.y - previous.point.y) * blend
        )
    }

    private func uniqueCandidates(
        _ candidates: [CameraMountainCandidate]
    ) -> [CameraMountainCandidate] {
        var seenIDs: Set<String> = []
        return candidates.filter { seenIDs.insert($0.mountain.id).inserted }
    }

    private func replacingScreenPoint(
        of candidate: CameraMountainCandidate,
        with screenPoint: ViewportPoint
    ) -> CameraMountainCandidate {
        CameraMountainCandidate(
            mountain: candidate.mountain,
            proximity: candidate.proximity,
            screenPoint: screenPoint,
            elevationAngleDegrees: candidate.elevationAngleDegrees,
            unpenalizedScore: candidate.unpenalizedScore,
            score: candidate.score,
            strength: candidate.strength,
            terrainVisibility: candidate.terrainVisibility
        )
    }
}
