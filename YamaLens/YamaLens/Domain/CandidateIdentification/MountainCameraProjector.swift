import Foundation

nonisolated enum CameraCandidateStrength: Equatable, Sendable {
    case strong
    case candidate
}

nonisolated struct CameraMountainCandidate: Equatable, Sendable {
    let mountain: Mountain
    let proximity: MountainProximity
    let screenPoint: ViewportPoint
    let elevationAngleDegrees: Double?
    let unpenalizedScore: Double
    let score: Double
    let strength: CameraCandidateStrength
    let terrainVisibility: TerrainVisibility
}

nonisolated struct CameraCandidateProjection: Equatable, Sendable {
    let labels: [CameraMountainCandidate]
    let sheetCandidates: [CameraMountainCandidate]
}

nonisolated struct MountainCameraProjector: Sendable {
    private let proximityCalculator: MountainProximityCalculator
    private let tuning: CandidateTuning

    init(
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator(),
        tuning: CandidateTuning = .default
    ) {
        self.proximityCalculator = proximityCalculator
        self.tuning = tuning
    }

    func projectCandidates(
        location: LocationObservation,
        camera: CameraPoseObservation,
        mountains: [Mountain],
        retainedSheetMountainIDs: [String],
        manualHeadingCorrectionDegrees: Double = 0,
        terrainVisibilityByMountainID: [String: TerrainVisibility] = [:],
        now: Date
    ) -> CameraCandidateProjection {
        guard manualHeadingCorrectionDegrees.isFinite else {
            return CameraCandidateProjection(labels: [], sheetCandidates: [])
        }
        let locationAge = now.timeIntervalSince(location.observedAt)
        let poseAge = now.timeIntervalSince(camera.observedAt)
        guard
            isUsable(age: locationAge, maximum: tuning.maximumLocationAgeSeconds),
            isUsable(age: poseAge, maximum: tuning.maximumPoseAgeSeconds),
            isUsableHeading(camera.headingAccuracyDegrees),
            camera.trackingQuality != .unavailable
        else {
            return CameraCandidateProjection(labels: [], sheetCandidates: [])
        }

        let qualityScore = observationQualityScore(
            location: location,
            camera: camera,
            locationAge: locationAge,
            poseAge: poseAge
        )
        guard qualityScore > 0 else {
            return CameraCandidateProjection(labels: [], sheetCandidates: [])
        }

        let projected = proximityCalculator
            .nearbyMountains(from: location.coordinate, mountains: mountains)
            .compactMap { nearby in
                project(
                    nearby,
                    location: location,
                    camera: camera,
                    manualHeadingCorrectionDegrees: manualHeadingCorrectionDegrees,
                    qualityScore: qualityScore,
                    terrainVisibility: terrainVisibilityByMountainID[nearby.mountain.id]
                        ?? .unavailable
                )
            }
            .sorted(by: candidatePrecedes)

        let labels = projected
            .filter { isInsideViewport($0.screenPoint, geometry: camera.projectionGeometry) }
            .filter { $0.score >= tuning.cameraCandidateScore }
            .prefix(tuning.maximumCameraLabelCount)
            .map { $0 }

        let extendedCandidates = projected.filter {
            isInsideExtendedViewport($0.screenPoint, geometry: camera.projectionGeometry)
                && $0.unpenalizedScore >= tuning.sheetCandidateScore
        }
        let byID = Dictionary(uniqueKeysWithValues: extendedCandidates.map { ($0.mountain.id, $0) })
        let retained = retainedSheetMountainIDs.compactMap { byID[$0] }
        let retainedIDs = Set(retained.map(\.mountain.id))
        let entering = extendedCandidates.filter {
            !retainedIDs.contains($0.mountain.id)
                && isInsideViewport($0.screenPoint, geometry: camera.projectionGeometry)
        }
        let sheetCandidates = (retained + entering)
            .prefix(tuning.maximumSheetCandidateCount)
            .map { $0 }

        return CameraCandidateProjection(labels: labels, sheetCandidates: sheetCandidates)
    }

    private func project(
        _ nearby: NearbyMountain,
        location: LocationObservation,
        camera: CameraPoseObservation,
        manualHeadingCorrectionDegrees: Double,
        qualityScore: Double,
        terrainVisibility: TerrainVisibility
    ) -> CameraMountainCandidate? {
        guard let direction = worldDirection(
            from: location,
            to: nearby.mountain
        ) else {
            return nil
        }
        guard let screenPoint = camera.projectionGeometry.project(
            worldDirection: corrected(
                direction.vector,
                byDegrees: manualHeadingCorrectionDegrees
            )
        ) else {
            return nil
        }

        let geometry = camera.projectionGeometry
        let horizontalScore = centeredScore(
            coordinate: screenPoint.x,
            length: geometry.viewportSizePoints.width,
            fieldOfViewDegrees: geometry.horizontalFieldOfViewDegrees
        )
        let verticalScore = direction.elevationAngleDegrees == nil
            ? 0.5
            : centeredScore(
                coordinate: screenPoint.y,
                length: geometry.viewportSizePoints.height,
                fieldOfViewDegrees: geometry.verticalFieldOfViewDegrees
            )
        let distanceScore = clamp(
            1 - nearby.proximity.distance.meters / tuning.maximumSearchDistanceMeters
        )
        let unpenalizedScore = tuning.bearingScoreWeight * horizontalScore
            + tuning.elevationScoreWeight * verticalScore
            + tuning.observationQualityScoreWeight * qualityScore
            + tuning.distanceScoreWeight * distanceScore
        let score: Double
        switch terrainVisibility {
        case .occluded:
            score = unpenalizedScore * tuning.terrainOcclusionScoreMultiplier
        case .notOccluded, .unavailable:
            score = unpenalizedScore
        }
        let strength: CameraCandidateStrength = score >= tuning.strongCandidateScore
            && qualityScore == 1
            ? .strong
            : .candidate

        return CameraMountainCandidate(
            mountain: nearby.mountain,
            proximity: nearby.proximity,
            screenPoint: screenPoint,
            elevationAngleDegrees: direction.elevationAngleDegrees,
            unpenalizedScore: unpenalizedScore,
            score: score,
            strength: strength,
            terrainVisibility: terrainVisibility
        )
    }

    private func corrected(
        _ direction: SpatialVector,
        byDegrees correctionDegrees: Double
    ) -> SpatialVector {
        let radians = correctionDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return SpatialVector(
            x: direction.x * cosine - direction.z * sine,
            y: direction.y,
            z: direction.x * sine + direction.z * cosine
        )
    }

    private func worldDirection(
        from location: LocationObservation,
        to mountain: Mountain
    ) -> (vector: SpatialVector, elevationAngleDegrees: Double?)? {
        guard let originAltitude = usableAltitude(from: location) else {
            guard let bearing = proximityCalculator
                .proximity(from: location.coordinate, to: mountain.coordinate)?
                .bearing?
                .degrees
            else {
                return nil
            }
            let radians = bearing * .pi / 180
            return (
                SpatialVector(x: sin(radians), y: 0, z: -cos(radians)),
                nil
            )
        }
        guard originAltitude.isFinite else { return nil }

        let originECEF = ecef(
            coordinate: location.coordinate,
            altitudeMeters: originAltitude
        )
        let mountainECEF = ecef(
            coordinate: mountain.coordinate,
            altitudeMeters: Double(mountain.elevationMeters)
        )
        guard let originECEF, let mountainECEF else { return nil }

        let delta = SpatialVector(
            x: mountainECEF.x - originECEF.x,
            y: mountainECEF.y - originECEF.y,
            z: mountainECEF.z - originECEF.z
        )
        let latitude = location.coordinate.latitude * .pi / 180
        let longitude = location.coordinate.longitude * .pi / 180
        let east = -sin(longitude) * delta.x + cos(longitude) * delta.y
        let north = -sin(latitude) * cos(longitude) * delta.x
            - sin(latitude) * sin(longitude) * delta.y
            + cos(latitude) * delta.z
        let up = cos(latitude) * cos(longitude) * delta.x
            + cos(latitude) * sin(longitude) * delta.y
            + sin(latitude) * delta.z
        let length = sqrt(east * east + north * north + up * up)
        guard length.isFinite, length > 0 else { return nil }

        let elevation = atan2(up, hypot(east, north)) * 180 / .pi
        return (
            SpatialVector(x: east / length, y: up / length, z: -north / length),
            elevation
        )
    }

    private func usableAltitude(from location: LocationObservation) -> Double? {
        guard
            let altitude = location.altitudeMeters,
            altitude.isFinite,
            let verticalAccuracy = location.verticalAccuracyMeters,
            verticalAccuracy.isFinite,
            verticalAccuracy >= 0,
            verticalAccuracy <= tuning.maximumVerticalAccuracyMeters
        else {
            return nil
        }
        return altitude
    }

    private func ecef(
        coordinate: GeoCoordinate,
        altitudeMeters: Double
    ) -> SpatialVector? {
        guard
            coordinate.latitude.isFinite,
            coordinate.longitude.isFinite,
            altitudeMeters.isFinite,
            (-90...90).contains(coordinate.latitude),
            (-180...180).contains(coordinate.longitude)
        else {
            return nil
        }

        let semiMajorAxis = 6_378_137.0
        let eccentricitySquared = 6.694_379_990_14e-3
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let primeVerticalRadius = semiMajorAxis
            / sqrt(1 - eccentricitySquared * pow(sin(latitude), 2))

        return SpatialVector(
            x: (primeVerticalRadius + altitudeMeters) * cos(latitude) * cos(longitude),
            y: (primeVerticalRadius + altitudeMeters) * cos(latitude) * sin(longitude),
            z: (
                primeVerticalRadius * (1 - eccentricitySquared) + altitudeMeters
            ) * sin(latitude)
        )
    }

    private func observationQualityScore(
        location: LocationObservation,
        camera: CameraPoseObservation,
        locationAge: TimeInterval,
        poseAge: TimeInterval
    ) -> Double {
        let horizontal = decreasingQuality(
            value: location.horizontalAccuracyMeters,
            goodMaximum: tuning.goodHorizontalAccuracyMeters,
            usableMaximum: tuning.maximumHorizontalAccuracyMeters,
            usableMinimumScore: tuning.reducedQualityMinimumScore
        )
        let heading = decreasingQuality(
            value: camera.headingAccuracyDegrees,
            goodMaximum: tuning.goodHeadingAccuracyDegrees,
            usableMaximum: tuning.maximumHeadingAccuracyDegrees,
            usableMinimumScore: tuning.reducedQualityMinimumScore
        )
        let vertical = verticalQuality(location.verticalAccuracyMeters)
        let locationFreshness = decreasingQuality(
            value: locationAge,
            goodMaximum: tuning.freshLocationAgeSeconds,
            usableMaximum: tuning.maximumLocationAgeSeconds,
            usableMinimumScore: tuning.reducedQualityMinimumScore
        )
        let poseFreshness = decreasingQuality(
            value: poseAge,
            goodMaximum: tuning.freshPoseAgeSeconds,
            usableMaximum: tuning.maximumPoseAgeSeconds,
            usableMinimumScore: tuning.reducedQualityMinimumScore
        )
        let tracking = camera.trackingQuality == .normal
            ? 1.0
            : tuning.reducedQualityMinimumScore
        let score = [horizontal, heading, vertical, locationFreshness, poseFreshness, tracking]
            .min() ?? 0
        return usableAltitude(from: location) == nil
            ? min(score, tuning.altitudeUnavailableQualityScore)
            : score
    }

    private func verticalQuality(_ accuracyMeters: Double?) -> Double {
        guard let accuracyMeters, accuracyMeters.isFinite, accuracyMeters >= 0 else {
            return tuning.altitudeUnavailableQualityScore
        }
        if accuracyMeters <= tuning.goodVerticalAccuracyMeters { return 1 }
        if accuracyMeters > tuning.maximumVerticalAccuracyMeters {
            return tuning.altitudeUnavailableQualityScore
        }
        let range = tuning.maximumVerticalAccuracyMeters - tuning.goodVerticalAccuracyMeters
        let progress = (accuracyMeters - tuning.goodVerticalAccuracyMeters) / range
        return 1 - progress * (1 - tuning.altitudeUnavailableQualityScore)
    }

    private func decreasingQuality(
        value: Double,
        goodMaximum: Double,
        usableMaximum: Double,
        usableMinimumScore: Double
    ) -> Double {
        guard value.isFinite, value >= 0, value <= usableMaximum else { return 0 }
        if value <= goodMaximum { return 1 }
        let progress = (value - goodMaximum) / (usableMaximum - goodMaximum)
        return 1 - progress * (1 - usableMinimumScore)
    }

    private func centeredScore(
        coordinate: Double,
        length: Double,
        fieldOfViewDegrees: Double
    ) -> Double {
        guard coordinate.isFinite, length > 0, fieldOfViewDegrees > 0 else { return 0 }
        let halfLength = length / 2
        let margin = halfLength * tuning.fieldOfViewMarginDegrees / (fieldOfViewDegrees / 2)
        return clamp(1 - abs(coordinate - halfLength) / (halfLength + margin))
    }

    private func isInsideViewport(
        _ point: ViewportPoint,
        geometry: CameraProjectionGeometry
    ) -> Bool {
        point.x >= 0
            && point.x <= geometry.viewportSizePoints.width
            && point.y >= 0
            && point.y <= geometry.viewportSizePoints.height
    }

    private func isInsideExtendedViewport(
        _ point: ViewportPoint,
        geometry: CameraProjectionGeometry
    ) -> Bool {
        let horizontalMargin = geometry.viewportSizePoints.width
            * tuning.fieldOfViewMarginDegrees / geometry.horizontalFieldOfViewDegrees
        let verticalMargin = geometry.viewportSizePoints.height
            * tuning.fieldOfViewMarginDegrees / geometry.verticalFieldOfViewDegrees
        return point.x >= -horizontalMargin
            && point.x <= geometry.viewportSizePoints.width + horizontalMargin
            && point.y >= -verticalMargin
            && point.y <= geometry.viewportSizePoints.height + verticalMargin
    }

    private func candidatePrecedes(
        _ lhs: CameraMountainCandidate,
        _ rhs: CameraMountainCandidate
    ) -> Bool {
        if lhs.score == rhs.score {
            if lhs.proximity.distance == rhs.proximity.distance {
                return lhs.mountain.id < rhs.mountain.id
            }
            return lhs.proximity.distance < rhs.proximity.distance
        }
        return lhs.score > rhs.score
    }

    private func isUsable(age: TimeInterval, maximum: TimeInterval) -> Bool {
        age.isFinite && age >= -1 && age <= maximum
    }

    private func isUsableHeading(_ accuracyDegrees: Double) -> Bool {
        accuracyDegrees.isFinite
            && accuracyDegrees >= 0
            && accuracyDegrees <= tuning.maximumHeadingAccuracyDegrees
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
