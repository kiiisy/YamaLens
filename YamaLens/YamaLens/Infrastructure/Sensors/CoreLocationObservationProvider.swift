import CoreLocation
import Foundation

@MainActor
final class CoreLocationObservationProvider: NSObject, LocationObservationProvider {
    private let locationManager: CLLocationManager
    private let maximumObservationAgeSeconds: TimeInterval
    private var continuation: CheckedContinuation<
        Result<LocationObservation, LocationObservationFailure>,
        Never
    >?

    init(
        maximumObservationAgeSeconds: TimeInterval = CandidateTuning.default.maximumLocationAgeSeconds
    ) {
        locationManager = CLLocationManager()
        self.maximumObservationAgeSeconds = maximumObservationAgeSeconds
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func authorizationState() -> LocationAuthorizationState {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    func requestCurrentLocation() async -> Result<LocationObservation, LocationObservationFailure> {
        guard continuation == nil else { return .failure(.requestInProgress) }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            continueRequest(for: locationManager.authorizationStatus)
        }
    }

    private func continueRequest(for authorizationStatus: CLAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied:
            finish(with: .failure(.denied))
        case .restricted:
            finish(with: .failure(.restricted))
        @unknown default:
            finish(with: .failure(.unavailable))
        }
    }

    private func finish(
        with result: Result<LocationObservation, LocationObservationFailure>
    ) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

extension CoreLocationObservationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        continueRequest(for: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(.invalidObservation))
            return
        }

        let age = Date().timeIntervalSince(location.timestamp)
        guard
            age >= -1,
            age <= maximumObservationAgeSeconds,
            location.horizontalAccuracy >= 0
        else {
            finish(with: .failure(.invalidObservation))
            return
        }

        let observation = LocationObservation(
            coordinate: GeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            horizontalAccuracyMeters: location.horizontalAccuracy,
            observedAt: location.timestamp
        )
        finish(with: .success(observation))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        if let locationError = error as? CLError, locationError.code == .denied {
            finish(with: .failure(.denied))
        } else {
            finish(with: .failure(.unavailable))
        }
    }
}
