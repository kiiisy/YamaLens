import Foundation

nonisolated enum CameraDiagnosticVideoRecordingState: Equatable, Sendable {
    case notRequested
    case preparing
    case recording
    case finishing
    case failed
}

/// Debug診断にだけ、利用者が明示して選んだ短い映像を添付するための境界。
@MainActor
protocol CameraDiagnosticVideoRecording: AnyObject {
    var recordingState: CameraDiagnosticVideoRecordingState { get }
    func startRecording(for diagnosticLogID: UUID)
    func stopRecording() async -> CameraDiagnosticVideoAttachment?
    func discardRecording()
}
