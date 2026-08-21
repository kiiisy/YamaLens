import Foundation

nonisolated enum CameraObservationUpdate: Equatable, Sendable {
    case pose(CameraPoseObservation)
    case temporarilyUnavailable
}

@MainActor
protocol CameraObservationProvider: AnyObject {
    func start() async -> Result<Void, CameraSessionFailure>
    func observations() -> AsyncStream<CameraObservationUpdate>
    func stop()
}
