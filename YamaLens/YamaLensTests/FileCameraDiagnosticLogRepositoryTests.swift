import Foundation
import Testing
@testable import YamaLens

struct FileCameraDiagnosticLogRepositoryTests {
    @Test("保持していないログは20件を超えると古い順に削除する")
    func limitsUnretainedLogsToTwenty() async throws {
        let directory = testDirectory(named: "count-limit")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let now = Date.diagnosticReference
        let repository = FileCameraDiagnosticLogRepository(
            directoryURL: directory,
            now: { now }
        )

        for index in 0...20 {
            try await repository.save(
                .diagnosticLog(
                    id: .diagnosticID(UInt8(index)),
                    startedAt: now.addingTimeInterval(TimeInterval(index - 20) * 60)
                )
            )
        }

        let logs = try await repository.fetchLogs()
        #expect(logs.count == 20)
        #expect(!logs.contains { $0.id == .diagnosticID(0) })
    }

    @Test("30日に達した未保持ログを削除し保持中ログは残す")
    func expiresOnlyUnretainedLogsAtThirtyDays() async throws {
        let directory = testDirectory(named: "age-limit")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let now = Date.diagnosticReference
        let repository = FileCameraDiagnosticLogRepository(
            directoryURL: directory,
            now: { now }
        )
        let startedAt = now.addingTimeInterval(-30 * 24 * 60 * 60)

        try await repository.save(
            .diagnosticLog(id: .diagnosticID(1), startedAt: startedAt)
        )
        try await repository.save(
            .diagnosticLog(
                id: .diagnosticID(2),
                startedAt: startedAt,
                isRetained: true
            )
        )

        let logs = try await repository.fetchLogs()
        #expect(logs.map(\.id) == [.diagnosticID(2)])
    }

    @Test("保持指定と個別削除を保存後の再読込へ反映する")
    func persistsRetentionAndDeletion() async throws {
        let directory = testDirectory(named: "retention-delete")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let now = Date.diagnosticReference
        let id = UUID.diagnosticID(3)
        let repository = FileCameraDiagnosticLogRepository(
            directoryURL: directory,
            now: { now }
        )
        try await repository.save(.diagnosticLog(id: id, startedAt: now))

        try await repository.setRetained(true, for: id)
        let retained = try #require(try await repository.fetchLogs().first)
        #expect(retained.isRetained)

        try await repository.delete(id: id)
        #expect(try await repository.fetchLogs().isEmpty)
    }

    @Test("全削除は保持中ログも削除する")
    func deletesAllLogsIncludingRetainedLogs() async throws {
        let directory = testDirectory(named: "delete-all")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let now = Date.diagnosticReference
        let repository = FileCameraDiagnosticLogRepository(
            directoryURL: directory,
            now: { now }
        )
        try await repository.save(
            .diagnosticLog(id: .diagnosticID(4), startedAt: now)
        )
        try await repository.save(
            .diagnosticLog(
                id: .diagnosticID(5),
                startedAt: now,
                isRetained: true
            )
        )

        try await repository.deleteAll()

        #expect(try await repository.fetchLogs().isEmpty)
    }

    @Test("診断ログ保存先へ完全保護とバックアップ除外を設定する")
    func appliesFileProtectionAndBackupExclusion() async throws {
        let directory = testDirectory(named: "file-protection")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let now = Date.diagnosticReference
        let id = UUID.diagnosticID(6)
        let repository = FileCameraDiagnosticLogRepository(
            directoryURL: directory,
            now: { now }
        )
        try await repository.save(.diagnosticLog(id: id, startedAt: now))

        let directoryValues = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        let fileURL = directory.appending(path: id.uuidString.lowercased() + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(directoryValues.isExcludedFromBackup == true)
        let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        // Simulatorの一時ファイルシステムはFile Protection属性を返さない場合がある。
        if let protection {
            #expect(protection == .complete)
        }
#else
        #expect(protection == .complete)
#endif
    }

    private func testDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "YamaLensDiagnosticTests-\(name)", directoryHint: .isDirectory)
    }

    private func resetDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func removeTestDirectory(_ directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("テスト用診断ログを削除できませんでした: \(error)")
        }
    }
}
