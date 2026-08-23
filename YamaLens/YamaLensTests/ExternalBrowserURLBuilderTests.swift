import Foundation
import Testing
@testable import YamaLens

struct ExternalBrowserURLBuilderTests {
    @Test("Chrome用URLは公式HTTPS URLのパスとクエリを維持する")
    func buildsChromeURL() throws {
        let officialURL = try #require(URL(string: "https://example.com/facility?source=yamalens"))

        let url = try #require(ExternalBrowserURLBuilder.chromeURL(for: officialURL))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "googlechromes")
        #expect(components.host == "example.com")
        #expect(components.path == "/facility")
        #expect(components.queryItems?.first(where: { $0.name == "source" })?.value == "yamalens")
    }

    @Test("HTTPS以外のURLはChrome用に変換しない")
    func rejectsNonHTTPSURL() throws {
        let url = try #require(URL(string: "http://example.com/facility"))

        #expect(ExternalBrowserURLBuilder.chromeURL(for: url) == nil)
    }
}
