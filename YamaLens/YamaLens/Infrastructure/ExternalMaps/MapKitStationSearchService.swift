import MapKit

nonisolated struct MapKitStationSearchService: StationSearching {
    func searchStations(query: String) async throws -> [StationSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw StationSearchError.emptyQuery
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery.hasSuffix("駅")
            ? trimmedQuery
            : "\(trimmedQuery) 駅"
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty, name.contains("駅") else { return nil }
                let coordinate = item.location.coordinate
                guard
                    coordinate.latitude.isFinite,
                    coordinate.longitude.isFinite,
                    (-90...90).contains(coordinate.latitude),
                    (-180...180).contains(coordinate.longitude)
                else {
                    return nil
                }
                return StationSearchResult(
                    name: name,
                    locality: item.address?.shortAddress,
                    coordinate: GeoCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StationSearchError.temporarilyUnavailable
        }
    }
}
