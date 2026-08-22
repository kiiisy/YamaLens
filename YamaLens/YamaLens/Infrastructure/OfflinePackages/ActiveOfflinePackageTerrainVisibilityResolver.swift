import Foundation

actor ActiveOfflinePackageTerrainVisibilityResolver: TerrainVisibilityResolving {
    private let store: OfflinePackageStore
    private let packageID: String
    private var packageDirectoryURL: URL?
    private var resolver: TerrainVisibilityResolver?

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
        let activeResolver: TerrainVisibilityResolver
        if packageDirectoryURL == activeURL, let resolver {
            activeResolver = resolver
        } else {
            let repository = try SQLiteTerrainElevationRepository(
                packageDirectoryURL: activeURL
            )
            let newResolver = TerrainVisibilityResolver(
                elevationRepository: repository
            )
            packageDirectoryURL = activeURL
            resolver = newResolver
            activeResolver = newResolver
        }
        return try await activeResolver.resolveVisibility(
            from: location,
            to: mountains
        )
    }

    private func unavailableResults(for mountains: [Mountain]) -> [String: TerrainVisibility] {
        Dictionary(uniqueKeysWithValues: mountains.map { ($0.id, .unavailable) })
    }
}
