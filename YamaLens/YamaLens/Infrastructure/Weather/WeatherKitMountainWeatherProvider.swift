import CoreLocation
import Foundation
import WeatherKit

nonisolated protocol MountainWeatherRemoteProviding: Sendable {
    func fetchForecast(for mountain: Mountain, now: Date) async throws -> MountainWeatherForecast

    func fetchPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        now: Date
    ) async throws -> PreviousDayWeatherSummary
}

actor WeatherKitMountainWeatherProvider: MountainWeatherRemoteProviding {
    private let service: WeatherService

    init(service: WeatherService = .shared) {
        self.service = service
    }

    func fetchForecast(
        for mountain: Mountain,
        now: Date
    ) async throws -> MountainWeatherForecast {
        let location = makeLocation(for: mountain)
        do {
            async let weather = service.weather(
                for: location,
                including: .current,
                .hourly(
                    startDate: now,
                    endDate: now.addingTimeInterval(MountainWeatherPolicy.forecastHorizon)
                ),
                .alerts
            )
            async let attribution = service.attribution
            let ((current, hourly, alerts), source) = try await (weather, attribution)
            guard isAllowedHTTPSURL(source.legalPageURL) else {
                throw MountainWeatherRepositoryError.invalidData
            }

            return MountainWeatherForecast(
                mountainID: mountain.id,
                current: map(current),
                hourly: hourly.map(map),
                alerts: (alerts ?? []).map(map),
                retrievedAt: now,
                sourceName: source.serviceName,
                legalPageURL: source.legalPageURL
            )
        } catch {
            throw map(error)
        }
    }

    func fetchPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        now: Date
    ) async throws -> PreviousDayWeatherSummary {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw MountainWeatherRepositoryError.invalidData
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: targetDate) else {
            throw MountainWeatherRepositoryError.invalidData
        }

        do {
            async let summaries = service.dailySummary(
                for: makeLocation(for: mountain),
                forDaysIn: DateInterval(start: targetDate, end: endDate),
                including: .precipitation,
                .temperature
            )
            async let attribution = service.attribution
            let ((precipitation, temperature), source) = try await (summaries, attribution)
            guard isAllowedHTTPSURL(source.legalPageURL) else {
                throw MountainWeatherRepositoryError.invalidData
            }
            let precipitationDay = precipitation.first {
                MountainWeatherCalendar.isSameDay(
                    $0.date,
                    targetDate,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
            let temperatureDay = temperature.first {
                MountainWeatherCalendar.isSameDay(
                    $0.date,
                    targetDate,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            }
            guard precipitationDay != nil || temperatureDay != nil else {
                throw MountainWeatherRepositoryError.invalidData
            }

            return PreviousDayWeatherSummary(
                mountainID: mountain.id,
                targetDate: targetDate,
                timeZoneIdentifier: timeZoneIdentifier,
                precipitationMillimeters: precipitationDay?.precipitationAmount
                    .converted(to: .millimeters).value,
                snowfallCentimeters: precipitationDay?.snowfallAmount
                    .converted(to: .centimeters).value,
                highTemperatureCelsius: temperatureDay?.highTemperature
                    .converted(to: .celsius).value,
                lowTemperatureCelsius: temperatureDay?.lowTemperature
                    .converted(to: .celsius).value,
                retrievedAt: now,
                sourceName: source.serviceName,
                legalPageURL: source.legalPageURL
            )
        } catch {
            throw map(error)
        }
    }

    private func makeLocation(for mountain: Mountain) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: mountain.coordinate.latitude,
                longitude: mountain.coordinate.longitude
            ),
            altitude: CLLocationDistance(mountain.elevationMeters),
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: .now
        )
    }

    private func map(_ weather: CurrentWeather) -> MountainCurrentWeather {
        MountainCurrentWeather(
            observedAt: weather.date,
            conditionCode: weather.condition.rawValue,
            symbolName: weather.symbolName,
            temperatureCelsius: weather.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: weather.apparentTemperature.converted(to: .celsius).value,
            windSpeedMetersPerSecond: weather.wind.speed.converted(to: .metersPerSecond).value,
            windDirectionCode: weather.wind.compassDirection.rawValue
        )
    }

    private func map(_ weather: HourWeather) -> MountainHourlyWeather {
        MountainHourlyWeather(
            date: weather.date,
            conditionCode: weather.condition.rawValue,
            symbolName: weather.symbolName,
            temperatureCelsius: weather.temperature.converted(to: .celsius).value,
            windSpeedMetersPerSecond: weather.wind.speed.converted(to: .metersPerSecond).value,
            precipitationChance: weather.precipitationChance,
            hasThunderstorm: Self.thunderstormConditions.contains(weather.condition),
            hasSnowOrIce: Self.snowOrIceConditions.contains(weather.condition)
                || Self.snowOrIcePrecipitation.contains(weather.precipitation)
        )
    }

    private func map(_ alert: WeatherAlert) -> MountainWeatherAlert {
        MountainWeatherAlert(
            summary: alert.summary,
            source: alert.source,
            severityCode: alert.severity.rawValue,
            detailsURL: isAllowedHTTPSURL(alert.detailsURL) ? alert.detailsURL : nil
        )
    }

    private func map(_ error: Error) -> MountainWeatherRepositoryError {
        if error is CancellationError {
            return .cancelled
        }
        if let repositoryError = error as? MountainWeatherRepositoryError {
            return repositoryError
        }
        if let weatherError = error as? WeatherError, weatherError == .permissionDenied {
            return .permissionDenied
        }
        return .temporarilyUnavailable
    }

    private func isAllowedHTTPSURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.scheme?.lowercased() == "https"
            && components.host?.isEmpty == false
            && components.user == nil
            && components.password == nil
            && url.absoluteString.utf8.count <= 2_048
    }

    private static let thunderstormConditions: Set<WeatherCondition> = [
        .isolatedThunderstorms,
        .scatteredThunderstorms,
        .strongStorms,
        .thunderstorms
    ]

    private static let snowOrIceConditions: Set<WeatherCondition> = [
        .blizzard,
        .blowingSnow,
        .flurries,
        .freezingDrizzle,
        .freezingRain,
        .hail,
        .heavySnow,
        .sleet,
        .snow,
        .sunFlurries,
        .wintryMix
    ]

    private static let snowOrIcePrecipitation: Set<Precipitation> = [
        .hail,
        .mixed,
        .sleet,
        .snow
    ]
}
