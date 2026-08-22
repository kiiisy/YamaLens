import Foundation

nonisolated struct MountainDaylightCalculator: Sendable {
    private static let officialZenithDegrees = 90.833

    func daylight(
        on date: Date,
        at coordinate: GeoCoordinate,
        timeZone: TimeZone
    ) -> MountainDaylight? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date),
            let sunrise = event(
                isSunrise: true,
                dayOfYear: dayOfYear,
                localDate: date,
                coordinate: coordinate,
                calendar: calendar,
                timeZone: timeZone
            ),
            let sunset = event(
                isSunrise: false,
                dayOfYear: dayOfYear,
                localDate: date,
                coordinate: coordinate,
                calendar: calendar,
                timeZone: timeZone
            )
        else {
            return nil
        }
        return MountainDaylight(
            date: calendar.startOfDay(for: date),
            sunrise: sunrise,
            sunset: sunset
        )
    }

    private func event(
        isSunrise: Bool,
        dayOfYear: Int,
        localDate: Date,
        coordinate: GeoCoordinate,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date? {
        let longitudeHour = coordinate.longitude / 15
        let approximateTime = Double(dayOfYear)
            + ((isSunrise ? 6 : 18) - longitudeHour) / 24
        let meanAnomaly = 0.9856 * approximateTime - 3.289
        let trueLongitude = normalizedDegrees(
            meanAnomaly
                + 1.916 * sineDegrees(meanAnomaly)
                + 0.020 * sineDegrees(2 * meanAnomaly)
                + 282.634
        )
        var rightAscension = normalizedDegrees(
            radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        )
        let longitudeQuadrant = floor(trueLongitude / 90) * 90
        let rightAscensionQuadrant = floor(rightAscension / 90) * 90
        rightAscension = (rightAscension + longitudeQuadrant - rightAscensionQuadrant) / 15

        let sineDeclination = 0.39782 * sineDegrees(trueLongitude)
        let cosineDeclination = cos(asin(sineDeclination))
        let cosineHourAngle = (
            cosineDegrees(Self.officialZenithDegrees)
                - sineDeclination * sineDegrees(coordinate.latitude)
        ) / (cosineDeclination * cosineDegrees(coordinate.latitude))
        guard (-1...1).contains(cosineHourAngle) else { return nil }

        let hourAngleDegrees = isSunrise
            ? 360 - radiansToDegrees(acos(cosineHourAngle))
            : radiansToDegrees(acos(cosineHourAngle))
        let hourAngle = hourAngleDegrees / 15
        let localMeanTime = hourAngle + rightAscension
            - 0.06571 * approximateTime - 6.622
        let universalTimeHours = normalizedHours(localMeanTime - longitudeHour)

        let localNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: localDate)
            ?? localDate
        let offsetHours = Double(timeZone.secondsFromGMT(for: localNoon)) / 3_600
        let localHours = normalizedHours(universalTimeHours + offsetHours)
        let hour = Int(localHours)
        let minuteValue = (localHours - Double(hour)) * 60
        let minute = Int(minuteValue)
        let second = Int(((minuteValue - Double(minute)) * 60).rounded())
        let components = calendar.dateComponents([.year, .month, .day], from: localDate)
        return calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute,
                second: min(second, 59)
            )
        )
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func normalizedHours(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 24)
        return remainder >= 0 ? remainder : remainder + 24
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private func sineDegrees(_ degrees: Double) -> Double {
        sin(degreesToRadians(degrees))
    }

    private func cosineDegrees(_ degrees: Double) -> Double {
        cos(degreesToRadians(degrees))
    }
}
