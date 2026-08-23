import Foundation

actor AutomaticOfflinePackageTerrainResolver: TerrainVisibilityResolving,
    TerrainHorizonResolving {
    private let selector: TerrainPackageCoverageSelector
    private let coverages: [TerrainPackageCoverage]
    private let resolversByPackageID: [String: ActiveOfflinePackageTerrainVisibilityResolver]

    init(
        store: OfflinePackageStore,
        coverages: [TerrainPackageCoverage],
        selector: TerrainPackageCoverageSelector = TerrainPackageCoverageSelector()
    ) {
        self.selector = selector
        self.coverages = coverages
        self.resolversByPackageID = Dictionary(
            uniqueKeysWithValues: coverages.map { coverage in
                (
                    coverage.packageID,
                    ActiveOfflinePackageTerrainVisibilityResolver(
                        store: store,
                        packageID: coverage.packageID
                    )
                )
            }
        )
    }

    func resolveVisibility(
        from location: LocationObservation,
        to mountains: [Mountain]
    ) async throws -> [String: TerrainVisibility] {
        guard let resolver = selectedResolver(for: location.coordinate) else {
            return unavailableResults(for: mountains)
        }
        return try await resolver.resolveVisibility(from: location, to: mountains)
    }

    func resolveHorizon(
        from location: LocationObservation,
        centerBearingDegrees: Double,
        horizontalFieldOfViewDegrees: Double
    ) async throws -> [TerrainHorizonSample] {
        guard let resolver = selectedResolver(for: location.coordinate) else {
            return []
        }
        return try await resolver.resolveHorizon(
            from: location,
            centerBearingDegrees: centerBearingDegrees,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees
        )
    }

    private func selectedResolver(
        for coordinate: GeoCoordinate
    ) -> ActiveOfflinePackageTerrainVisibilityResolver? {
        guard let coverage = selector.select(for: coordinate, from: coverages) else {
            return nil
        }
        return resolversByPackageID[coverage.packageID]
    }

    private func unavailableResults(for mountains: [Mountain]) -> [String: TerrainVisibility] {
        Dictionary(uniqueKeysWithValues: mountains.map { ($0.id, .unavailable) })
    }
}
