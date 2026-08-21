import Foundation
@testable import YamaLens

extension Date {
    static let diagnosticReference = Date(timeIntervalSince1970: 1_800_000_000)
}

extension UUID {
    static func diagnosticID(_ value: UInt8) -> UUID {
        UUID(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    }
}

extension LocationObservation {
    static func diagnosticLocation(at date: Date) -> LocationObservation {
        LocationObservation(
            coordinate: GeoCoordinate(latitude: 35.4548, longitude: 139.1636),
            altitudeMeters: 1_491,
            horizontalAccuracyMeters: 8,
            verticalAccuracyMeters: 10,
            observedAt: date
        )
    }
}

extension CameraPoseObservation {
    static func diagnosticCamera(at date: Date) -> CameraPoseObservation {
        CameraPoseObservation(
            trueBearingDegrees: 34,
            pitchDegrees: 2,
            headingAccuracyDegrees: 5,
            observedAt: date,
            trackingQuality: .normal,
            projectionGeometry: CameraProjectionGeometry(
                cameraRightInWorld: SpatialVector(x: 1, y: 0, z: 0),
                cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
                cameraBackInWorld: SpatialVector(x: 0, y: 0, z: 1),
                focalLengthXPixels: 300,
                focalLengthYPixels: 300,
                principalPointXPixels: 200,
                principalPointYPixels: 400,
                imageSizePixels: ViewportSize(width: 400, height: 800),
                normalizedImageToViewport: NormalizedImageTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: 1,
                    translationX: 0,
                    translationY: 0
                ),
                viewportSizePoints: ViewportSize(width: 400, height: 800),
                horizontalFieldOfViewDegrees: 70,
                verticalFieldOfViewDegrees: 100
            )
        )
    }
}

extension CameraDiagnosticLog {
    static func diagnosticLog(
        id: UUID,
        startedAt: Date,
        isRetained: Bool = false
    ) -> CameraDiagnosticLog {
        CameraDiagnosticLog(
            schemaVersion: CameraDiagnosticLog.currentSchemaVersion,
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1),
            isRetained: isRetained,
            device: CameraDiagnosticDevice(
                appVersion: "test",
                operatingSystemVersion: "26.5",
                deviceModel: "iPhone"
            ),
            samples: [
                CameraDiagnosticSample(
                    recordedAt: startedAt,
                    elapsedSeconds: 0,
                    location: .diagnosticLocation(at: startedAt),
                    locationQuality: .good,
                    camera: .diagnosticCamera(at: startedAt),
                    estimateQuality: .good,
                    manualHeadingCorrectionDegrees: 0,
                    candidates: []
                ),
            ],
            events: [],
            confirmedMountainID: nil
        )
    }
}
