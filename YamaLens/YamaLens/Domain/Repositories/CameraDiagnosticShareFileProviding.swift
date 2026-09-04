import Foundation

nonisolated protocol CameraDiagnosticShareFileProviding: Sendable {
    func prepareShareFile(
        for log: CameraDiagnosticLog,
        format: CameraDiagnosticShareFormat
    ) async throws -> CameraDiagnosticShareFile

    func removeShareFile(_ shareFile: CameraDiagnosticShareFile) async

    func removeExpiredShareFiles() async

    func videoURL(for log: CameraDiagnosticLog) async -> URL?
}
