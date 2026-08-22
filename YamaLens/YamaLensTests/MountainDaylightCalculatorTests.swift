import Foundation
import Testing
@testable import YamaLens

struct MountainDaylightCalculatorTests {
    private let calculator = MountainDaylightCalculator()

    @Test("丹沢の夏の日の出と日の入りを現地日付で計算する")
    func calculatesSummerDaylightInTanzawa() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try makeDate(year: 2026, month: 8, day: 22, timeZone: timeZone)

        let daylight = try #require(
            calculator.daylight(
                on: date,
                at: GeoCoordinate(latitude: 35.4541667, longitude: 139.1633333),
                timeZone: timeZone
            )
        )

        #expect(abs(localMinutes(daylight.sunrise, timeZone: timeZone) - 307) <= 5)
        #expect(abs(localMinutes(daylight.sunset, timeZone: timeZone) - 1_100) <= 5)
        #expect(daylight.sunrise < daylight.sunset)
    }

    @Test("太陽が昇降しない緯度では時刻を作らない")
    func returnsUnavailableAtPolarDayBoundary() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try makeDate(year: 2026, month: 6, day: 21, timeZone: timeZone)

        let daylight = calculator.daylight(
            on: date,
            at: GeoCoordinate(latitude: 90, longitude: 0),
            timeZone: timeZone
        )

        #expect(daylight == nil)
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        )
    }

    private func localMinutes(_ date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? -24) * 60 + (components.minute ?? -60)
    }
}
