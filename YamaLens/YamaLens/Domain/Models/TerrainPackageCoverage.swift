nonisolated struct TerrainPackageCoverage: Equatable, Sendable {
    let packageID: String
    let displayName: String
    let north: Double
    let south: Double
    let east: Double
    let west: Double

    var center: GeoCoordinate {
        GeoCoordinate(
            latitude: (north + south) / 2,
            longitude: (east + west) / 2
        )
    }

    func contains(_ coordinate: GeoCoordinate) -> Bool {
        guard isValid, coordinate.isValid else { return false }
        return (south...north).contains(coordinate.latitude)
            && (west...east).contains(coordinate.longitude)
    }

    private var isValid: Bool {
        !packageID.isEmpty
            && !displayName.isEmpty
            && north.isFinite
            && south.isFinite
            && east.isFinite
            && west.isFinite
            && (-90...90).contains(north)
            && (-90...90).contains(south)
            && (-180...180).contains(east)
            && (-180...180).contains(west)
            && north > south
            && east > west
    }
}

nonisolated struct TerrainPackageCoverageSelector: Sendable {
    private let proximityCalculator: MountainProximityCalculator

    init(
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator()
    ) {
        self.proximityCalculator = proximityCalculator
    }

    func select(
        for coordinate: GeoCoordinate,
        from coverages: [TerrainPackageCoverage]
    ) -> TerrainPackageCoverage? {
        coverages
            .filter { $0.contains(coordinate) }
            .compactMap { coverage -> SelectionCandidate? in
                guard let proximity = proximityCalculator.proximity(
                    from: coordinate,
                    to: coverage.center
                ) else {
                    return nil
                }
                return SelectionCandidate(
                    coverage: coverage,
                    distance: proximity.distance
                )
            }
            .min { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.coverage.packageID < rhs.coverage.packageID
                }
                return lhs.distance < rhs.distance
            }?
            .coverage
    }
}

private nonisolated struct SelectionCandidate: Sendable {
    let coverage: TerrainPackageCoverage
    let distance: MountainDistance
}

private extension GeoCoordinate {
    nonisolated var isValid: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}
