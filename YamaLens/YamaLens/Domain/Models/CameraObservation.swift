import Foundation

nonisolated enum CameraTrackingQuality: Codable, Equatable, Sendable {
    case normal
    case limited
    case unavailable
}

nonisolated struct CameraPoseObservation: Codable, Equatable, Sendable {
    let trueBearingDegrees: Double
    let pitchDegrees: Double
    let headingAccuracyDegrees: Double
    let observedAt: Date
    let trackingQuality: CameraTrackingQuality
    let projectionGeometry: CameraProjectionGeometry
}

nonisolated enum CameraSessionFailure: Error, Equatable, Sendable {
    case denied
    case restricted
    case unsupported
    case unavailable
}
