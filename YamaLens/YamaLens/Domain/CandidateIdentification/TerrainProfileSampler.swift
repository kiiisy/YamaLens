import Foundation

nonisolated struct TerrainProfileSampler: Sendable {
    private let preferredSpacingMeters: Double
    private let maximumSampleCount: Int

    init(tuning: CandidateTuning = .default) {
        preferredSpacingMeters = tuning.preferredTerrainProfileSpacingMeters
        maximumSampleCount = tuning.maximumTerrainProfileSampleCount
    }

    func points(
        from origin: GeoCoordinate,
        to destination: GeoCoordinate,
        summitDistance: MountainDistance
    ) -> [TerrainProfilePoint]? {
        guard
            origin.isValidTerrainCoordinate,
            destination.isValidTerrainCoordinate,
            summitDistance.meters.isFinite,
            summitDistance.meters > 0,
            preferredSpacingMeters.isFinite,
            preferredSpacingMeters > 0,
            maximumSampleCount > 0
        else {
            return nil
        }

        let preferredSegmentCount = max(
            2,
            Int(ceil(summitDistance.meters / preferredSpacingMeters))
        )
        let segmentCount = min(preferredSegmentCount, maximumSampleCount + 1)
        guard segmentCount >= 2 else { return nil }

        let originVector = unitVector(for: origin)
        let destinationVector = unitVector(for: destination)
        let dotProduct = clamp(
            originVector.x * destinationVector.x
                + originVector.y * destinationVector.y
                + originVector.z * destinationVector.z,
            minimum: -1,
            maximum: 1
        )
        let angularDistance = acos(dotProduct)
        guard angularDistance.isFinite, angularDistance > 0 else { return nil }

        return (1..<segmentCount).compactMap { index in
            let fraction = Double(index) / Double(segmentCount)
            guard let coordinate = interpolatedCoordinate(
                origin: originVector,
                destination: destinationVector,
                angularDistance: angularDistance,
                fraction: fraction
            ) else {
                return nil
            }
            return TerrainProfilePoint(
                coordinate: coordinate,
                distance: MountainDistance(meters: summitDistance.meters * fraction)
            )
        }
    }

    private func unitVector(for coordinate: GeoCoordinate) -> TerrainVector {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        return TerrainVector(
            x: cos(latitude) * cos(longitude),
            y: cos(latitude) * sin(longitude),
            z: sin(latitude)
        )
    }

    private func interpolatedCoordinate(
        origin: TerrainVector,
        destination: TerrainVector,
        angularDistance: Double,
        fraction: Double
    ) -> GeoCoordinate? {
        let sine = sin(angularDistance)
        guard sine.isFinite, abs(sine) > .ulpOfOne else { return nil }
        let originWeight = sin((1 - fraction) * angularDistance) / sine
        let destinationWeight = sin(fraction * angularDistance) / sine
        let vector = TerrainVector(
            x: originWeight * origin.x + destinationWeight * destination.x,
            y: originWeight * origin.y + destinationWeight * destination.y,
            z: originWeight * origin.z + destinationWeight * destination.z
        )
        let horizontalLength = hypot(vector.x, vector.y)
        let latitude = atan2(vector.z, horizontalLength) * 180 / .pi
        let longitude = atan2(vector.y, vector.x) * 180 / .pi
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValidTerrainCoordinate ? coordinate : nil
    }

    private func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

private nonisolated struct TerrainVector: Sendable {
    let x: Double
    let y: Double
    let z: Double
}

private extension GeoCoordinate {
    nonisolated var isValidTerrainCoordinate: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}
