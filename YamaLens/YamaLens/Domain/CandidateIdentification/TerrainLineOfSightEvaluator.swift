import Foundation

nonisolated struct TerrainLineOfSightEvaluator: Sendable {
    private let obstructionClearanceMeters: Double
    private let earthRadiusMeters = 6_371_008.8

    init(tuning: CandidateTuning = .default) {
        obstructionClearanceMeters = tuning.terrainOcclusionClearanceMeters
    }

    /// 地形断面を直線視線と比較する。欠損が残る場合は、既知の地点で遮蔽を
    /// 検出できた場合を除き、見えていると推測せず判定不能を返す。
    func evaluate(
        observerElevation: TerrainElevation?,
        summitElevation: TerrainElevation,
        summitDistance: MountainDistance,
        samples: [TerrainProfileSample]
    ) -> TerrainVisibility {
        guard
            let observerElevation,
            summitDistance.meters.isFinite,
            summitDistance.meters > 0,
            obstructionClearanceMeters.isFinite,
            obstructionClearanceMeters >= 0,
            !samples.isEmpty
        else {
            return .unavailable
        }

        var hasUnavailableSample = false
        var hasUsableSample = false
        var maximumExcessHeightMeters = -Double.infinity

        for sample in samples {
            let distanceMeters = sample.distance.meters
            guard
                distanceMeters.isFinite,
                distanceMeters > 0,
                distanceMeters < summitDistance.meters
            else {
                hasUnavailableSample = true
                continue
            }
            guard let elevation = sample.elevation else {
                hasUnavailableSample = true
                continue
            }

            hasUsableSample = true
            guard let sightLineElevationMeters = sightLineElevation(
                observerElevationMeters: observerElevation.meters,
                summitElevationMeters: summitElevation.meters,
                summitDistanceMeters: summitDistance.meters,
                sampleDistanceMeters: distanceMeters
            ) else {
                hasUnavailableSample = true
                continue
            }
            let excessHeightMeters = elevation.meters - sightLineElevationMeters
            maximumExcessHeightMeters = max(maximumExcessHeightMeters, excessHeightMeters)
        }

        if hasUsableSample, maximumExcessHeightMeters >= obstructionClearanceMeters {
            return .occluded(maximumExcessHeightMeters: maximumExcessHeightMeters)
        }
        guard hasUsableSample, !hasUnavailableSample else {
            return .unavailable
        }
        return .notOccluded
    }

    /// 地表面に沿った距離を球面上の中心角へ変換し、観測地点と山頂を結ぶ
    /// 直線が途中地点で通る標高を求める。遠方で地球曲率を無視してしまうのを防ぐ。
    private func sightLineElevation(
        observerElevationMeters: Double,
        summitElevationMeters: Double,
        summitDistanceMeters: Double,
        sampleDistanceMeters: Double
    ) -> Double? {
        let observerRadius = earthRadiusMeters + observerElevationMeters
        let summitRadius = earthRadiusMeters + summitElevationMeters
        guard observerRadius > 0, summitRadius > 0 else { return nil }

        let summitAngle = summitDistanceMeters / earthRadiusMeters
        let sampleAngle = sampleDistanceMeters / earthRadiusMeters
        guard summitAngle > 0, summitAngle < .pi, sampleAngle > 0, sampleAngle < summitAngle else {
            return nil
        }

        let denominator = summitRadius * sin(summitAngle - sampleAngle)
            + observerRadius * sin(sampleAngle)
        guard denominator.isFinite, denominator > 0 else { return nil }
        let sightLineRadius = observerRadius * summitRadius * sin(summitAngle) / denominator
        let elevationMeters = sightLineRadius - earthRadiusMeters
        return elevationMeters.isFinite ? elevationMeters : nil
    }
}
