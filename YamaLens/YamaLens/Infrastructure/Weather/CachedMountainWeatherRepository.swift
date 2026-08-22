import Foundation

actor CachedMountainWeatherRepository: MountainWeatherRepository {
    private let provider: any MountainWeatherRemoteProviding
    private let cache: any MountainWeatherCaching
    private var forecastTasks: [String: Task<MountainWeatherForecast, Error>] = [:]
    private var previousDayTasks: [String: Task<PreviousDayWeatherSummary, Error>] = [:]
    private var forecastFailureDates: [String: Date] = [:]
    private var previousDayFailureDates: [String: Date] = [:]

    init(
        provider: any MountainWeatherRemoteProviding = WeatherKitMountainWeatherProvider(),
        cache: any MountainWeatherCaching = FileMountainWeatherCache()
    ) {
        self.provider = provider
        self.cache = cache
    }

    func cachedForecast(for mountainID: String) async throws -> MountainWeatherForecast? {
        try await cache.forecast(for: mountainID)
    }

    func cachedPreviousDaySummary(
        for mountainID: String
    ) async throws -> PreviousDayWeatherSummary? {
        try await cache.previousDaySummary(for: mountainID)
    }

    func refreshForecast(
        for mountain: Mountain,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> MountainWeatherForecast {
        if let task = forecastTasks[mountain.id] {
            return try await task.value
        }
        try enforceCooldown(
            reason: reason,
            lastFailure: forecastFailureDates[mountain.id],
            now: now
        )
        let provider = provider
        let cache = cache
        let task = Task {
            let forecast = try await Self.withRetry {
                try await provider.fetchForecast(for: mountain, now: now)
            }
            try await cache.save(forecast)
            return forecast
        }
        forecastTasks[mountain.id] = task
        do {
            let result = try await task.value
            forecastTasks[mountain.id] = nil
            forecastFailureDates[mountain.id] = nil
            return result
        } catch {
            forecastTasks[mountain.id] = nil
            if Self.isTemporary(error) {
                forecastFailureDates[mountain.id] = now
            }
            throw Self.normalized(error)
        }
    }

    func refreshPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> PreviousDayWeatherSummary {
        let key = "\(mountain.id)-\(targetDate.timeIntervalSince1970)"
        if let task = previousDayTasks[key] {
            return try await task.value
        }
        try enforceCooldown(
            reason: reason,
            lastFailure: previousDayFailureDates[mountain.id],
            now: now
        )
        let provider = provider
        let cache = cache
        let task = Task {
            let summary = try await Self.withRetry {
                try await provider.fetchPreviousDaySummary(
                    for: mountain,
                    targetDate: targetDate,
                    timeZoneIdentifier: timeZoneIdentifier,
                    now: now
                )
            }
            try await cache.save(summary)
            return summary
        }
        previousDayTasks[key] = task
        do {
            let result = try await task.value
            previousDayTasks[key] = nil
            previousDayFailureDates[mountain.id] = nil
            return result
        } catch {
            previousDayTasks[key] = nil
            if Self.isTemporary(error) {
                previousDayFailureDates[mountain.id] = now
            }
            throw Self.normalized(error)
        }
    }

    private func enforceCooldown(
        reason: WeatherRefreshReason,
        lastFailure: Date?,
        now: Date
    ) throws {
        guard reason == .automatic,
              let lastFailure,
              now.timeIntervalSince(lastFailure) < MountainWeatherPolicy.automaticRetryCooldown else {
            return
        }
        throw MountainWeatherRepositoryError.automaticRefreshThrottled
    }

    private nonisolated static func withRetry<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await withTimeout(operation: operation)
        } catch {
            guard isTemporary(error) else { throw normalized(error) }
            try await Task.sleep(for: .seconds(MountainWeatherPolicy.retryDelay))
            return try await withTimeout(operation: operation)
        }
    }

    private nonisolated static func withTimeout<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(MountainWeatherPolicy.requestTimeout))
                throw MountainWeatherRepositoryError.temporarilyUnavailable
            }
            guard let result = try await group.next() else {
                throw MountainWeatherRepositoryError.temporarilyUnavailable
            }
            group.cancelAll()
            return result
        }
    }

    private nonisolated static func isTemporary(_ error: Error) -> Bool {
        normalized(error) == .temporarilyUnavailable
    }

    private nonisolated static func normalized(_ error: Error) -> MountainWeatherRepositoryError {
        if error is CancellationError {
            return .cancelled
        }
        return error as? MountainWeatherRepositoryError ?? .temporarilyUnavailable
    }
}
