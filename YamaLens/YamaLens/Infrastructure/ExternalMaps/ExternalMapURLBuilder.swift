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
}

nonisolated struct ExternalMapSearch: Equatable, Sendable {
    let query: String
    let center: GeoCoordinate?
}

private nonisolated extension GeoCoordinate {
    var mapQueryValue: String {
        "\(latitude),\(longitude)"
    }
}
