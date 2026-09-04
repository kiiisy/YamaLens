@preconcurrency import ARKit
import AVFoundation
import Foundation
import OSLog

@MainActor
final class ARCameraDiagnosticVideoRecorder: CameraDiagnosticVideoRecording {
    private enum State {
        case idle
        case pending(UUID)
        case recording(Recording)
        case finishing(Recording)
    }

    private struct Recording {
        let diagnosticLogID: UUID
        let fileURL: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let startedAt: TimeInterval
        var lastFrameAt: TimeInterval
    }

    private let directoryURL: URL?
    private let policy: CameraDiagnosticPolicy
    private var state: State = .idle
    private var didFailToStart = false

    var recordingState: CameraDiagnosticVideoRecordingState {
        if didFailToStart {
            return .failed
        }
        switch state {
        case .idle:
            return .notRequested
        case .pending:
            return .preparing
        case .recording:
            return .recording
        case .finishing:
            return .finishing
        }
    }

    init(
        directoryURL: URL? = nil,
        policy: CameraDiagnosticPolicy = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appending(path: "Diagnostics", directoryHint: .isDirectory)
        }
        self.policy = policy
    }

    func startRecording(for diagnosticLogID: UUID) {
        discardRecording()
        didFailToStart = false
        guard let directoryURL else {
            didFailToStart = true
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var protectedURL = directoryURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
        } catch {
            didFailToStart = true
            return
        }
        state = .pending(diagnosticLogID)
    }

    func append(frame: ARFrame) {
        switch state {
        case .pending(let diagnosticLogID):
            beginRecording(for: diagnosticLogID, frame: frame)
            return
        case .recording(let recording):
            appendFrame(frame, to: recording)
        case .idle, .finishing:
            return
        }
    }

    private func appendFrame(_ frame: ARFrame, to recording: Recording) {
        let elapsed = frame.timestamp - recording.startedAt
        guard elapsed >= 0 else { return }
        if elapsed >= policy.maximumVideoDurationSeconds {
            finish(recording)
            return
        }
        guard recording.input.isReadyForMoreMediaData else { return }
        let presentationTime = CMTime(seconds: elapsed, preferredTimescale: 600)
        guard recording.adaptor.append(
            frame.capturedImage,
            withPresentationTime: presentationTime
        ) else {
            failRecording(recording)
            return
        }
        var updatedRecording = recording
        updatedRecording.lastFrameAt = frame.timestamp
        state = .recording(updatedRecording)
    }

    func stopRecording() async -> CameraDiagnosticVideoAttachment? {
        switch state {
        case .idle:
            return nil
        case .pending:
            state = .idle
            return nil
        case .recording(let recording), .finishing(let recording):
            return await finishAndMakeAttachment(recording)
        }
    }

    func discardRecording() {
        let recording: Recording?
        switch state {
        case .idle:
            recording = nil
        case .pending:
            recording = nil
        case .recording(let active), .finishing(let active):
            recording = active
        }
        state = .idle
        recording?.input.markAsFinished()
        recording?.writer.cancelWriting()
        if let url = recording?.fileURL,
           FileManager.default.fileExists(atPath: url.path) {
            removeFile(at: url)
        }
    }

    private func beginRecording(for diagnosticLogID: UUID, frame: ARFrame) {
        guard let directoryURL else { return }
        let pixelBuffer = frame.capturedImage
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard width > 0, height > 0 else { return }
        let fileURL = directoryURL.appending(path: diagnosticLogID.uuidString.lowercased() + ".mov")
        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 4_000_000,
                    ],
                ]
            )
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                ]
            )
            guard writer.canAdd(input) else { return }
            writer.add(input)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            let recording = Recording(
                diagnosticLogID: diagnosticLogID,
                fileURL: fileURL,
                writer: writer,
                input: input,
                adaptor: adaptor,
                startedAt: frame.timestamp,
                lastFrameAt: frame.timestamp
            )
            state = .recording(recording)
            append(frame: frame)
        } catch {
            state = .idle
            didFailToStart = true
        }
    }

    private func finish(_ recording: Recording) {
        guard case .recording = state else { return }
        state = .finishing(recording)
        recording.input.markAsFinished()
    }

    private func finishAndMakeAttachment(
        _ recording: Recording
    ) async -> CameraDiagnosticVideoAttachment? {
        state = .finishing(recording)
        recording.input.markAsFinished()
        await recording.writer.finishWriting()
        defer { state = .idle }
        guard recording.writer.status == .completed else {
            didFailToStart = true
            if FileManager.default.fileExists(atPath: recording.fileURL.path) {
                removeFile(at: recording.fileURL)
            }
            return nil
        }
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: recording.fileURL.path
            )
            return CameraDiagnosticVideoAttachment(
                fileName: recording.fileURL.lastPathComponent,
                durationSeconds: max(0, recording.lastFrameAt - recording.startedAt)
            )
        } catch {
            didFailToStart = true
            removeFile(at: recording.fileURL)
            return nil
        }
    }

    func receive(frame: ARFrame) {
        switch state {
        case .idle:
            return
        case .pending, .recording:
            append(frame: frame)
        case .finishing:
            return
        }
    }

    private func removeFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger(subsystem: "com.kiiisy.YamaLens", category: "Diagnostics")
                .error("A diagnostic video file could not be removed")
        }
    }

    private func failRecording(_ recording: Recording) {
        state = .idle
        didFailToStart = true
        recording.input.markAsFinished()
        recording.writer.cancelWriting()
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            removeFile(at: recording.fileURL)
        }
    }

}
