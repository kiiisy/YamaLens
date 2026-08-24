import Foundation
import Testing
@testable import YamaLens

struct ExternalMapURLBuilderTests {
    @Test("Google Maps検索URLは検索語と周辺中心を渡す")
    func buildsGoogleMapsSearchURL() throws {
        let search = ExternalMapSearch(
            query: "コンビニ",
            center: GeoCoordinate(latitude: 35.411, longitude: 139.276)
        )

        let url = try #require(ExternalMapURLBuilder.googleMapsURL(for: search))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.absoluteString.hasPrefix("comgooglemaps://?"))
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "コンビニ")
        #expect(components.queryItems?.first(where: { $0.name == "center" })?.value == "35.411,139.276")
        #expect(components.queryItems?.first(where: { $0.name == "zoom" })?.value == "15")
    }

    @Test("Appleマップ検索URLは検索語と周辺中心を渡す")
    func buildsAppleMapsSearchURL() throws {
        let search = ExternalMapSearch(
            query: "温泉",
            center: GeoCoordinate(latitude: 35.411, longitude: 139.276)
        )

        let url = try #require(ExternalMapURLBuilder.appleMapsURL(for: search))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "maps.apple.com")
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "温泉")
        #expect(components.queryItems?.first(where: { $0.name == "sll" })?.value == "35.411,139.276")
    }

    @Test("現在地から公共交通で向かうAppleマップ経路は出発地を省略する")
    func buildsAppleMapsRouteFromCurrentLocation() throws {
        let route = ExternalMapRoute(
            origin: .currentLocation,
            destination: ExternalMapPlace(
                name: "大倉バス停",
                coordinate: GeoCoordinate(latitude: 35.403, longitude: 139.205)
            ),
            travelMode: .publicTransport
        )

        let url = try #require(ExternalMapURLBuilder.appleMapsURL(for: route))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.first(where: { $0.name == "daddr" })?.value == "35.403,139.205")
        #expect(components.queryItems?.first(where: { $0.name == "saddr" }) == nil)
        #expect(components.queryItems?.first(where: { $0.name == "dirflg" })?.value == "r")
    }

    @Test("登録駅から車で向かうGoogle Maps経路は出発地と目的地を渡す")
    func buildsGoogleMapsRouteFromSavedStation() throws {
        let route = ExternalMapRoute(
            origin: .savedStation(
                ExternalMapPlace(
                    name: "横浜駅",
                    coordinate: GeoCoordinate(latitude: 35.466, longitude: 139.622)
                )
            ),
            destination: ExternalMapPlace(
                name: "大倉駐車場",
                coordinate: GeoCoordinate(latitude: 35.404, longitude: 139.206)
            ),
            travelMode: .driving
        )

        let url = try #require(ExternalMapURLBuilder.googleMapsURL(for: route))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.first(where: { $0.name == "saddr" })?.value == "35.466,139.622")
        #expect(components.queryItems?.first(where: { $0.name == "daddr" })?.value == "35.404,139.206")
        #expect(components.queryItems?.first(where: { $0.name == "directionsmode" })?.value == "driving")
    }

    @Test("座標がない目的地は確認済み名称で経路を生成する")
    func buildsRouteUsingDestinationNameFallback() throws {
        let route = ExternalMapRoute(
            origin: .currentLocation,
            destination: ExternalMapPlace(name: "確認済み登山口", coordinate: nil),
            travelMode: .walking
        )

        let url = try #require(ExternalMapURLBuilder.googleMapsURL(for: route))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems?.first(where: { $0.name == "daddr" })?.value == "確認済み登山口")
        #expect(components.queryItems?.first(where: { $0.name == "directionsmode" })?.value == "walking")
    }
}
