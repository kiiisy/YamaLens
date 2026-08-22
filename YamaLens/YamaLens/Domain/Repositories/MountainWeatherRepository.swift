import Foundation

nonisolated enum WeatherRefreshReason: Equatable, Sendable {
    case automatic
    case manual
}

nonisolated enum MountainWeatherRepositoryError: Error, Equatable, Sendable {
    case permissionDenied
    case temporarilyUnavailable
    case automaticRefreshThrottled
    case invalidData
    case storageUnavailable
    case cancelled
}

nonisolated protocol MountainWeatherRepository: Sendable {
    func cachedForecast(for mountainID: String) async throws -> MountainWeatherForecast?
    func cachedPreviousDaySummary(for mountainID: String) async throws -> PreviousDayWeatherSummary?

    func refreshForecast(
        for mountain: Mountain,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> MountainWeatherForecast

    func refreshPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> PreviousDayWeatherSummary
}
