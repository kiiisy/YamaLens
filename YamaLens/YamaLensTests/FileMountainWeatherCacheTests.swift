import Foundation
import Testing
@testable import YamaLens

struct FileMountainWeatherCacheTests {
    @Test("天気キャッシュを読み書きしバックアップ対象外にする")
    func roundTripsForecastWithProtection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "weather-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FileMountainWeatherCache(directoryURL: root)
        let forecast = makeForecast()

        try await cache.save(forecast)
        let restored = try await cache.forecast(for: forecast.mountainID)
        #expect(restored == forecast)

        let fileURL = root.appending(path: "forecast-tonodake.json")
        let values = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
#if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(
            attributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication
        )
#endif
    }

    @Test("壊れたキャッシュを未取得として握りつぶさない")
    func rejectsCorruptCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "weather-corrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: root.appending(path: "forecast-tonodake.json"))
        let cache = FileMountainWeatherCache(directoryURL: root)

        await #expect(throws: MountainWeatherRepositoryError.invalidData) {
            try await cache.forecast(for: "tonodake")
        }
    }

    private func makeForecast() -> MountainWeatherForecast {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return MountainWeatherForecast(
            mountainID: "tonodake",
            current: MountainCurrentWeather(
                observedAt: now,
                conditionCode: "clear",
                symbolName: "sun.max.fill",
                temperatureCelsius: 8,
                apparentTemperatureCelsius: 7,
                windSpeedMetersPerSecond: 2,
                windDirectionCode: "north"
            ),
            hourly: [],
            alerts: [],
            retrievedAt: now,
            sourceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
    }
}
