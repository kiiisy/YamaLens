import Foundation

@MainActor
protocol CameraObservationProvider: AnyObject {
    func start() async -> Result<Void, CameraSessionFailure>
    func observations() -> AsyncStream<CameraPoseObservation>
    func stop()
}
