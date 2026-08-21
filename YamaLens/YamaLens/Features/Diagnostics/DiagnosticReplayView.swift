import SwiftUI

struct DiagnosticReplayView: View {
    let log: CameraDiagnosticLog
    let mountains: [Mountain]
    let projector: MountainCameraProjector
    @State private var sampleIndex = 0

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
                HStack {
                    Button {
                        sampleIndex = max(0, sampleIndex - 1)
                    } label: {
                        Label("前", systemImage: "backward.frame")
                    }
                    .disabled(sampleIndex == 0)
                    Spacer()
                    Text("\(sampleIndex + 1) / \(log.samples.count)")
                        .monospacedDigit()
                    Spacer()
                    Button {
                        sampleIndex = min(log.samples.count - 1, sampleIndex + 1)
                    } label: {
                        Label("次", systemImage: "forward.frame")
                    }
                    .disabled(sampleIndex >= log.samples.count - 1)
                }
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
                if let confirmedMountainName {
                    LabeledContent("目視で確認", value: confirmedMountainName)
                }
                if log.events.isEmpty {
                    Text("問題マーカーなし")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(log.events) { event in
                        Label(event.kind.title, systemImage: "exclamationmark.bubble")
                    }
                }
            }
        }
        .navigationTitle("ログをリプレイ")
        .navigationBarTitleDisplayMode(.inline)
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
        log.samples[min(max(sampleIndex, 0), log.samples.count - 1)]
    }

    private var recalculated: CameraCandidateProjection {
        let retainedIDs = sampleIndex > 0
            ? log.samples[sampleIndex - 1].candidates.map(\.mountainID)
            : []
        return projector.projectCandidates(
            location: currentSample.location,
            camera: currentSample.camera,
            mountains: mountains,
            retainedSheetMountainIDs: retainedIDs,
            manualHeadingCorrectionDegrees: currentSample.manualHeadingCorrectionDegrees,
            now: currentSample.recordedAt
        )
    }

    private var recordedLabels: [CameraDiagnosticCandidate] {
        currentSample.candidates.filter(\.isLabelVisible)
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
