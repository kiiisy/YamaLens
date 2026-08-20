import Foundation
import SwiftUI

@MainActor
struct AppContainer {
    let mountainRepository: any MountainRepository
    let locationObservationProvider: any LocationObservationProvider
    let proximityCalculator: MountainProximityCalculator
    let cameraObservationProvider: any CameraObservationProvider
    let cameraPreview: AnyView

    init(
        mountainRepository: any MountainRepository = BootstrapMountainRepository(),
        locationObservationProvider: (any LocationObservationProvider)? = nil,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator()
    ) {
        self.mountainRepository = mountainRepository
        self.locationObservationProvider = locationObservationProvider
            ?? Self.makeLocationObservationProvider()
        self.proximityCalculator = proximityCalculator
        let cameraDependencies = Self.makeCameraDependencies()
        cameraObservationProvider = cameraDependencies.provider
        cameraPreview = cameraDependencies.preview
    }

    private static func makeLocationObservationProvider() -> any LocationObservationProvider {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-location-granted") {
            return FixedLocationObservationProvider(
                result: .success(
                    LocationObservation(
                        coordinate: GeoCoordinate(latitude: 35.4700, longitude: 139.1450),
                        horizontalAccuracyMeters: 8,
                        observedAt: .now
                    )
                )
            )
        }
        if arguments.contains("-ui-test-location-denied") {
            return FixedLocationObservationProvider(result: .failure(.denied))
        }
#endif
        return CoreLocationObservationProvider()
    }

    private static func makeCameraDependencies() -> (
        provider: any CameraObservationProvider,
        preview: AnyView
    ) {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-camera-active") {
            let provider = FixedCameraObservationProvider(
                result: .success(()),
                observation: CameraPoseObservation(
                    trueBearingDegrees: 25,
                    pitchDegrees: 2,
                    headingAccuracyDegrees: 5,
                    observedAt: .now,
                    trackingQuality: .normal
                )
            )
            return (provider, AnyView(Color(red: 0.14, green: 0.24, blue: 0.22)))
        }
        if arguments.contains("-ui-test-camera-denied") {
            let provider = FixedCameraObservationProvider(
                result: .failure(.denied),
                observation: nil
            )
            return (provider, AnyView(YamaColor.canvas))
        }
#endif
        let adapter = ARCameraSessionAdapter()
        return (adapter, AnyView(ARCameraPreview(adapter: adapter)))
    }
}

#if DEBUG
@MainActor
private final class FixedLocationObservationProvider: LocationObservationProvider {
    private let result: Result<LocationObservation, LocationObservationFailure>

    init(result: Result<LocationObservation, LocationObservationFailure>) {
        self.result = result
    }

    func authorizationState() -> LocationAuthorizationState {
        switch result {
        case .success:
            return .authorized
        case .failure(.denied):
            return .denied
        case .failure(.restricted):
            return .restricted
        case .failure:
            return .unavailable
        }
    }

    func requestCurrentLocation() async -> Result<LocationObservation, LocationObservationFailure> {
        result
    }
}

@MainActor
private final class FixedCameraObservationProvider: CameraObservationProvider {
    private let result: Result<Void, CameraSessionFailure>
    private let observation: CameraPoseObservation?

    init(result: Result<Void, CameraSessionFailure>, observation: CameraPoseObservation?) {
        self.result = result
        self.observation = observation
    }

    func start() async -> Result<Void, CameraSessionFailure> {
        result
    }

    func observations() -> AsyncStream<CameraPoseObservation> {
        AsyncStream { continuation in
            if let observation {
                continuation.yield(
                    CameraPoseObservation(
                        trueBearingDegrees: observation.trueBearingDegrees,
                        pitchDegrees: observation.pitchDegrees,
                        headingAccuracyDegrees: observation.headingAccuracyDegrees,
                        observedAt: .now,
                        trackingQuality: observation.trackingQuality
                    )
                )
            }
        }
    }

    func stop() {}
}
#endif
