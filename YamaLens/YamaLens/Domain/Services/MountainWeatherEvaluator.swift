import Foundation

nonisolated struct MountainWeatherEvaluator: Sendable {
    func freshness(retrievedAt: Date, now: Date) -> WeatherFreshness {
        let age = max(0, now.timeIntervalSince(retrievedAt))
        if age <= MountainWeatherPolicy.freshInterval {
            return .fresh
        }
        if age <= MountainWeatherPolicy.staleInterval {
            return .refreshRecommended
        }
        return .stale
    }

    func warnings(
        for forecast: MountainWeatherForecast,
        now: Date
    ) -> [MountainWeatherWarning] {
        let horizonEnd = now.addingTimeInterval(MountainWeatherPolicy.forecastHorizon)
        let hours = forecast.hourly
            .filter { $0.date >= now && $0.date <= horizonEnd }
            .sorted { $0.date < $1.date }
        var result: [MountainWeatherWarning] = []

        if let peakWind = hours.max(by: {
            $0.windSpeedMetersPerSecond < $1.windSpeedMetersPerSecond
        }), peakWind.windSpeedMetersPerSecond >= MountainWeatherPolicy.strongWindSpeedMetersPerSecond {
            let isSevere = peakWind.windSpeedMetersPerSecond
                >= MountainWeatherPolicy.severeWindSpeedMetersPerSecond
            result.append(
                MountainWeatherWarning(
                    kind: isSevere ? .severeWind : .strongWind,
                    date: peakWind.date,
                    value: peakWind.windSpeedMetersPerSecond,
                    title: isSevere ? "非常に強い風の予報" : "強い風の予報",
                    detailsURL: nil
                )
            )
        }

        if let thunderstorm = hours.first(where: \.hasThunderstorm) {
            result.append(
                MountainWeatherWarning(
                    kind: .thunderstorm,
                    date: thunderstorm.date,
                    value: nil,
                    title: "雷を伴う予報",
                    detailsURL: nil
                )
            )
        }

        if let snowOrIce = hours.first(where: \.hasSnowOrIce) {
            result.append(
                MountainWeatherWarning(
                    kind: .snowOrIce,
                    date: snowOrIce.date,
                    value: nil,
                    title: "雪・みぞれ・凍結性降水の予報",
                    detailsURL: nil
                )
            )
        }

        if let drop = firstRapidTemperatureDrop(in: hours) {
            result.append(
                MountainWeatherWarning(
                    kind: .rapidTemperatureDrop,
                    date: drop.endDate,
                    value: drop.celsius,
                    title: "3時間で大きく気温が低下する予報",
                    detailsURL: nil
                )
            )
        }

        result.append(contentsOf: forecast.alerts.map { alert in
            MountainWeatherWarning(
                kind: .officialAlert,
                date: nil,
                value: nil,
                title: "\(alert.summary)（\(alert.source)）",
                detailsURL: alert.detailsURL
            )
        })
        return result
    }

    private func firstRapidTemperatureDrop(
        in hours: [MountainHourlyWeather]
    ) -> (endDate: Date, celsius: Double)? {
        for start in hours {
            for end in hours where end.date > start.date {
                let interval = end.date.timeIntervalSince(start.date)
                guard interval <= MountainWeatherPolicy.rapidTemperatureDropInterval else {
                    break
                }
                let drop = start.temperatureCelsius - end.temperatureCelsius
                if drop >= MountainWeatherPolicy.rapidTemperatureDropCelsius {
                    return (end.date, drop)
                }
            }
        }
        return nil
    }
}

nonisolated enum MountainWeatherCalendar {
    static let timeZoneIdentifier = "Asia/Tokyo"

    static func previousDayStart(now: Date) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -1, to: today)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, timeZoneIdentifier: String) -> Bool {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
