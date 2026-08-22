import Foundation

nonisolated struct CandidateTuning: Equatable, Sendable {
    let maximumSearchDistanceMeters: Double
    let goodHorizontalAccuracyMeters: Double
    let maximumHorizontalAccuracyMeters: Double
    let goodVerticalAccuracyMeters: Double
    let maximumVerticalAccuracyMeters: Double
    let goodHeadingAccuracyDegrees: Double
    let maximumHeadingAccuracyDegrees: Double
    let freshLocationAgeSeconds: TimeInterval
    let maximumLocationAgeSeconds: TimeInterval
    let freshPoseAgeSeconds: TimeInterval
    let maximumPoseAgeSeconds: TimeInterval
    let maximumSheetCandidateCount: Int
    let maximumCameraLabelCount: Int
    let manualHeadingCorrectionStepDegrees: Double
    let maximumManualHeadingCorrectionDegrees: Double
    let fieldOfViewMarginDegrees: Double
    let strongCandidateScore: Double
    let cameraCandidateScore: Double
    let sheetCandidateScore: Double
    let bearingScoreWeight: Double
    let elevationScoreWeight: Double
    let observationQualityScoreWeight: Double
    let distanceScoreWeight: Double
    let reducedQualityMinimumScore: Double
    let altitudeUnavailableQualityScore: Double
    let terrainOcclusionClearanceMeters: Double
    let terrainOcclusionScoreMultiplier: Double
    let preferredTerrainProfileSpacingMeters: Double
    let maximumTerrainProfileSampleCount: Int

    static let `default` = CandidateTuning(
        maximumSearchDistanceMeters: 150_000,
        goodHorizontalAccuracyMeters: 25,
        maximumHorizontalAccuracyMeters: 100,
        goodVerticalAccuracyMeters: 30,
        maximumVerticalAccuracyMeters: 75,
        goodHeadingAccuracyDegrees: 10,
        maximumHeadingAccuracyDegrees: 25,
        freshLocationAgeSeconds: 15,
        maximumLocationAgeSeconds: 60,
        freshPoseAgeSeconds: 1,
        maximumPoseAgeSeconds: 3,
        maximumSheetCandidateCount: 10,
        maximumCameraLabelCount: 5,
        manualHeadingCorrectionStepDegrees: 1,
        maximumManualHeadingCorrectionDegrees: 30,
        fieldOfViewMarginDegrees: 3,
        strongCandidateScore: 0.75,
        cameraCandidateScore: 0.50,
        sheetCandidateScore: 0.35,
        bearingScoreWeight: 0.45,
        elevationScoreWeight: 0.30,
        observationQualityScoreWeight: 0.15,
        distanceScoreWeight: 0.10,
        reducedQualityMinimumScore: 0.4,
        altitudeUnavailableQualityScore: 0.6,
        terrainOcclusionClearanceMeters: 30,
        terrainOcclusionScoreMultiplier: 0.75,
        preferredTerrainProfileSpacingMeters: 50,
        maximumTerrainProfileSampleCount: 512
    )
}

nonisolated struct MountainDistance: Equatable, Comparable, Sendable {
    let meters: Double

    static func < (lhs: MountainDistance, rhs: MountainDistance) -> Bool {
        lhs.meters < rhs.meters
    }
}

nonisolated struct TrueBearing: Equatable, Sendable {
    let degrees: Double
}

nonisolated enum CompassDirection: Equatable, Sendable {
    case north
    case northeast
    case east
    case southeast
    case south
    case southwest
    case west
    case northwest
}

nonisolated struct MountainProximity: Equatable, Sendable {
    let distance: MountainDistance
    let bearing: TrueBearing?
    let direction: CompassDirection?
}

nonisolated struct NearbyMountain: Equatable, Sendable {
    let mountain: Mountain
    let proximity: MountainProximity
}

nonisolated struct MountainProximityCalculator: Sendable {
    private let tuning: CandidateTuning
    private let earthRadiusMeters = 6_371_008.8

    init(tuning: CandidateTuning = .default) {
        self.tuning = tuning
    }

    func locationQuality(horizontalAccuracyMeters: Double) -> LocationObservationQuality? {
        guard horizontalAccuracyMeters.isFinite, horizontalAccuracyMeters >= 0 else {
            return nil
        }
        guard horizontalAccuracyMeters <= tuning.maximumHorizontalAccuracyMeters else {
            return nil
        }
        return horizontalAccuracyMeters <= tuning.goodHorizontalAccuracyMeters ? .good : .reduced
    }

    func proximity(
        from origin: GeoCoordinate,
        to destination: GeoCoordinate
    ) -> MountainProximity? {
        guard origin.isValid, destination.isValid else { return nil }

        let originLatitude = origin.latitude.degreesToRadians
        let destinationLatitude = destination.latitude.degreesToRadians
        let latitudeDelta = (destination.latitude - origin.latitude).degreesToRadians
        let longitudeDelta = (destination.longitude - origin.longitude).degreesToRadians

        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(originLatitude) * cos(destinationLatitude) * pow(sin(longitudeDelta / 2), 2)
        let clampedHaversine = min(max(haversine, 0), 1)
        let distanceMeters = earthRadiusMeters * 2 * asin(sqrt(clampedHaversine))
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return nil }

        let distance = MountainDistance(meters: distanceMeters)
        guard distanceMeters > 0.01 else {
            return MountainProximity(distance: distance, bearing: nil, direction: nil)
        }

        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude)
            - sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        let rawDegrees = atan2(y, x).radiansToDegrees
        let normalizedDegrees = normalizeBearing(rawDegrees)
        let bearing = TrueBearing(degrees: normalizedDegrees)

        return MountainProximity(
            distance: distance,
            bearing: bearing,
            direction: compassDirection(for: bearing)
        )
    }

    func nearbyMountains(
        from origin: GeoCoordinate,
        mountains: [Mountain]
    ) -> [NearbyMountain] {
        mountains
            .compactMap { mountain -> NearbyMountain? in
                guard let proximity = proximity(from: origin, to: mountain.coordinate) else {
                    return nil
                }
                guard proximity.distance.meters <= tuning.maximumSearchDistanceMeters else {
                    return nil
                }
                return NearbyMountain(mountain: mountain, proximity: proximity)
            }
            .sorted { lhs, rhs in
                if lhs.proximity.distance == rhs.proximity.distance {
                    return lhs.mountain.id < rhs.mountain.id
                }
                return lhs.proximity.distance < rhs.proximity.distance
            }
    }

    private func normalizeBearing(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func compassDirection(for bearing: TrueBearing) -> CompassDirection {
        let index = Int(((bearing.degrees + 22.5) / 45).rounded(.down)) % 8
        return [
            .north,
            .northeast,
            .east,
            .southeast,
            .south,
            .southwest,
            .west,
            .northwest,
        ][index]
    }
}

private extension GeoCoordinate {
    nonisolated var isValid: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

private extension Double {
    nonisolated var degreesToRadians: Double { self * .pi / 180 }
    nonisolated var radiansToDegrees: Double { self * 180 / .pi }
}
