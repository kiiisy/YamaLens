import Foundation

nonisolated struct LocationObservation: Equatable, Sendable {
    let coordinate: GeoCoordinate
    let horizontalAccuracyMeters: Double
    let observedAt: Date
}

nonisolated enum LocationObservationQuality: Equatable, Sendable {
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
