import Foundation
import Observation

enum DiagnosticLogsLoadState: Equatable {
    case idle
    case loading
    case loaded([CameraDiagnosticLog])
    case failed
}

@MainActor
@Observable
final class DiagnosticLogsScreenModel {
    private let repository: any CameraDiagnosticLogRepository

    private(set) var state: DiagnosticLogsLoadState = .idle
    private(set) var operationErrorMessage: String?

    init(repository: any CameraDiagnosticLogRepository) {
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.fetchLogs())
            operationErrorMessage = nil
        } catch {
            state = .failed
        }
    }

    func setRetained(_ isRetained: Bool, for log: CameraDiagnosticLog) async {
        do {
            try await repository.setRetained(isRetained, for: log.id)
            state = .loaded(try await repository.fetchLogs())
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = "保持設定を変更できませんでした。"
        }
    }

    func delete(_ log: CameraDiagnosticLog) async {
        do {
            try await repository.delete(id: log.id)
            state = .loaded(try await repository.fetchLogs())
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = "診断ログを削除できませんでした。"
        }
    }

    func deleteAll() async {
        do {
            try await repository.deleteAll()
            state = .loaded([])
            operationErrorMessage = nil
        } catch {
            operationErrorMessage = "診断ログを削除できませんでした。"
        }
    }

    func clearOperationError() {
        operationErrorMessage = nil
    }
}
