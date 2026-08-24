import Foundation

nonisolated enum ExternalMapURLBuilder {
    static func appleMapsURL(for search: ExternalMapSearch) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "q", value: search.query)]
        if let center = search.center {
            components.queryItems?.append(
                URLQueryItem(name: "sll", value: center.mapQueryValue)
            )
            components.queryItems?.append(
                URLQueryItem(name: "sspn", value: "0.015,0.015")
            )
        }
        return components.url
    }

    static func googleMapsURL(for search: ExternalMapSearch) -> URL? {
        guard var components = URLComponents(string: "comgooglemaps://") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "q", value: search.query)]
        if let center = search.center {
            components.queryItems?.append(
                URLQueryItem(name: "center", value: center.mapQueryValue)
            )
            components.queryItems?.append(URLQueryItem(name: "zoom", value: "15"))
        }
        return components.url
    }

    static func appleMapsURL(for route: ExternalMapRoute) -> URL? {
        guard let destination = route.destination.mapValue else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "q", value: route.destination.name),
            URLQueryItem(name: "dirflg", value: route.travelMode.appleMapsValue),
        ]
        if case .savedStation(let station) = route.origin,
           let origin = station.mapValue {
            components.queryItems?.append(URLQueryItem(name: "saddr", value: origin))
        }
        return components.url
    }

    static func googleMapsURL(for route: ExternalMapRoute) -> URL? {
        guard
            let destination = route.destination.mapValue,
            var components = URLComponents(string: "comgooglemaps://")
        else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "daddr", value: destination),
            URLQueryItem(name: "directionsmode", value: route.travelMode.googleMapsValue),
        ]
        if case .savedStation(let station) = route.origin,
           let origin = station.mapValue {
            components.queryItems?.append(URLQueryItem(name: "saddr", value: origin))
        }
        return components.url
    }
}

nonisolated struct ExternalMapSearch: Equatable, Sendable {
    let query: String
    let center: GeoCoordinate?
}

nonisolated struct ExternalMapPlace: Equatable, Sendable {
    let name: String
    let coordinate: GeoCoordinate?

    fileprivate var mapValue: String? {
        if let coordinate {
            return coordinate.mapQueryValue
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}

nonisolated enum ExternalMapRouteOrigin: Equatable, Sendable {
    case currentLocation
    case savedStation(ExternalMapPlace)
}

nonisolated enum ExternalMapTravelMode: Hashable, Sendable {
    case driving
    case walking
    case publicTransport

    fileprivate var appleMapsValue: String {
        switch self {
        case .driving: "d"
        case .walking: "w"
        case .publicTransport: "r"
        }
    }

    fileprivate var googleMapsValue: String {
        switch self {
        case .driving: "driving"
        case .walking: "walking"
        case .publicTransport: "transit"
        }
    }
}

nonisolated struct ExternalMapRoute: Equatable, Sendable {
    let origin: ExternalMapRouteOrigin
    let destination: ExternalMapPlace
    let travelMode: ExternalMapTravelMode
}

private nonisolated extension GeoCoordinate {
    var mapQueryValue: String {
        "\(latitude),\(longitude)"
    }
}
