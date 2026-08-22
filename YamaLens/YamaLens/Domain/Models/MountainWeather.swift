import Foundation

nonisolated enum MountainWeatherPolicy {
    static let automaticRefreshInterval: TimeInterval = 30 * 60
    static let freshInterval: TimeInterval = 60 * 60
    static let staleInterval: TimeInterval = 3 * 60 * 60
    static let previousDayCacheInterval: TimeInterval = 6 * 60 * 60
    static let automaticRetryCooldown: TimeInterval = 60
    static let requestTimeout: TimeInterval = 15
    static let retryDelay: TimeInterval = 2
    static let forecastHorizon: TimeInterval = 12 * 60 * 60
    static let strongWindSpeedMetersPerSecond = 10.0
    static let severeWindSpeedMetersPerSecond = 15.0
    static let rapidTemperatureDropInterval: TimeInterval = 3 * 60 * 60
    static let rapidTemperatureDropCelsius = 5.0
}

nonisolated enum WeatherFreshness: String, Codable, Equatable, Sendable {
    case fresh
    case refreshRecommended
    case stale
}

nonisolated struct MountainCurrentWeather: Codable, Equatable, Sendable {
    let observedAt: Date
    let conditionCode: String
    let symbolName: String
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let windSpeedMetersPerSecond: Double
    let windDirectionCode: String
}

nonisolated struct MountainHourlyWeather: Codable, Equatable, Sendable {
    let date: Date
    let conditionCode: String
    let symbolName: String
    let temperatureCelsius: Double
    let windSpeedMetersPerSecond: Double
    let precipitationChance: Double
    let hasThunderstorm: Bool
    let hasSnowOrIce: Bool
}

nonisolated struct MountainWeatherAlert: Codable, Equatable, Sendable {
    let summary: String
    let source: String
    let severityCode: String
    let detailsURL: URL?
}

nonisolated struct MountainWeatherForecast: Codable, Equatable, Sendable {
    let mountainID: String
    let current: MountainCurrentWeather
    let hourly: [MountainHourlyWeather]
    let alerts: [MountainWeatherAlert]
    let retrievedAt: Date
    let sourceName: String
    let legalPageURL: URL
}

nonisolated struct PreviousDayWeatherSummary: Codable, Equatable, Sendable {
    let mountainID: String
    let targetDate: Date
    let timeZoneIdentifier: String
    let precipitationMillimeters: Double?
    let snowfallCentimeters: Double?
    let highTemperatureCelsius: Double?
    let lowTemperatureCelsius: Double?
    let retrievedAt: Date
    let sourceName: String
    let legalPageURL: URL
}

nonisolated enum MountainWeatherWarningKind: String, Equatable, Sendable {
    case strongWind
    case severeWind
    case thunderstorm
    case snowOrIce
    case rapidTemperatureDrop
    case officialAlert
}

nonisolated struct MountainWeatherWarning: Equatable, Sendable, Identifiable {
    let kind: MountainWeatherWarningKind
    let date: Date?
    let value: Double?
    let title: String
    let detailsURL: URL?

    var id: String {
        "\(kind.rawValue)-\(date?.timeIntervalSince1970.description ?? title)"
    }
}
