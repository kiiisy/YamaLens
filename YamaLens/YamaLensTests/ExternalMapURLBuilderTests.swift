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
}
