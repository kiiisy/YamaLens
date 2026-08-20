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
        case .active(let observation, let candidates, let quality):
            activeContent(observation: observation, candidates: candidates, quality: quality)
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
        candidates: [HeadingCandidate],
        quality: CameraEstimateQuality
    ) -> some View {
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
            }
            candidateTray(candidates)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier("camera-active-view")
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

    private func candidateTray(_ candidates: [HeadingCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("方位順の候補")
                    .font(.headline)
                Spacer()
                Text("最大10件")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
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
                                model.stop()
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
                .scrollIndicators(.hidden)
            }
            searchButton
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var searchButton: some View {
        Button("検索から山を選ぶ") { selectedTab = .home }
            .buttonStyle(.bordered)
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
