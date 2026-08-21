import Foundation

nonisolated struct CameraDiagnosticPolicy: Equatable, Sendable {
    let samplingIntervalSeconds: TimeInterval
    let inMemoryBufferSeconds: TimeInterval
    let maximumSampleCount: Int
    let maximumUnretainedLogCount: Int
    let maximumUnretainedLogAgeDays: Int
    let maximumLogByteCount: Int

    static let `default` = CameraDiagnosticPolicy(
        samplingIntervalSeconds: 0.2,
        inMemoryBufferSeconds: 10,
        maximumSampleCount: 1_500,
        maximumUnretainedLogCount: 20,
        maximumUnretainedLogAgeDays: 30,
        maximumLogByteCount: 10 * 1_024 * 1_024
    )

    var maximumRecordingDurationSeconds: TimeInterval {
        samplingIntervalSeconds * Double(maximumSampleCount)
    }

    var maximumUnretainedLogAgeSeconds: TimeInterval {
        TimeInterval(maximumUnretainedLogAgeDays) * 24 * 60 * 60
    }
}

nonisolated struct CameraDiagnosticLog: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let isRetained: Bool
    let device: CameraDiagnosticDevice
    let samples: [CameraDiagnosticSample]
    let events: [CameraDiagnosticEvent]
    let confirmedMountainID: String?

    var automaticDeletionDate: Date? {
        guard !isRetained else { return nil }
        return Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: CameraDiagnosticPolicy.default.maximumUnretainedLogAgeDays,
            to: startedAt
        )
    }

    func settingRetained(_ isRetained: Bool) -> CameraDiagnosticLog {
        CameraDiagnosticLog(
            schemaVersion: schemaVersion,
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            isRetained: isRetained,
            device: device,
            samples: samples,
            events: events,
            confirmedMountainID: confirmedMountainID
        )
    }
}

nonisolated struct CameraDiagnosticDevice: Codable, Equatable, Sendable {
    let appVersion: String
    let operatingSystemVersion: String
    let deviceModel: String
}

nonisolated struct CameraDiagnosticSample: Codable, Equatable, Sendable {
    let recordedAt: Date
    let elapsedSeconds: TimeInterval
    let location: LocationObservation
    let locationQuality: LocationObservationQuality
    let camera: CameraPoseObservation
    let estimateQuality: CameraDiagnosticEstimateQuality
    let manualHeadingCorrectionDegrees: Double
    let candidates: [CameraDiagnosticCandidate]
}

nonisolated enum CameraDiagnosticEstimateQuality: String, Codable, Equatable, Sendable {
    case good
    case reduced
    case unavailable
}

nonisolated struct CameraDiagnosticCandidate: Codable, Equatable, Sendable {
    let mountainID: String
    let screenPoint: ViewportPoint
    let score: Double
    let isLabelVisible: Bool
}

nonisolated struct CameraDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let recordedAt: Date
    let elapsedSeconds: TimeInterval
    let kind: CameraDiagnosticEventKind
}

nonisolated enum CameraDiagnosticEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case alignmentWrong
    case jitter
    case lag
    case wrongMountain

    var title: String {
        switch self {
        case .alignmentWrong:
            return "ラベルの方向が違う"
        case .jitter:
            return "静止しても揺れる"
        case .lag:
            return "追従が遅い"
        case .wrongMountain:
            return "別の山を表示した"
        }
    }
}
