import Foundation

nonisolated protocol CameraDiagnosticLogRepository: Sendable {
    func fetchLogs() async throws -> [CameraDiagnosticLog]
    func save(_ log: CameraDiagnosticLog) async throws
    func setRetained(_ isRetained: Bool, for id: UUID) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

nonisolated enum CameraDiagnosticLogStoreError: Error, Equatable, Sendable {
    case storageUnavailable
    case unsupportedSchema
    case invalidLog
    case logNotFound
}
