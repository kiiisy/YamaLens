import Foundation
import SwiftUI
import UIKit

@MainActor
struct AppContainer {
    let mountainRepository: any MountainRepository
    let locationObservationProvider: any LocationObservationProvider
    let proximityCalculator: MountainProximityCalculator
    let cameraObservationProvider: any CameraObservationProvider
    let cameraPreview: AnyView
    let cameraDiagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let cameraDiagnosticDevice: CameraDiagnosticDevice?
    let terrainVisibilityResolver: (any TerrainVisibilityResolving)?

    init(
        mountainRepository: any MountainRepository = BootstrapMountainRepository(),
        locationObservationProvider: (any LocationObservationProvider)? = nil,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator()
    ) {
        self.mountainRepository = mountainRepository
        self.locationObservationProvider = locationObservationProvider
            ?? Self.makeLocationObservationProvider()
        self.proximityCalculator = proximityCalculator
        if let offlinePackageRootURL = Self.offlinePackageRootURL() {
            let offlinePackageStore = OfflinePackageStore(
                rootURL: offlinePackageRootURL,
                validator: OfflinePackageValidator(publicKeys: [:])
            )
            terrainVisibilityResolver = ActiveOfflinePackageTerrainVisibilityResolver(
                store: offlinePackageStore
            )
        } else {
            terrainVisibilityResolver = nil
        }
        let cameraDependencies = Self.makeCameraDependencies()
        cameraObservationProvider = cameraDependencies.provider
        cameraPreview = cameraDependencies.preview
#if DEBUG
        cameraDiagnosticLogRepository = FileCameraDiagnosticLogRepository()
        cameraDiagnosticDevice = CameraDiagnosticDevice(
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "未取得",
            operatingSystemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
#else
        cameraDiagnosticLogRepository = nil
        cameraDiagnosticDevice = nil
#endif
    }

    private static func offlinePackageRootURL() -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appending(path: "OfflinePackages", directoryHint: .isDirectory)
    }

    private static func makeLocationObservationProvider() -> any LocationObservationProvider {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-location-granted") {
            return FixedLocationObservationProvider(
                result: .success(
                    LocationObservation(
                        coordinate: GeoCoordinate(latitude: 35.4700, longitude: 139.1450),
                        altitudeMeters: 1_300,
                        horizontalAccuracyMeters: 8,
                        verticalAccuracyMeters: 8,
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
                    trueBearingDegrees: 34,
                    pitchDegrees: 2,
                    headingAccuracyDegrees: 5,
                    observedAt: .now,
                    trackingQuality: .normal,
                    projectionGeometry: testProjectionGeometry(facingDegrees: 34)
                )
            )
            return (provider, AnyView(Color(red: 0.14, green: 0.24, blue: 0.22)))
        }
        if arguments.contains("-ui-test-camera-heading-unavailable") {
            let provider = FixedCameraObservationProvider(
                result: .success(()),
                observation: CameraPoseObservation(
                    trueBearingDegrees: 34,
                    pitchDegrees: 2,
                    headingAccuracyDegrees: 5,
                    observedAt: .now,
                    trackingQuality: .normal,
                    projectionGeometry: testProjectionGeometry(facingDegrees: 34)
                ),
                becomesTemporarilyUnavailable: true
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

#if DEBUG
    private static func testProjectionGeometry(
        facingDegrees: Double
    ) -> CameraProjectionGeometry {
        let radians = facingDegrees * .pi / 180
        let viewport = ViewportSize(width: 393, height: 700)
        let focalLength = 421.0
        return CameraProjectionGeometry(
            cameraRightInWorld: SpatialVector(
                x: cos(radians),
                y: 0,
                z: sin(radians)
            ),
            cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
            cameraBackInWorld: SpatialVector(
                x: -sin(radians),
                y: 0,
                z: cos(radians)
            ),
            focalLengthXPixels: focalLength,
            focalLengthYPixels: focalLength,
            principalPointXPixels: viewport.width / 2,
            principalPointYPixels: viewport.height / 2,
            imageSizePixels: viewport,
            normalizedImageToViewport: NormalizedImageTransform(
                a: 1,
                b: 0,
                c: 0,
                d: 1,
                translationX: 0,
                translationY: 0
            ),
            viewportSizePoints: viewport,
            horizontalFieldOfViewDegrees: 50,
            verticalFieldOfViewDegrees: 80
        )
    }
#endif
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
    private let becomesTemporarilyUnavailable: Bool

    init(
        result: Result<Void, CameraSessionFailure>,
        observation: CameraPoseObservation?,
        becomesTemporarilyUnavailable: Bool = false
    ) {
        self.result = result
        self.observation = observation
        self.becomesTemporarilyUnavailable = becomesTemporarilyUnavailable
    }

    func start() async -> Result<Void, CameraSessionFailure> {
        result
    }

    func observations() -> AsyncStream<CameraObservationUpdate> {
        AsyncStream { continuation in
            if let observation {
                continuation.yield(.pose(
                    CameraPoseObservation(
                        trueBearingDegrees: observation.trueBearingDegrees,
                        pitchDegrees: observation.pitchDegrees,
                        headingAccuracyDegrees: observation.headingAccuracyDegrees,
                        observedAt: .now,
                        trackingQuality: observation.trackingQuality,
                        projectionGeometry: observation.projectionGeometry
                    )
                ))
            }
            if becomesTemporarilyUnavailable {
                continuation.yield(.temporarilyUnavailable)
            }
        }
    }

    func stop() {}
}
#endif
