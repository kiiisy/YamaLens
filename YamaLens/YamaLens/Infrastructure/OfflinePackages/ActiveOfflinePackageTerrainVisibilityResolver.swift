import Foundation

actor ActiveOfflinePackageTerrainVisibilityResolver: TerrainVisibilityResolving,
    TerrainHorizonResolving {
    private let store: OfflinePackageStore
    private let packageID: String
    private var packageDirectoryURL: URL?
    private var resolver: TerrainVisibilityResolver?
    private var horizonResolver: TerrainHorizonResolver?

    init(
        store: OfflinePackageStore,
        packageID: String = "jp.kanagawa.tanzawa"
    ) {
        self.store = store
        self.packageID = packageID
    }

    func resolveVisibility(
        from location: LocationObservation,
        to mountains: [Mountain]
    ) async throws -> [String: TerrainVisibility] {
        guard let activeURL = try await store.activePackageURL(packageID: packageID) else {
            return unavailableResults(for: mountains)
        }
        let activeResolver = try resolvers(for: activeURL).visibility
        return try await activeResolver.resolveVisibility(
            from: location,
            to: mountains
        )
    }

    func resolveHorizon(
        from location: LocationObservation,
        centerBearingDegrees: Double,
        horizontalFieldOfViewDegrees: Double
    ) async throws -> [TerrainHorizonSample] {
        guard let activeURL = try await store.activePackageURL(packageID: packageID) else {
            return []
        }
        let activeResolver = try resolvers(for: activeURL).horizon
        return try await activeResolver.resolveHorizon(
            from: location,
            centerBearingDegrees: centerBearingDegrees,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees
        )
    }

    private func resolvers(
        for activeURL: URL
    ) throws -> (visibility: TerrainVisibilityResolver, horizon: TerrainHorizonResolver) {
        if packageDirectoryURL == activeURL, let resolver, let horizonResolver {
            return (resolver, horizonResolver)
        }
        let repository = try SQLiteTerrainElevationRepository(
            packageDirectoryURL: activeURL
        )
        let newVisibilityResolver = TerrainVisibilityResolver(
            elevationRepository: repository
        )
        let newHorizonResolver = TerrainHorizonResolver(
            elevationRepository: repository
        )
        packageDirectoryURL = activeURL
        resolver = newVisibilityResolver
        horizonResolver = newHorizonResolver
        return (newVisibilityResolver, newHorizonResolver)
    }

    private func unavailableResults(for mountains: [Mountain]) -> [String: TerrainVisibility] {
        Dictionary(uniqueKeysWithValues: mountains.map { ($0.id, .unavailable) })
    }
}
