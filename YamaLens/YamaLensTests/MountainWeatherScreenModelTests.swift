import Foundation
import Testing
@testable import YamaLens

@MainActor
struct MountainWeatherScreenModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("古い保存済み天気の更新失敗時も値と失敗理由を保持する")
    func keepsStaleForecastWhenRefreshFails() async throws {
        let forecast = makeForecast(retrievedAt: now.addingTimeInterval(-4 * 60 * 60))
        let previousDay = try #require(MountainWeatherCalendar.previousDayStart(now: now))
        let repository = FailingWeatherRepository(
            forecast: forecast,
            previousDay: makePreviousDay(targetDate: previousDay)
        )
        let fixedNow = now
        let model = MountainWeatherScreenModel(repository: repository, now: { fixedNow })

        await model.load(for: makeMountain())

        guard case .loaded(let content) = model.forecastState else {
            Issue.record("保存済み天気が表示されていません")
            return
        }
        #expect(content.forecast == forecast)
        #expect(content.freshness == .stale)
        #expect(content.updateFailure == .temporarilyUnavailable)
        #expect(content.isRefreshing == false)
    }

    @Test("対象日が一致する6時間以内の前日サマリーは再取得しない")
    func reusesRecentPreviousDaySummary() async throws {
        let previousDay = try #require(MountainWeatherCalendar.previousDayStart(now: now))
        let repository = FailingWeatherRepository(
            forecast: makeForecast(retrievedAt: now),
            previousDay: makePreviousDay(targetDate: previousDay)
        )
        let fixedNow = now
        let model = MountainWeatherScreenModel(repository: repository, now: { fixedNow })

        await model.load(for: makeMountain())

        #expect(await repository.previousDayRefreshCount == 0)
        guard case .loaded(let content) = model.previousDayState else {
            Issue.record("前日サマリーが表示されていません")
            return
        }
        #expect(content.summary.targetDate == previousDay)
        #expect(content.updateFailure == nil)
    }

    private func makeMountain() -> Mountain {
        Mountain(
            id: "tonodake",
            name: "塔ノ岳",
            aliases: [],
            regionName: "丹沢",
            prefectureName: "神奈川県",
            elevationMeters: 1_491,
            coordinate: GeoCoordinate(latitude: 35.4548, longitude: 139.1636)
        )
    }

    private func makeForecast(retrievedAt: Date) -> MountainWeatherForecast {
        MountainWeatherForecast(
            mountainID: "tonodake",
            current: MountainCurrentWeather(
                observedAt: retrievedAt,
                conditionCode: "clear",
                symbolName: "sun.max.fill",
                temperatureCelsius: 8,
                apparentTemperatureCelsius: 7,
                windSpeedMetersPerSecond: 2,
                windDirectionCode: "north"
            ),
            hourly: [],
            alerts: [],
            retrievedAt: retrievedAt,
            sourceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
    }

    private func makePreviousDay(targetDate: Date) -> PreviousDayWeatherSummary {
        PreviousDayWeatherSummary(
            mountainID: "tonodake",
            targetDate: targetDate,
            timeZoneIdentifier: "Asia/Tokyo",
            precipitationMillimeters: nil,
            snowfallCentimeters: nil,
            highTemperatureCelsius: 9,
            lowTemperatureCelsius: 2,
            retrievedAt: now,
            sourceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
    }
}

private actor FailingWeatherRepository: MountainWeatherRepository {
    let forecast: MountainWeatherForecast?
    let previousDay: PreviousDayWeatherSummary?
    private(set) var previousDayRefreshCount = 0

    init(
        forecast: MountainWeatherForecast?,
        previousDay: PreviousDayWeatherSummary?
    ) {
        self.forecast = forecast
        self.previousDay = previousDay
    }

    func cachedForecast(for mountainID: String) async throws -> MountainWeatherForecast? {
        forecast
    }

    func cachedPreviousDaySummary(
        for mountainID: String
    ) async throws -> PreviousDayWeatherSummary? {
        previousDay
    }

    func refreshForecast(
        for mountain: Mountain,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> MountainWeatherForecast {
        throw MountainWeatherRepositoryError.temporarilyUnavailable
    }

    func refreshPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> PreviousDayWeatherSummary {
        previousDayRefreshCount += 1
        throw MountainWeatherRepositoryError.temporarilyUnavailable
    }
}
