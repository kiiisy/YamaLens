import MapKit

nonisolated protocol NearbySearchCenterResolving: Sendable {
    func resolveCenter(for areaName: String) async -> GeoCoordinate?
}

nonisolated struct MapKitNearbySearchCenterResolver: NearbySearchCenterResolving {
    func resolveCenter(for areaName: String) async -> GeoCoordinate? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = areaName
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), let item = response.mapItems.first else {
            return nil
        }
        let coordinate = item.location.coordinate
        guard (-90...90).contains(coordinate.latitude), (-180...180).contains(coordinate.longitude) else {
            return nil
        }
        return GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
