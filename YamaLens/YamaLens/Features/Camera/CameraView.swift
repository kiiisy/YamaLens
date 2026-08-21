import SwiftUI
import UIKit

struct CameraView: View {
    @Binding var selectedTab: YamaTab
    let model: CameraScreenModel
    let locationModel: LocationSessionModel
    let preview: AnyView
    let onSelectMountain: (Mountain) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var adjustmentStartDegrees: Double?

    var body: some View {
        NavigationStack {
            ZStack {
                background
                content
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: locationModel.state, initial: true) { _, newState in
            model.updateLocationState(newState)
        }
        .task(id: model.locationRefreshRequestID) {
            guard model.locationRefreshRequestID > 0 else { return }
            await locationModel.requestLocation()
        }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                model.stop()
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch model.state {
        case .waitingForSensors, .active:
            preview
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.08))
        case .idle, .starting, .cameraDenied, .cameraRestricted, .unsupported, .unavailable:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.20, blue: 0.21), YamaColor.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            permissionContent
        case .starting:
            progressContent("カメラを開始しています")
        case .waitingForSensors:
            sensorWaitingContent
        case .active(let observation, let labels, let candidates, let quality):
            activeContent(
                observation: observation,
                labels: labels,
                candidates: candidates,
                quality: quality
            )
        case .cameraDenied:
            recoveryContent(
                title: "カメラが許可されていません",
                message: "設定でカメラを許可すると、映像上で山候補を確認できます。",
                actionTitle: "設定を開く",
                action: openSettings
            )
        case .cameraRestricted:
            recoveryContent(
                title: "カメラを利用できません",
                message: "端末の制限により利用できません。検索から山を選べます。",
                actionTitle: "検索から選ぶ",
                action: { selectedTab = .home }
            )
        case .unsupported:
            recoveryContent(
                title: "この端末ではARを利用できません",
                message: "山一覧と検索、山詳細は引き続き利用できます。",
                actionTitle: "検索から選ぶ",
                action: { selectedTab = .home }
            )
        case .unavailable:
            recoveryContent(
                title: "カメラを開始できませんでした",
                message: "一度カメラ画面を開き直すか、検索から山を選んでください。",
                actionTitle: "もう一度試す",
                action: startCamera
            )
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 0) {
            statusBar(left: "丹沢・技術試作", right: "候補待機中", symbol: "scope")
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Label("カメラで山候補を探す", systemImage: "camera.viewfinder")
                    .font(.title3.bold())
                    .foregroundStyle(YamaColor.primaryText)
                Text("カメラ・現在地・真北方位・端末姿勢から、向いている方向に近い山を候補として表示します。")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
                Text("映像と正確な位置は保存・送信しません。候補は実際に見える山を確定するものではありません。")
                    .font(.footnote)
                    .foregroundStyle(YamaColor.secondaryText)
                Button("カメラを使う", action: startCamera)
                    .buttonStyle(.borderedProminent)
                    .tint(YamaColor.forest)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("camera-start-button")
                searchButton
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func activeContent(
        observation: CameraPoseObservation,
        labels: [CameraMountainCandidate],
        candidates: [CameraMountainCandidate],
        quality: CameraEstimateQuality
    ) -> some View {
        ZStack {
            projectedLabels(labels, observation: observation)
            if model.isManualHeadingAdjustmentActive {
                manualHeadingDragLayer(observation: observation)
            }

            VStack(spacing: 12) {
                statusBar(
                    left: "真北 \(Int(observation.trueBearingDegrees.rounded()))°",
                    right: qualityText(quality),
                    symbol: quality == .good ? "location.north.fill" : "exclamationmark.triangle"
                )
                Spacer()
                if quality == .reduced {
                    Label(
                        "位置または方位の精度を調整中です",
                        systemImage: "wave.3.right"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(.regularMaterial, in: Capsule())
                } else if quality == .unavailable {
                    headingRecoveryNotice
                }
                if model.isManualHeadingAdjustmentActive {
                    manualHeadingAdjustmentPanel
                } else {
                    candidateTray(candidates, canAdjustHeading: quality != .unavailable)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 84)
        }
    }

    private var headingRecoveryNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("方位を再確認しています")
                    .font(.caption.weight(.semibold))
                Text("金属や磁石を端末から離し、端末をゆっくり上下左右に動かしてください")
                    .font(.caption2)
                    .foregroundStyle(YamaColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "方位を再確認しています。金属や磁石を端末から離し、端末をゆっくり上下左右に動かしてください"
        )
        .accessibilityIdentifier("camera-heading-recovery")
    }

    private func projectedLabels(
        _ labels: [CameraMountainCandidate],
        observation: CameraPoseObservation
    ) -> some View {
        GeometryReader { proxy in
            let sourceSize = observation.projectionGeometry.viewportSizePoints
            let candidatesByID = Dictionary(
                uniqueKeysWithValues: labels.map { ($0.mountain.id, $0) }
            )
            let placements = CameraLabelPlacementResolver(
                labelSize: cameraLabelSize
            ).resolve(
                anchors: labels.map { candidate in
                    CameraLabelAnchor(
                        id: candidate.mountain.id,
                        point: scaledPoint(
                            candidate.screenPoint,
                            from: sourceSize,
                            to: proxy.size
                        )
                    )
                },
                viewportSize: proxy.size
            )

            ZStack {
                ForEach(placements, id: \.id) { placement in
                    Path { path in
                        path.move(to: placement.anchor)
                        path.addLine(to: placement.labelCenter)
                    }
                    .stroke(
                        Color.white.opacity(0.72),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )

                    Circle()
                        .fill(YamaColor.alpineTeal)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(placement.anchor)
                }

                ForEach(placements, id: \.id) { placement in
                    if let candidate = candidatesByID[placement.id] {
                        Button {
                            model.pauseForDetail()
                            onSelectMountain(candidate.mountain)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.mountain.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text("\(candidate.mountain.elevationMeters.formatted())m・\(MountainProximityText.distance(candidate.proximity.distance))")
                                    .font(.caption2)
                                    .foregroundStyle(YamaColor.secondaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                YamaColor.surface.opacity(0.94),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(
                            width: cameraLabelSize.width,
                            height: cameraLabelSize.height
                        )
                        .position(placement.labelCenter)
                        .accessibilityLabel(
                            "候補、\(candidate.mountain.name)、標高\(candidate.mountain.elevationMeters.formatted())メートル、\(MountainProximityText.summary(candidate.proximity))"
                        )
                        .accessibilityIdentifier("camera-label-\(candidate.mountain.id)")
                    }
                }
            }
        }
    }

    private var cameraLabelSize: CGSize {
        if dynamicTypeSize.isAccessibilitySize {
            return CGSize(width: 190, height: 78)
        }
        return CGSize(width: 168, height: 54)
    }

    private var sensorWaitingContent: some View {
        VStack(spacing: 12) {
            statusBar(left: "丹沢・技術試作", right: "センサー準備中", symbol: "location.north")
            Spacer()
            switch locationModel.state {
            case .denied:
                recoveryCard(
                    title: "位置情報が許可されていません",
                    message: "設定で位置情報を許可するか、検索から山を選んでください。",
                    actionTitle: "設定を開く",
                    action: openSettings
                )
            case .restricted:
                recoveryCard(
                    title: "位置情報を利用できません",
                    message: "端末の制限中でも検索は利用できます。",
                    actionTitle: "検索から選ぶ",
                    action: { selectedTab = .home }
                )
            case .insufficientAccuracy, .unavailable:
                recoveryCard(
                    title: "現在地を確認できません",
                    message: "空が見える場所で、もう一度取得してください。",
                    actionTitle: "もう一度試す",
                    action: requestLocation
                )
            case .notRequested, .loading, .available:
                progressCard("現在地と真北方位を確認しています")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func candidateTray(
        _ candidates: [CameraMountainCandidate],
        canAdjustHeading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("この画角の候補")
                    .font(.headline)
                Spacer()
                Button {
                    adjustmentStartDegrees = nil
                    model.beginManualHeadingAdjustment()
                } label: {
                    Label(manualCorrectionButtonTitle, systemImage: "arrow.left.and.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minHeight: 44)
                .disabled(!canAdjustHeading)
                .accessibilityHint("山のラベル位置を手動で左右に合わせます")
                .accessibilityIdentifier("camera-heading-adjust-button")
            }
            if candidates.isEmpty {
                Text("この方向に表示できる候補がありません")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(candidates, id: \.mountain.id) { candidate in
                            Button {
                                model.pauseForDetail()
                                onSelectMountain(candidate.mountain)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.mountain.name)
                                        .font(.headline)
                                    Text("\(candidate.mountain.elevationMeters.formatted())m・\(MountainProximityText.summary(candidate.proximity))")
                                        .font(.caption)
                                        .foregroundStyle(YamaColor.secondaryText)
                                }
                                .frame(width: 150, alignment: .leading)
                                .padding(12)
                                .background(YamaColor.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("候補、\(candidate.mountain.name)、\(MountainProximityText.summary(candidate.proximity))")
                            .accessibilityIdentifier("camera-candidate-\(candidate.mountain.id)")
                        }
                    }
                }
                .frame(height: 72)
                .scrollIndicators(.hidden)
            }
            searchButton
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func manualHeadingDragLayer(
        observation: CameraPoseObservation
    ) -> some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .frame(
                    width: proxy.size.width,
                    height: max(proxy.size.height - 230, 1),
                    alignment: .top
                )
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let start = adjustmentStartDegrees
                                ?? model.manualHeadingCorrectionDegrees
                            adjustmentStartDegrees = start
                            let width = max(proxy.size.width, 1)
                            let degrees = value.translation.width / width
                                * observation.projectionGeometry.horizontalFieldOfViewDegrees
                            model.setManualHeadingCorrection(degrees: start + degrees)
                        }
                        .onEnded { _ in
                            adjustmentStartDegrees = nil
                        }
                )
                .accessibilityHidden(true)
        }
    }

    private var manualHeadingAdjustmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("手動調整中", systemImage: "arrow.left.and.right")
                    .font(.headline)
                Spacer()
                Text(manualCorrectionText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .accessibilityIdentifier("camera-heading-correction-value")
            }

            Text("山のラベルを左右にドラッグして、実際の山に合わせてください。")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)

            HStack(spacing: 10) {
                headingStepButton(step: -1, title: "西へ1°", symbol: "arrow.left")
                headingStepButton(step: 1, title: "東へ1°", symbol: "arrow.right")
            }

            HStack(spacing: 10) {
                Button {
                    adjustmentStartDegrees = nil
                    model.resetManualHeadingCorrection()
                } label: {
                    Text("自動に戻す")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(YamaColor.alpineTeal)
                .controlSize(.large)
                .disabled(model.manualHeadingCorrectionDegrees == 0)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("camera-heading-reset-button")

                Button {
                    adjustmentStartDegrees = nil
                    model.finishManualHeadingAdjustment()
                } label: {
                    Text("完了")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("camera-heading-adjust-done-button")
            }
            searchButton
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func headingStepButton(
        step: Int,
        title: String,
        symbol: String
    ) -> some View {
        Button {
            adjustmentStartDegrees = nil
            model.adjustManualHeadingByStep(step)
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
        .tint(YamaColor.alpineTeal)
        .controlSize(.large)
        .accessibilityLabel("方位を\(title)補正")
        .accessibilityHint("1回押すと1度、押し続けると連続して補正します")
        .accessibilityIdentifier(step < 0 ? "camera-heading-west-button" : "camera-heading-east-button")
    }

    private var manualCorrectionButtonTitle: String {
        model.manualHeadingCorrectionDegrees == 0
            ? "方位を調整"
            : "補正 \(manualCorrectionText)"
    }

    private var manualCorrectionText: String {
        let degrees = abs(model.manualHeadingCorrectionDegrees)
            .formatted(.number.precision(.fractionLength(0...1)))
        if model.manualHeadingCorrectionDegrees > 0 {
            return "東へ\(degrees)°"
        }
        if model.manualHeadingCorrectionDegrees < 0 {
            return "西へ\(degrees)°"
        }
        return "補正なし"
    }

    private var searchButton: some View {
        Button("検索から山を選ぶ") { selectedTab = .home }
            .buttonStyle(.bordered)
            .tint(YamaColor.alpineTeal)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("camera-search-button")
    }

    private func statusBar(left: String, right: String, symbol: String) -> some View {
        HStack {
            Text(left)
            Spacer()
            Label(right, systemImage: symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(YamaColor.primaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(.regularMaterial, in: Capsule())
    }

    private func progressContent(_ message: String) -> some View {
        VStack {
            Spacer()
            progressCard(message)
            Spacer()
        }
        .padding(18)
    }

    private func progressCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.headline)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func recoveryContent(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack {
            Spacer()
            recoveryCard(title: title, message: message, actionTitle: actionTitle, action: action)
            searchButton
            Spacer()
        }
        .padding(18)
    }

    private func recoveryCard(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(YamaColor.secondaryText)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func qualityText(_ quality: CameraEstimateQuality) -> String {
        switch quality {
        case .good:
            return "推定精度 良好"
        case .reduced:
            return "推定精度 低下"
        case .unavailable:
            return "推定利用困難"
        }
    }

    private func scaledPoint(
        _ point: ViewportPoint,
        from source: ViewportSize,
        to destination: CGSize
    ) -> CGPoint {
        guard source.width > 0, source.height > 0 else { return .zero }
        return CGPoint(
            x: point.x / source.width * destination.width,
            y: point.y / source.height * destination.height
        )
    }

    private func startCamera() {
        Task {
            await model.start()
            if model.state == .waitingForSensors {
                await locationModel.requestLocation()
            }
        }
    }

    private func requestLocation() {
        Task { await locationModel.requestLocation() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
