import Foundation

nonisolated protocol TerrainVisibilityResolving: Sendable {
    func resolveVisibility(
        from location: LocationObservation,
        to mountains: [Mountain]
    ) async throws -> [String: TerrainVisibility]
}

nonisolated struct TerrainVisibilityResolver: TerrainVisibilityResolving, Sendable {
    private let elevationRepository: any TerrainElevationRepository
    private let proximityCalculator: MountainProximityCalculator
    private let profileSampler: TerrainProfileSampler
    private let lineOfSightEvaluator: TerrainLineOfSightEvaluator
    private let tuning: CandidateTuning

    init(
        elevationRepository: any TerrainElevationRepository,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator(),
        profileSampler: TerrainProfileSampler = TerrainProfileSampler(),
        lineOfSightEvaluator: TerrainLineOfSightEvaluator = TerrainLineOfSightEvaluator(),
        tuning: CandidateTuning = .default
    ) {
        self.elevationRepository = elevationRepository
        self.proximityCalculator = proximityCalculator
        self.profileSampler = profileSampler
        self.lineOfSightEvaluator = lineOfSightEvaluator
        self.tuning = tuning
    }

    func resolveVisibility(
        from location: LocationObservation,
        to mountains: [Mountain]
    ) async throws -> [String: TerrainVisibility] {
        guard let observerElevation = usableObserverElevation(from: location) else {
            return unavailableResults(for: mountains)
        }

        var profiles: [MountainProfile] = []
        var coordinates: [GeoCoordinate] = []
        for mountain in mountains {
            guard
                let proximity = proximityCalculator.proximity(
                    from: location.coordinate,
                    to: mountain.coordinate
                ),
                let points = profileSampler.points(
                    from: location.coordinate,
                    to: mountain.coordinate,
                    summitDistance: proximity.distance
                ),
                !points.isEmpty
            else {
                continue
            }
            profiles.append(
                MountainProfile(
                    mountain: mountain,
                    summitDistance: proximity.distance,
                    points: points,
                    elevationOffset: coordinates.count
                )
            )
            coordinates.append(contentsOf: points.map(\.coordinate))
        }

        guard !coordinates.isEmpty else {
            return unavailableResults(for: mountains)
        }
        let elevations = try await elevationRepository.elevations(at: coordinates)
        guard elevations.count == coordinates.count else {
            return unavailableResults(for: mountains)
        }

        var results = unavailableResults(for: mountains)
        for profile in profiles {
            guard let summitElevation = TerrainElevation(
                meters: Double(profile.mountain.elevationMeters)
            ) else {
                continue
            }
            let samples = profile.points.enumerated().map { index, point in
                TerrainProfileSample(
                    distance: point.distance,
                    elevation: elevations[profile.elevationOffset + index]
                )
            }
            results[profile.mountain.id] = lineOfSightEvaluator.evaluate(
                observerElevation: observerElevation,
                summitElevation: summitElevation,
                summitDistance: profile.summitDistance,
                samples: samples
            )
        }
        return results
    }

    private func usableObserverElevation(from location: LocationObservation) -> TerrainElevation? {
        guard
            let altitudeMeters = location.altitudeMeters,
            let verticalAccuracyMeters = location.verticalAccuracyMeters,
            verticalAccuracyMeters.isFinite,
            verticalAccuracyMeters >= 0,
            verticalAccuracyMeters <= tuning.maximumVerticalAccuracyMeters
        else {
            return nil
        }
        return TerrainElevation(meters: altitudeMeters)
    }

    private func unavailableResults(for mountains: [Mountain]) -> [String: TerrainVisibility] {
        Dictionary(uniqueKeysWithValues: mountains.map { ($0.id, .unavailable) })
    }
}

private nonisolated struct MountainProfile: Sendable {
    let mountain: Mountain
    let summitDistance: MountainDistance
    let points: [TerrainProfilePoint]
    let elevationOffset: Int
}
