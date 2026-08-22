import Foundation
import Testing
@testable import YamaLens

struct MountainWeatherEvaluatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let evaluator = MountainWeatherEvaluator()

    @Test("取得後1時間と3時間の境界で鮮度を分類する")
    func classifiesFreshnessBoundaries() {
        #expect(
            evaluator.freshness(
                retrievedAt: now.addingTimeInterval(-MountainWeatherPolicy.freshInterval),
                now: now
            ) == .fresh
        )
        #expect(
            evaluator.freshness(
                retrievedAt: now.addingTimeInterval(-MountainWeatherPolicy.freshInterval - 1),
                now: now
            ) == .refreshRecommended
        )
        #expect(
            evaluator.freshness(
                retrievedAt: now.addingTimeInterval(-MountainWeatherPolicy.staleInterval - 1),
                now: now
            ) == .stale
        )
    }

    @Test("12時間以内の風速10m毎秒と15m毎秒を段階分けする")
    func classifiesWindWarnings() throws {
        let strong = evaluator.warnings(
            for: forecast(hours: [hour(offsetHours: 1, wind: 10)]),
            now: now
        )
        #expect(try #require(strong.first?.kind) == .strongWind)

        let severe = evaluator.warnings(
            for: forecast(hours: [hour(offsetHours: 12, wind: 15)]),
            now: now
        )
        #expect(try #require(severe.first?.kind) == .severeWind)

        let outside = evaluator.warnings(
            for: forecast(hours: [hour(offsetHours: 12.01, wind: 20)]),
            now: now
        )
        #expect(!outside.contains { $0.kind == .strongWind || $0.kind == .severeWind })
    }

    @Test("雷と雪氷を取得できた場合だけ注意表示する")
    func reportsThunderAndSnow() {
        let warnings = evaluator.warnings(
            for: forecast(
                hours: [
                    hour(offsetHours: 1, thunderstorm: true),
                    hour(offsetHours: 2, snowOrIce: true)
                ]
            ),
            now: now
        )
        #expect(warnings.contains { $0.kind == .thunderstorm })
        #expect(warnings.contains { $0.kind == .snowOrIce })
    }

    @Test("3時間以内に5度低下した場合だけ気温低下を表示する")
    func reportsRapidTemperatureDrop() {
        let warning = evaluator.warnings(
            for: forecast(
                hours: [
                    hour(offsetHours: 0, temperature: 8),
                    hour(offsetHours: 3, temperature: 3)
                ]
            ),
            now: now
        )
        #expect(warning.contains { $0.kind == .rapidTemperatureDrop && $0.value == 5 })

        let slowDrop = evaluator.warnings(
            for: forecast(
                hours: [
                    hour(offsetHours: 0, temperature: 8),
                    hour(offsetHours: 4, temperature: 3)
                ]
            ),
            now: now
        )
        #expect(!slowDrop.contains { $0.kind == .rapidTemperatureDrop })
    }

    @Test("丹沢の前日はAsia Tokyoの暦日で計算する")
    func calculatesPreviousDayInTokyo() throws {
        let formatter = ISO8601DateFormatter()
        let date = try #require(formatter.date(from: "2026-08-22T00:30:00+09:00"))
        let previous = try #require(MountainWeatherCalendar.previousDayStart(now: date))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: previous)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 21)
        #expect(components.hour == 0)
    }

    private func forecast(hours: [MountainHourlyWeather]) -> MountainWeatherForecast {
        MountainWeatherForecast(
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
            hourly: hours,
            alerts: [],
            retrievedAt: now,
            sourceName: "Apple Weather",
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
    }

    private func hour(
        offsetHours: Double,
        temperature: Double = 8,
        wind: Double = 2,
        thunderstorm: Bool = false,
        snowOrIce: Bool = false
    ) -> MountainHourlyWeather {
        MountainHourlyWeather(
            date: now.addingTimeInterval(offsetHours * 60 * 60),
            conditionCode: "clear",
            symbolName: "sun.max.fill",
            temperatureCelsius: temperature,
            windSpeedMetersPerSecond: wind,
            precipitationChance: 0,
            hasThunderstorm: thunderstorm,
            hasSnowOrIce: snowOrIce
        )
    }
}
