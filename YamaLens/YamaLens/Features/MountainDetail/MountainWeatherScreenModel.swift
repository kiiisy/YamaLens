import Foundation
import Observation

nonisolated enum MountainWeatherDisplayFailure: Equatable, Sendable {
    case permissionDenied
    case temporarilyUnavailable
    case invalidData
    case storageUnavailable
}

nonisolated struct MountainWeatherForecastContent: Equatable, Sendable {
    let forecast: MountainWeatherForecast
    let freshness: WeatherFreshness
    let isRefreshing: Bool
    let updateFailure: MountainWeatherDisplayFailure?
}

nonisolated enum MountainWeatherForecastState: Equatable, Sendable {
    case loading
    case loaded(MountainWeatherForecastContent)
    case unavailable(MountainWeatherDisplayFailure)
}

nonisolated struct PreviousDayWeatherContent: Equatable, Sendable {
    let summary: PreviousDayWeatherSummary
    let isRefreshing: Bool
    let updateFailure: MountainWeatherDisplayFailure?
}

nonisolated enum PreviousDayWeatherState: Equatable, Sendable {
    case loading
    case loaded(PreviousDayWeatherContent)
    case unavailable(MountainWeatherDisplayFailure)
}

@MainActor
@Observable
final class MountainWeatherScreenModel {
    private let repository: any MountainWeatherRepository
    private let evaluator: MountainWeatherEvaluator
    private let now: @Sendable () -> Date
    private(set) var forecastState: MountainWeatherForecastState = .loading
    private(set) var previousDayState: PreviousDayWeatherState = .loading
    private var hasLoaded = false

    init(
        repository: any MountainWeatherRepository,
        evaluator: MountainWeatherEvaluator = MountainWeatherEvaluator(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.evaluator = evaluator
        self.now = now
    }

    func load(for mountain: Mountain) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        let requestDate = now()
        let previousDay = MountainWeatherCalendar.previousDayStart(now: requestDate)

        do {
            if let cached = try await repository.cachedForecast(for: mountain.id) {
                forecastState = contentState(forecast: cached, now: requestDate)
            }
        } catch {
            forecastState = .unavailable(failure(from: error))
        }

        if let previousDay {
            do {
                if let cached = try await repository.cachedPreviousDaySummary(for: mountain.id),
                   MountainWeatherCalendar.isSameDay(
                       cached.targetDate,
                       previousDay,
                       timeZoneIdentifier: MountainWeatherCalendar.timeZoneIdentifier
                   ) {
                    previousDayState = .loaded(
                        PreviousDayWeatherContent(
                            summary: cached,
                            isRefreshing: false,
                            updateFailure: nil
                        )
                    )
                }
            } catch {
                previousDayState = .unavailable(failure(from: error))
            }
        } else {
            previousDayState = .unavailable(.invalidData)
        }

        await withTaskGroup(of: Void.self) { group in
            if shouldRefreshForecast(now: requestDate) {
                group.addTask { await self.refreshForecast(for: mountain, reason: .automatic) }
            }
            if shouldRefreshPreviousDay(targetDate: previousDay, now: requestDate) {
                group.addTask {
                    await self.refreshPreviousDay(
                        for: mountain,
                        targetDate: previousDay,
                        reason: .automatic
                    )
                }
            }
        }
    }

    func refresh(for mountain: Mountain) async {
        let targetDate = MountainWeatherCalendar.previousDayStart(now: now())
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshForecast(for: mountain, reason: .manual) }
            group.addTask {
                await self.refreshPreviousDay(
                    for: mountain,
                    targetDate: targetDate,
                    reason: .manual
                )
            }
        }
    }

    private func refreshForecast(
        for mountain: Mountain,
        reason: WeatherRefreshReason
    ) async {
        let requestDate = now()
        setForecastRefreshing(true)
        do {
            let forecast = try await repository.refreshForecast(
                for: mountain,
                reason: reason,
                now: requestDate
            )
            forecastState = contentState(forecast: forecast, now: now())
        } catch MountainWeatherRepositoryError.automaticRefreshThrottled {
            setForecastRefreshing(false)
        } catch {
            setForecastFailure(failure(from: error))
        }
    }

    private func refreshPreviousDay(
        for mountain: Mountain,
        targetDate: Date?,
        reason: WeatherRefreshReason
    ) async {
        guard let targetDate else {
            previousDayState = .unavailable(.invalidData)
            return
        }
        setPreviousDayRefreshing(true)
        do {
            let summary = try await repository.refreshPreviousDaySummary(
                for: mountain,
                targetDate: targetDate,
                timeZoneIdentifier: MountainWeatherCalendar.timeZoneIdentifier,
                reason: reason,
                now: now()
            )
            previousDayState = .loaded(
                PreviousDayWeatherContent(
                    summary: summary,
                    isRefreshing: false,
                    updateFailure: nil
                )
            )
        } catch MountainWeatherRepositoryError.automaticRefreshThrottled {
            setPreviousDayRefreshing(false)
        } catch {
            setPreviousDayFailure(failure(from: error))
        }
    }

    private func shouldRefreshForecast(now: Date) -> Bool {
        guard case .loaded(let content) = forecastState else { return true }
        return now.timeIntervalSince(content.forecast.retrievedAt)
            > MountainWeatherPolicy.automaticRefreshInterval
    }

    private func shouldRefreshPreviousDay(targetDate: Date?, now: Date) -> Bool {
        guard let targetDate,
              case .loaded(let content) = previousDayState,
              MountainWeatherCalendar.isSameDay(
                  content.summary.targetDate,
                  targetDate,
                  timeZoneIdentifier: MountainWeatherCalendar.timeZoneIdentifier
              ) else {
            return true
        }
        return now.timeIntervalSince(content.summary.retrievedAt)
            > MountainWeatherPolicy.previousDayCacheInterval
    }

    private func contentState(
        forecast: MountainWeatherForecast,
        now: Date
    ) -> MountainWeatherForecastState {
        .loaded(
            MountainWeatherForecastContent(
                forecast: forecast,
                freshness: evaluator.freshness(retrievedAt: forecast.retrievedAt, now: now),
                isRefreshing: false,
                updateFailure: nil
            )
        )
    }

    private func setForecastRefreshing(_ isRefreshing: Bool) {
        if case .loaded(let content) = forecastState {
            forecastState = .loaded(
                MountainWeatherForecastContent(
                    forecast: content.forecast,
                    freshness: evaluator.freshness(
                        retrievedAt: content.forecast.retrievedAt,
                        now: now()
                    ),
                    isRefreshing: isRefreshing,
                    updateFailure: nil
                )
            )
        } else if isRefreshing {
            forecastState = .loading
        }
    }

    private func setForecastFailure(_ failure: MountainWeatherDisplayFailure) {
        if case .loaded(let content) = forecastState {
            forecastState = .loaded(
                MountainWeatherForecastContent(
                    forecast: content.forecast,
                    freshness: evaluator.freshness(
                        retrievedAt: content.forecast.retrievedAt,
                        now: now()
                    ),
                    isRefreshing: false,
                    updateFailure: failure
                )
            )
        } else {
            forecastState = .unavailable(failure)
        }
    }

    private func setPreviousDayRefreshing(_ isRefreshing: Bool) {
        if case .loaded(let content) = previousDayState {
            previousDayState = .loaded(
                PreviousDayWeatherContent(
                    summary: content.summary,
                    isRefreshing: isRefreshing,
                    updateFailure: nil
                )
            )
        } else if isRefreshing {
            previousDayState = .loading
        }
    }

    private func setPreviousDayFailure(_ failure: MountainWeatherDisplayFailure) {
        if case .loaded(let content) = previousDayState {
            previousDayState = .loaded(
                PreviousDayWeatherContent(
                    summary: content.summary,
                    isRefreshing: false,
                    updateFailure: failure
                )
            )
        } else {
            previousDayState = .unavailable(failure)
        }
    }

    private func failure(from error: Error) -> MountainWeatherDisplayFailure {
        switch error as? MountainWeatherRepositoryError {
        case .permissionDenied:
            return .permissionDenied
        case .invalidData:
            return .invalidData
        case .storageUnavailable:
            return .storageUnavailable
        case .temporarilyUnavailable,
             .automaticRefreshThrottled,
             .cancelled,
             nil:
            return .temporarilyUnavailable
        }
    }
}
