import SwiftUI

struct DiagnosticReplayView: View {
    let log: CameraDiagnosticLog
    let mountains: [Mountain]
    let projector: MountainCameraProjector
    private let frames: [CameraDiagnosticReplayFrame]
    @State private var sampleIndex = 0
    @State private var isPlaying = false

    init(
        log: CameraDiagnosticLog,
        mountains: [Mountain],
        projector: MountainCameraProjector
    ) {
        self.log = log
        self.mountains = mountains
        self.projector = projector
        var calculator = CameraDiagnosticReplayCalculator(projector: projector)
        frames = calculator.replay(samples: log.samples, mountains: mountains)
    }

    var body: some View {
        Form {
            Section {
                replayViewport
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("候補の再計算")
            } footer: {
                Text("緑は現在の候補計算、橙は記録時のラベル位置です。カメラ映像は保存されていません。")
            }

            Section("タイムライン") {
                Slider(
                    value: sampleIndexBinding,
                    in: 0...Double(max(log.samples.count - 1, 0)),
                    step: 1
                )
                .disabled(log.samples.count <= 1)
                .accessibilityLabel("診断ログの再生位置")
                .onChange(of: sampleIndex) { _, _ in
                    if sampleIndex >= frames.count - 1 {
                        isPlaying = false
                    }
                }
                HStack {
                    Button {
                        sampleIndex = max(0, sampleIndex - 1)
                    } label: {
                        Label("前", systemImage: "backward.frame")
                    }
                    .disabled(sampleIndex == 0)
                    Spacer()
                    Button {
                        if sampleIndex >= frames.count - 1 {
                            sampleIndex = 0
                        }
                        isPlaying.toggle()
                    } label: {
                        Label(
                            isPlaying ? "一時停止" : "再生",
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                    .accessibilityIdentifier("diagnostic-replay-playback")
                    Spacer()
                    Button {
                        sampleIndex = min(log.samples.count - 1, sampleIndex + 1)
                    } label: {
                        Label("次", systemImage: "forward.frame")
                    }
                    .disabled(sampleIndex >= log.samples.count - 1)
                }
                Text("\(sampleIndex + 1) / \(log.samples.count)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }

            Section("入力") {
                LabeledContent("経過", value: elapsedText)
                LabeledContent("緯度", value: currentSample.location.coordinate.latitude.formatted(.number.precision(.fractionLength(5))))
                LabeledContent("経度", value: currentSample.location.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))
                LabeledContent("真北方位", value: degreesText(currentSample.camera.trueBearingDegrees))
                LabeledContent("ピッチ", value: degreesText(currentSample.camera.pitchDegrees))
                LabeledContent("方位精度", value: "±\(degreesText(currentSample.camera.headingAccuracyDegrees))")
                LabeledContent("手動補正", value: degreesText(currentSample.manualHeadingCorrectionDegrees))
            }

            Section("比較") {
                LabeledContent("記録時の候補", value: "\(recordedLabelCount)件")
                LabeledContent("現在の候補", value: "\(recalculated.labels.count)件")
                LabeledContent("一致した候補", value: "\(currentFrame.differences.count)件")
                LabeledContent("平均位置差", value: differenceText(currentFrame.meanDifferencePoints))
                LabeledContent("最大位置差", value: differenceText(currentFrame.maximumDifferencePoints))
                Text("現在の計算は、保存された5Hzサンプルをログ先頭から時系列に処理し、安定化状態を復元しています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let confirmedMountainName {
                    LabeledContent("目視で確認", value: confirmedMountainName)
                }
                if log.events.isEmpty {
                    Text("問題マーカーなし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.events) { event in
                        Button {
                            sampleIndex = nearestSampleIndex(to: event.elapsedSeconds)
                            isPlaying = false
                        } label: {
                            Label(event.kind.title, systemImage: "exclamationmark.bubble")
                        }
                    }
                }
            }
        }
        .navigationTitle("ログをリプレイ")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isPlaying) {
            guard isPlaying else { return }
            await playFromCurrentPosition()
        }
    }

    private var replayViewport: some View {
        GeometryReader { proxy in
            let viewport = currentSample.camera.projectionGeometry.viewportSizePoints
            ZStack {
                LinearGradient(
                    colors: [YamaColor.deepForest, YamaColor.canvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ForEach(recordedLabels, id: \.mountainID) { candidate in
                    replayMarker(
                        title: mountainName(for: candidate.mountainID),
                        point: candidate.screenPoint,
                        viewport: viewport,
                        destination: proxy.size,
                        color: YamaColor.amber,
                        symbol: "circle"
                    )
                }
                ForEach(recalculated.labels, id: \.mountain.id) { candidate in
                    replayMarker(
                        title: candidate.mountain.name,
                        point: candidate.screenPoint,
                        viewport: viewport,
                        destination: proxy.size,
                        color: YamaColor.moss,
                        symbol: "plus"
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("記録時と現在の山候補位置の比較")
        .accessibilityValue("記録時\(recordedLabelCount)件、現在\(recalculated.labels.count)件")
    }

    private func replayMarker(
        title: String,
        point: ViewportPoint,
        viewport: ViewportSize,
        destination: CGSize,
        color: Color,
        symbol: String
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(YamaColor.surface.opacity(0.92), in: Capsule())
            .position(
                x: point.x / max(viewport.width, 1) * destination.width,
                y: point.y / max(viewport.height, 1) * destination.height
            )
    }

    private var currentSample: CameraDiagnosticSample {
        currentFrame.sample
    }

    private var recalculated: CameraCandidateProjection {
        currentFrame.recalculated
    }

    private var recordedLabels: [CameraDiagnosticCandidate] {
        currentFrame.recordedLabels
    }

    private var recordedLabelCount: Int { recordedLabels.count }

    private var confirmedMountainName: String? {
        guard let id = log.confirmedMountainID else { return nil }
        return mountainName(for: id)
    }

    private var sampleIndexBinding: Binding<Double> {
        Binding(
            get: { Double(sampleIndex) },
            set: { sampleIndex = Int($0.rounded()) }
        )
    }

    private var currentFrame: CameraDiagnosticReplayFrame {
        frames[min(max(sampleIndex, 0), frames.count - 1)]
    }

    private func playFromCurrentPosition() async {
        while !Task.isCancelled, isPlaying, sampleIndex < frames.count - 1 {
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch is CancellationError {
                return
            } catch {
                isPlaying = false
                return
            }
            guard !Task.isCancelled, isPlaying else { return }
            sampleIndex += 1
        }
        isPlaying = false
    }

    private func nearestSampleIndex(to elapsedSeconds: TimeInterval) -> Int {
        frames.indices.min { lhs, rhs in
            abs(frames[lhs].sample.elapsedSeconds - elapsedSeconds)
                < abs(frames[rhs].sample.elapsedSeconds - elapsedSeconds)
        } ?? 0
    }

    private func differenceText(_ points: Double?) -> String {
        guard let points else { return "比較対象なし" }
        return points.formatted(.number.precision(.fractionLength(1))) + "pt"
    }

    private var elapsedText: String {
        Duration.seconds(currentSample.elapsedSeconds)
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    private func mountainName(for id: String) -> String {
        mountains.first { $0.id == id }?.name ?? id
    }

    private func degreesText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "°"
    }
}
