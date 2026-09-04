import Foundation

nonisolated enum CameraDiagnosticShareFormat: Equatable, Sendable {
    case anonymizedSummary
    case replayLogWithExactLocation

    var fileName: String {
        switch self {
        case .anonymizedSummary:
            return "YamaLens-diagnostic-summary.json"
        case .replayLogWithExactLocation:
            return "YamaLens-diagnostic-replay.json"
        }
    }
}

nonisolated struct CameraDiagnosticShareFile: Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let additionalURLs: [URL]
    let format: CameraDiagnosticShareFormat

    init(
        url: URL,
        additionalURLs: [URL] = [],
        format: CameraDiagnosticShareFormat
    ) {
        id = UUID()
        self.url = url
        self.additionalURLs = additionalURLs
        self.format = format
    }

    var allURLs: [URL] { [url] + additionalURLs }
}

nonisolated struct CameraDiagnosticAnonymizedSummary: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sampleCount: Int
    let durationSeconds: TimeInterval
    let device: CameraDiagnosticDevice
    let estimateQualityCounts: [String: Int]
    let horizontalAccuracyRangeMeters: CameraDiagnosticValueRange?
    let headingAccuracyRangeDegrees: CameraDiagnosticValueRange?
    let manualHeadingCorrectionRangeDegrees: CameraDiagnosticValueRange?
    let candidateMountainIDs: [String]
    let eventKinds: [String]

    init(log: CameraDiagnosticLog) {
        schemaVersion = 1
        sampleCount = log.samples.count
        durationSeconds = max(0, log.endedAt.timeIntervalSince(log.startedAt))
        device = log.device
        estimateQualityCounts = Dictionary(
            grouping: log.samples,
            by: { $0.estimateQuality.rawValue }
        ).mapValues(\.count)
        horizontalAccuracyRangeMeters = Self.range(
            log.samples.map(\.location.horizontalAccuracyMeters)
        )
        headingAccuracyRangeDegrees = Self.range(
            log.samples.map(\.camera.headingAccuracyDegrees)
        )
        manualHeadingCorrectionRangeDegrees = Self.range(
            log.samples.map(\.manualHeadingCorrectionDegrees)
        )
        candidateMountainIDs = Array(
            Set(log.samples.flatMap { $0.candidates.map(\.mountainID) })
        ).sorted()
        eventKinds = Array(Set(log.events.map { $0.kind.rawValue })).sorted()
    }

    private static func range(_ values: [Double]) -> CameraDiagnosticValueRange? {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return nil
        }
        return CameraDiagnosticValueRange(minimum: minimum, maximum: maximum)
    }
}

nonisolated struct CameraDiagnosticValueRange: Codable, Equatable, Sendable {
    let minimum: Double
    let maximum: Double
}
