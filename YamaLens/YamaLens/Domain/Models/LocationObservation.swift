import Foundation

nonisolated struct LocationObservation: Codable, Equatable, Sendable {
    let coordinate: GeoCoordinate
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double
    let verticalAccuracyMeters: Double?
    let observedAt: Date

    init(
        coordinate: GeoCoordinate,
        altitudeMeters: Double? = nil,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double? = nil,
        observedAt: Date
    ) {
        self.coordinate = coordinate
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.observedAt = observedAt
    }
}

nonisolated enum LocationObservationQuality: Codable, Equatable, Sendable {
    case good
    case reduced
}

nonisolated enum CurrentLocationState: Equatable, Sendable {
    case notRequested
    case loading
    case available(LocationObservation, quality: LocationObservationQuality)
    case denied
    case restricted
    case insufficientAccuracy
    case unavailable
}

nonisolated enum LocationObservationFailure: Error, Equatable, Sendable {
    case denied
    case restricted
    case servicesDisabled
    case invalidObservation
    case unavailable
    case requestInProgress
}

nonisolated enum LocationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}
