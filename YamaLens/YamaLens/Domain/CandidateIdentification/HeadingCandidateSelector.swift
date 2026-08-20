import Foundation

nonisolated struct HeadingCandidate: Equatable, Sendable {
    let mountain: Mountain
    let proximity: MountainProximity
    let angularDifferenceDegrees: Double
}

nonisolated struct HeadingCandidateSelector: Sendable {
    private let proximityCalculator: MountainProximityCalculator

    init(proximityCalculator: MountainProximityCalculator = MountainProximityCalculator()) {
        self.proximityCalculator = proximityCalculator
    }

    func candidates(
        from origin: GeoCoordinate,
        facing trueBearingDegrees: Double,
        mountains: [Mountain],
        maximumCount: Int = 10
    ) -> [HeadingCandidate] {
        guard trueBearingDegrees.isFinite, maximumCount > 0 else { return [] }

        return proximityCalculator.nearbyMountains(from: origin, mountains: mountains)
            .compactMap { nearby -> HeadingCandidate? in
                guard let bearing = nearby.proximity.bearing else { return nil }
                return HeadingCandidate(
                    mountain: nearby.mountain,
                    proximity: nearby.proximity,
                    angularDifferenceDegrees: angularDifference(
                        from: trueBearingDegrees,
                        to: bearing.degrees
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.angularDifferenceDegrees == rhs.angularDifferenceDegrees {
                    if lhs.proximity.distance == rhs.proximity.distance {
                        return lhs.mountain.id < rhs.mountain.id
                    }
                    return lhs.proximity.distance < rhs.proximity.distance
                }
                return lhs.angularDifferenceDegrees < rhs.angularDifferenceDegrees
            }
            .prefix(maximumCount)
            .map { $0 }
    }

    private func angularDifference(from start: Double, to end: Double) -> Double {
        abs((end - start + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
}
