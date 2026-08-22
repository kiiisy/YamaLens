import Foundation

nonisolated struct TerrainHorizonSample: Equatable, Sendable {
    let bearingDegrees: Double
    let elevationAngleDegrees: Double?
}

nonisolated protocol TerrainHorizonResolving: Sendable {
    func resolveHorizon(
        from location: LocationObservation,
        centerBearingDegrees: Double,
        horizontalFieldOfViewDegrees: Double
    ) async throws -> [TerrainHorizonSample]
}

nonisolated struct TerrainHorizonResolver: TerrainHorizonResolving, Sendable {
    private let elevationRepository: any TerrainElevationRepository
    private let tuning: CandidateTuning
    private let earthRadiusMeters = 6_371_008.8

    init(
        elevationRepository: any TerrainElevationRepository,
        tuning: CandidateTuning = .default
    ) {
        self.elevationRepository = elevationRepository
        self.tuning = tuning
    }

    func resolveHorizon(
        from location: LocationObservation,
        centerBearingDegrees: Double,
        horizontalFieldOfViewDegrees: Double
    ) async throws -> [TerrainHorizonSample] {
        guard
            let observerElevationMeters = usableObserverElevation(from: location),
            centerBearingDegrees.isFinite,
            horizontalFieldOfViewDegrees.isFinite,
            horizontalFieldOfViewDegrees > 0,
            tuning.terrainHorizonMaximumDistanceMeters > 0,
            tuning.preferredTerrainHorizonSpacingMeters > 0,
            tuning.maximumTerrainHorizonSampleCountPerBearing > 0,
            tuning.terrainHorizonBearingStepDegrees > 0
        else {
            return []
        }

        let bearings = sampledBearings(
            centerBearingDegrees: centerBearingDegrees,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees
        )
        let distances = sampledDistances()
        guard !bearings.isEmpty, !distances.isEmpty else { return [] }

        var coordinates: [GeoCoordinate] = []
        coordinates.reserveCapacity(bearings.count * distances.count)
        for bearing in bearings {
            try Task.checkCancellation()
            coordinates.append(contentsOf: distances.compactMap { distance in
                destinationCoordinate(
                    from: location.coordinate,
                    bearingDegrees: bearing,
                    distanceMeters: distance
                )
            })
        }
        guard coordinates.count == bearings.count * distances.count else { return [] }

        let elevations = try await elevationRepository.elevations(at: coordinates)
        guard elevations.count == coordinates.count else { return [] }

        var samples: [TerrainHorizonSample] = []
        samples.reserveCapacity(bearings.count)
        for (bearingIndex, bearing) in bearings.enumerated() {
            try Task.checkCancellation()
            let offset = bearingIndex * distances.count
            var maximumElevationAngleDegrees: Double?
            for distanceIndex in distances.indices {
                guard let elevation = elevations[offset + distanceIndex] else { continue }
                let angle = elevationAngleDegrees(
                    observerCoordinate: location.coordinate,
                    observerElevationMeters: observerElevationMeters,
                    targetCoordinate: coordinates[offset + distanceIndex],
                    targetElevationMeters: elevation.meters
                )
                guard let angle else { continue }
                maximumElevationAngleDegrees = max(maximumElevationAngleDegrees ?? angle, angle)
            }
            samples.append(
                TerrainHorizonSample(
                    bearingDegrees: bearing,
                    elevationAngleDegrees: maximumElevationAngleDegrees
                )
            )
        }
        return samples
    }

    private func usableObserverElevation(from location: LocationObservation) -> Double? {
        guard
            let altitudeMeters = location.altitudeMeters,
            altitudeMeters.isFinite,
            let verticalAccuracyMeters = location.verticalAccuracyMeters,
            verticalAccuracyMeters.isFinite,
            verticalAccuracyMeters >= 0,
            verticalAccuracyMeters <= tuning.maximumVerticalAccuracyMeters
        else {
            return nil
        }
        return altitudeMeters
    }

    private func sampledBearings(
        centerBearingDegrees: Double,
        horizontalFieldOfViewDegrees: Double
    ) -> [Double] {
        let halfSpan = min(
            horizontalFieldOfViewDegrees / 2
                + tuning.maximumManualHeadingCorrectionDegrees
                + tuning.fieldOfViewMarginDegrees,
            180
        )
        let segmentCount = max(
            1,
            Int(ceil(halfSpan * 2 / tuning.terrainHorizonBearingStepDegrees))
        )
        return (0...segmentCount).map { index in
            let fraction = Double(index) / Double(segmentCount)
            return normalizedBearing(centerBearingDegrees - halfSpan + halfSpan * 2 * fraction)
        }
    }

    private func sampledDistances() -> [Double] {
        let preferredCount = Int(
            ceil(
                tuning.terrainHorizonMaximumDistanceMeters
                    / tuning.preferredTerrainHorizonSpacingMeters
            )
        )
        let sampleCount = min(
            max(preferredCount, 1),
            tuning.maximumTerrainHorizonSampleCountPerBearing
        )
        return (1...sampleCount).map { index in
            tuning.terrainHorizonMaximumDistanceMeters
                * Double(index) / Double(sampleCount)
        }
    }

    private func destinationCoordinate(
        from origin: GeoCoordinate,
        bearingDegrees: Double,
        distanceMeters: Double
    ) -> GeoCoordinate? {
        guard
            origin.latitude.isFinite,
            origin.longitude.isFinite,
            (-90...90).contains(origin.latitude),
            (-180...180).contains(origin.longitude),
            bearingDegrees.isFinite,
            distanceMeters.isFinite,
            distanceMeters > 0
        else {
            return nil
        }
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let bearing = bearingDegrees * .pi / 180
        let angularDistance = distanceMeters / earthRadiusMeters
        let destinationLatitude = asin(
            sin(latitude) * cos(angularDistance)
                + cos(latitude) * sin(angularDistance) * cos(bearing)
        )
        let destinationLongitude = longitude + atan2(
            sin(bearing) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(destinationLatitude)
        )
        let coordinate = GeoCoordinate(
            latitude: destinationLatitude * 180 / .pi,
            longitude: normalizedLongitude(destinationLongitude * 180 / .pi)
        )
        return coordinate.latitude.isFinite && coordinate.longitude.isFinite
            ? coordinate
            : nil
    }

    private func elevationAngleDegrees(
        observerCoordinate: GeoCoordinate,
        observerElevationMeters: Double,
        targetCoordinate: GeoCoordinate,
        targetElevationMeters: Double
    ) -> Double? {
        guard
            let observer = ecef(
                coordinate: observerCoordinate,
                elevationMeters: observerElevationMeters
            ),
            let target = ecef(
                coordinate: targetCoordinate,
                elevationMeters: targetElevationMeters
            )
        else {
            return nil
        }
        let delta = SpatialVector(
            x: target.x - observer.x,
            y: target.y - observer.y,
            z: target.z - observer.z
        )
        let latitude = observerCoordinate.latitude * .pi / 180
        let longitude = observerCoordinate.longitude * .pi / 180
        let east = -sin(longitude) * delta.x + cos(longitude) * delta.y
        let north = -sin(latitude) * cos(longitude) * delta.x
            - sin(latitude) * sin(longitude) * delta.y
            + cos(latitude) * delta.z
        let up = cos(latitude) * cos(longitude) * delta.x
            + cos(latitude) * sin(longitude) * delta.y
            + sin(latitude) * delta.z
        let angle = atan2(up, hypot(east, north)) * 180 / .pi
        return angle.isFinite ? angle : nil
    }

    private func ecef(
        coordinate: GeoCoordinate,
        elevationMeters: Double
    ) -> SpatialVector? {
        guard elevationMeters.isFinite else { return nil }
        let semiMajorAxis = 6_378_137.0
        let eccentricitySquared = 6.694_379_990_14e-3
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let primeVerticalRadius = semiMajorAxis
            / sqrt(1 - eccentricitySquared * pow(sin(latitude), 2))
        return SpatialVector(
            x: (primeVerticalRadius + elevationMeters) * cos(latitude) * cos(longitude),
            y: (primeVerticalRadius + elevationMeters) * cos(latitude) * sin(longitude),
            z: (
                primeVerticalRadius * (1 - eccentricitySquared) + elevationMeters
            ) * sin(latitude)
        )
    }

    private func normalizedBearing(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func normalizedLongitude(_ degrees: Double) -> Double {
        let remainder = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (remainder >= 0 ? remainder : remainder + 360) - 180
    }
}
