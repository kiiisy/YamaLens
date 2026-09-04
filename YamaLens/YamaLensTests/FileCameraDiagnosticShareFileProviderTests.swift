import Foundation
import Testing
@testable import YamaLens

struct FileCameraDiagnosticShareFileProviderTests {
    @Test("匿名化サマリーは位置と記録時刻を含めない")
    func createsAnonymizedSummary() async throws {
        let directory = testDirectory(named: "summary")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let provider = FileCameraDiagnosticShareFileProvider(directoryURL: directory)
        let log = CameraDiagnosticLog.diagnosticLog(
            id: .diagnosticID(1),
            startedAt: .diagnosticReference
        )

        let shareFile = try await provider.prepareShareFile(
            for: log,
            format: .anonymizedSummary
        )
        let data = try Data(contentsOf: shareFile.url)
        let summary = try JSONDecoder().decode(CameraDiagnosticAnonymizedSummary.self, from: data)

        #expect(summary.sampleCount == log.samples.count)
        #expect(summary.durationSeconds == log.endedAt.timeIntervalSince(log.startedAt))
        #expect(summary.candidateMountainIDs.isEmpty)
        #expect(!String(decoding: data, as: UTF8.self).contains("recordedAt"))
        #expect(!String(decoding: data, as: UTF8.self).contains("latitude"))
    }

    @Test("リプレイ用ログは元の正確な観測を保持する")
    func createsReplayLogWithExactLocation() async throws {
        let directory = testDirectory(named: "replay")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let provider = FileCameraDiagnosticShareFileProvider(directoryURL: directory)
        let log = CameraDiagnosticLog.diagnosticLog(
            id: .diagnosticID(2),
            startedAt: .diagnosticReference
        )

        let shareFile = try await provider.prepareShareFile(
            for: log,
            format: .replayLogWithExactLocation
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let replayLog = try decoder.decode(CameraDiagnosticLog.self, from: Data(contentsOf: shareFile.url))

        #expect(replayLog == log)
    }

    @Test("添付映像の端末内URLを返す")
    func returnsAttachedVideoURL() async throws {
        let shareDirectory = testDirectory(named: "video-url-share")
        let diagnosticDirectory = testDirectory(named: "video-url-diagnostic")
        try resetDirectory(shareDirectory)
        try resetDirectory(diagnosticDirectory)
        defer {
            removeTestDirectory(shareDirectory)
            removeTestDirectory(diagnosticDirectory)
        }
        try FileManager.default.createDirectory(
            at: diagnosticDirectory,
            withIntermediateDirectories: true
        )
        let id = UUID.diagnosticID(9)
        let fileName = id.uuidString.lowercased() + ".mov"
        let videoURL = diagnosticDirectory.appending(path: fileName)
        try Data([0x00]).write(to: videoURL)
        let log = CameraDiagnosticLog.diagnosticLog(
            id: id,
            startedAt: .diagnosticReference,
            videoAttachment: CameraDiagnosticVideoAttachment(
                fileName: fileName,
                durationSeconds: 1
            )
        )
        let provider = FileCameraDiagnosticShareFileProvider(
            directoryURL: shareDirectory,
            diagnosticDirectoryURL: diagnosticDirectory
        )

        let actualURL = await provider.videoURL(for: log)

        #expect(actualURL == videoURL)
    }

    @Test("共有終了後に一時ファイルを削除する")
    func removesShareFile() async throws {
        let directory = testDirectory(named: "remove")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let provider = FileCameraDiagnosticShareFileProvider(directoryURL: directory)
        let shareFile = try await provider.prepareShareFile(
            for: .diagnosticLog(
                id: .diagnosticID(3),
                startedAt: .diagnosticReference
            ),
            format: .anonymizedSummary
        )

        await provider.removeShareFile(shareFile)

        #expect(!FileManager.default.fileExists(atPath: shareFile.url.path))
    }

    @Test("起動時の整理で期限切れの共有一時ファイルを削除する")
    func removesExpiredShareFiles() async throws {
        let directory = testDirectory(named: "expired")
        try resetDirectory(directory)
        defer { removeTestDirectory(directory) }
        let provider = FileCameraDiagnosticShareFileProvider(
            directoryURL: directory,
            maximumAge: 0
        )
        let shareFile = try await provider.prepareShareFile(
            for: .diagnosticLog(
                id: .diagnosticID(4),
                startedAt: .diagnosticReference
            ),
            format: .anonymizedSummary
        )

        await provider.removeExpiredShareFiles()

        #expect(!FileManager.default.fileExists(atPath: shareFile.url.path))
    }

    private func testDirectory(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "YamaLensDiagnosticShareTests-\(name)", directoryHint: .isDirectory)
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
            Issue.record("テスト用共有ファイルを削除できませんでした: \(error)")
        }
    }
}
