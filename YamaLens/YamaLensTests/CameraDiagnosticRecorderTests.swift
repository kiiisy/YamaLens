import Foundation
import Testing
@testable import YamaLens

@MainActor
struct CameraDiagnosticRecorderTests {
    @Test("明示開始前の観測は保存されない")
    func doesNotPersistBeforeExplicitStart() async throws {
        let repository = DiagnosticLogRepositorySpy()
        let clock = DiagnosticTestClock(date: .diagnosticReference)
        let recorder = makeRecorder(repository: repository, clock: clock)

        recorder.observe(
            location: .diagnosticLocation(at: clock.date),
            locationQuality: .good,
            camera: .diagnosticCamera(at: clock.date),
            labels: [],
            candidates: [],
            quality: .good,
            manualHeadingCorrectionDegrees: 0
        )

        #expect(recorder.sampleCount == 0)
        #expect(try await repository.fetchLogs().isEmpty)
    }

    @Test("開始後に直前バッファと問題マーカーを保存する")
    func savesBufferedSamplesAndIssueMarker() async throws {
        let repository = DiagnosticLogRepositorySpy()
        let clock = DiagnosticTestClock(date: .diagnosticReference)
        let recorder = makeRecorder(repository: repository, clock: clock)
        recorder.observe(
            location: .diagnosticLocation(at: clock.date),
            locationQuality: .good,
            camera: .diagnosticCamera(at: clock.date),
            labels: [],
            candidates: [],
            quality: .good,
            manualHeadingCorrectionDegrees: 0
        )

        recorder.startRecording()
        recorder.markIssue(.jitter)
        recorder.setConfirmedMountainID("tonodake")
        clock.date = clock.date.addingTimeInterval(1)
        recorder.observe(
            location: .diagnosticLocation(at: clock.date),
            locationQuality: .reduced,
            camera: .diagnosticCamera(at: clock.date),
            labels: [],
            candidates: [],
            quality: .reduced,
            manualHeadingCorrectionDegrees: 2
        )
        await recorder.saveRecording()

        let logs = try await repository.fetchLogs()
        let log = try #require(logs.first)
        #expect(log.samples.count == 2)
        #expect(log.samples.first?.elapsedSeconds == 0)
        #expect(log.samples.last?.manualHeadingCorrectionDegrees == 2)
        #expect(log.events.map(\.kind) == [.jitter])
        #expect(log.confirmedMountainID == "tonodake")
        #expect(!recorder.isRecording)
    }

    @Test("破棄した記録は保存されない")
    func discardsUnsavedSession() async throws {
        let repository = DiagnosticLogRepositorySpy()
        let clock = DiagnosticTestClock(date: .diagnosticReference)
        let recorder = makeRecorder(repository: repository, clock: clock)
        recorder.startRecording()
        recorder.observe(
            location: .diagnosticLocation(at: clock.date),
            locationQuality: .good,
            camera: .diagnosticCamera(at: clock.date),
            labels: [],
            candidates: [],
            quality: .good,
            manualHeadingCorrectionDegrees: 0
        )

        recorder.discardRecording()

        #expect(!recorder.isRecording)
        #expect(try await repository.fetchLogs().isEmpty)
    }

    @Test("候補ごとの地形未確認理由を診断ログへ保存する")
    func savesTerrainVisibilityReason() async throws {
        let repository = DiagnosticLogRepositorySpy()
        let clock = DiagnosticTestClock(date: .diagnosticReference)
        let recorder = makeRecorder(repository: repository, clock: clock)
        let candidate = CameraMountainCandidate(
            mountain: Mountain(
                id: "tonodake",
                name: "塔ノ岳",
                aliases: [],
                regionName: "丹沢",
                prefectureName: "神奈川県",
                elevationMeters: 1_491,
                coordinate: GeoCoordinate(latitude: 35.454, longitude: 139.163)
            ),
            proximity: MountainProximity(
                distance: MountainDistance(meters: 1_000),
                bearing: TrueBearing(degrees: 0),
                direction: .north
            ),
            screenPoint: ViewportPoint(x: 100, y: 200),
            elevationAngleDegrees: 5,
            unpenalizedScore: 0.8,
            score: 0.8,
            strength: .strong,
            terrainVisibility: .unavailable
        )
        recorder.startRecording()
        recorder.observe(
            location: .diagnosticLocation(at: clock.date),
            locationQuality: .good,
            camera: .diagnosticCamera(at: clock.date),
            labels: [candidate],
            candidates: [candidate],
            quality: .good,
            manualHeadingCorrectionDegrees: 0
        )

        await recorder.saveRecording()

        let log = try #require(try await repository.fetchLogs().first)
        #expect(log.samples.first?.candidates.first?.terrainVisibility == .unavailable)
    }

    @Test("旧schemaの候補ログは地形項目なしでも読み込める")
    func decodesCandidateWithoutTerrainField() throws {
        let data = try #require(
            """
            {"mountainID":"tonodake","screenPoint":{"x":100,"y":200},"score":0.8,"isLabelVisible":true}
            """.data(using: .utf8)
        )

        let candidate = try JSONDecoder().decode(CameraDiagnosticCandidate.self, from: data)

        #expect(candidate.terrainVisibility == nil)
    }

    private func makeRecorder(
        repository: DiagnosticLogRepositorySpy,
        clock: DiagnosticTestClock
    ) -> CameraDiagnosticRecorder {
        CameraDiagnosticRecorder(
            repository: repository,
            device: CameraDiagnosticDevice(
                appVersion: "test",
                operatingSystemVersion: "26.5",
                deviceModel: "iPhone"
            ),
            now: { clock.date },
            makeID: { .diagnosticID(1) }
        )
    }
}

private actor DiagnosticLogRepositorySpy: CameraDiagnosticLogRepository {
    private var logs: [CameraDiagnosticLog] = []

    func fetchLogs() async throws -> [CameraDiagnosticLog] { logs }

    func save(_ log: CameraDiagnosticLog) async throws {
        logs.removeAll { $0.id == log.id }
        logs.append(log)
    }

    func setRetained(_ isRetained: Bool, for id: UUID) async throws {
        guard let index = logs.firstIndex(where: { $0.id == id }) else {
            throw CameraDiagnosticLogStoreError.logNotFound
        }
        logs[index] = logs[index].settingRetained(isRetained)
    }

    func delete(id: UUID) async throws {
        logs.removeAll { $0.id == id }
    }

    func deleteAll() async throws {
        logs = []
    }
}

@MainActor
private final class DiagnosticTestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
