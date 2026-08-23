import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showsTerrainHorizon: Bool
    let diagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let mountains: [Mountain]
    let cameraProjector: MountainCameraProjector
    let offlinePackageModel: OfflinePackageScreenModel
    @AppStorage("externalMaps.application") private var mapApplicationRawValue = ExternalMapApplication.appleMaps.rawValue
    @AppStorage("externalBrowser.application") private var browserApplicationRawValue = ExternalBrowserApplication.defaultBrowser.rawValue

    private var mapApplication: ExternalMapApplication {
        ExternalMapApplication(rawValue: mapApplicationRawValue) ?? .appleMaps
    }

    private var browserApplication: ExternalBrowserApplication {
        ExternalBrowserApplication(rawValue: browserApplicationRawValue) ?? .defaultBrowser
    }

    init(
        showsTerrainHorizon: Binding<Bool> = .constant(true),
        diagnosticLogRepository: (any CameraDiagnosticLogRepository)? = nil,
        mountains: [Mountain] = [],
        cameraProjector: MountainCameraProjector = MountainCameraProjector(),
        offlinePackageModel: OfflinePackageScreenModel
    ) {
        _showsTerrainHorizon = showsTerrainHorizon
        self.diagnosticLogRepository = diagnosticLogRepository
        self.mountains = mountains
        self.cameraProjector = cameraProjector
        self.offlinePackageModel = offlinePackageModel
    }

    var body: some View {
        NavigationStack {
            List {
                Section("カメラ表示") {
                    Toggle(isOn: $showsTerrainHorizon) {
                        SettingsLabel(title: "稜線を表示", systemImage: "waveform.path")
                    }
                    Toggle(isOn: .constant(true)) {
                        SettingsLabel(title: "登頂旗を表示", systemImage: "flag")
                    }
                    Text("登頂旗は手動で登頂済みにした山だけに表示します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("位置情報とアクセス") {
                    SettingsLink(title: "よく使う出発駅", value: "未登録", systemImage: "tram")
                    NavigationLink {
                        ExternalMapApplicationSettingsView(
                            selectedApplicationRawValue: $mapApplicationRawValue
                        )
                    } label: {
                        SettingsLink(
                            title: "地図アプリ",
                            value: mapApplication.displayName,
                            systemImage: "map"
                        )
                    }
                    NavigationLink {
                        ExternalBrowserApplicationSettingsView(
                            selectedApplicationRawValue: $browserApplicationRawValue
                        )
                    } label: {
                        SettingsLink(
                            title: "公式サイトを開くブラウザ",
                            value: browserApplication.displayName,
                            systemImage: "safari"
                        )
                    }
                }

                Section("オフライン") {
                    NavigationLink {
                        OfflineView(
                            model: offlinePackageModel,
                            coreMountainCount: mountains.filter { $0.coverageRole == .core }.count,
                            surroundingMountainCount: mountains.filter { $0.coverageRole == .surroundingCandidate }.count
                        )
                    } label: {
                        SettingsLabel(title: "オフラインデータ", systemImage: "arrow.down.circle")
                    }
                    LabeledContent {
                        Text("丹沢 \(mountains.filter { $0.coverageRole == .core }.count)座・周辺 \(mountains.filter { $0.coverageRole == .surroundingCandidate }.count)座")
                            .foregroundStyle(.secondary)
                    } label: {
                        SettingsLabel(title: "内蔵基本データ", systemImage: "mountain.2")
                    }
                }

                Section("プライバシーと情報") {
                    SettingsLink(title: "権限", value: nil, systemImage: "hand.raised")
                    SettingsLink(title: "データと出典", value: nil, systemImage: "book.closed")
                    SettingsLink(title: "YamaLensについて", value: "0.1.0", systemImage: "info.circle")
                }

                if let diagnosticLogRepository {
                    Section {
                        NavigationLink {
                            DiagnosticLogsView(
                                repository: diagnosticLogRepository,
                                mountains: mountains,
                                projector: cameraProjector
                            )
                        } label: {
                            SettingsLabel(title: "診断ログ", systemImage: "waveform.path.ecg")
                        }
                    } header: {
                        Text("開発用")
                    } footer: {
                        Text("Debugビルドでだけ表示されます。正確な位置を含むログは、明示的に保存した場合だけ端末内へ残ります。")
                    }
                }

                Section("このiPhone内のデータ") {
                    Text("山ノート、お気に入り、登頂済み、出発駅はこのiPhone内に保存されます。クラウド同期とバックアップはMVPでは行いません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TopographicBackground())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ExternalMapApplicationSettingsView: View {
    @Binding var selectedApplicationRawValue: String

    private var selectedApplication: ExternalMapApplication {
        ExternalMapApplication(rawValue: selectedApplicationRawValue) ?? .appleMaps
    }

    var body: some View {
        List {
            Section {
                ForEach(availableApplications, id: \.self) { application in
                    Button {
                        selectedApplicationRawValue = application.rawValue
                    } label: {
                        HStack {
                            Text(application.displayName)
                            Spacer()
                            if selectedApplication == application {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(YamaColor.alpineTeal)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(application.displayName)
                    .accessibilityAddTraits(selectedApplication == application ? .isSelected : [])
                }
            } footer: {
                Text("Google MapsはこのiPhoneにインストールされている場合だけ表示されます。")
            }
        }
        .navigationTitle("地図アプリ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableApplications: [ExternalMapApplication] {
        var applications: [ExternalMapApplication] = [.appleMaps]
        if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
            applications.append(.googleMaps)
        }
        applications.append(.askEveryTime)
        return applications
    }
}

private struct ExternalBrowserApplicationSettingsView: View {
    @Binding var selectedApplicationRawValue: String

    private var selectedApplication: ExternalBrowserApplication {
        ExternalBrowserApplication(rawValue: selectedApplicationRawValue) ?? .defaultBrowser
    }

    var body: some View {
        List {
            Section {
                ForEach(availableApplications, id: \.self) { application in
                    Button {
                        selectedApplicationRawValue = application.rawValue
                    } label: {
                        HStack {
                            Text(application.displayName)
                            Spacer()
                            if selectedApplication == application {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(YamaColor.alpineTeal)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(application.displayName)
                    .accessibilityAddTraits(selectedApplication == application ? .isSelected : [])
                }
            } footer: {
                Text("既定のブラウザはiPhoneの設定に従います。ChromeはこのiPhoneにインストールされている場合だけ表示されます。")
            }
        }
        .navigationTitle("公式サイトを開くブラウザ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableApplications: [ExternalBrowserApplication] {
        var applications: [ExternalBrowserApplication] = [.defaultBrowser]
        if ExternalBrowserApplicationAvailability.isChromeAvailable {
            applications.append(.chrome)
        }
        applications.append(.askEveryTime)
        return applications
    }
}

private struct SettingsLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
    }
}

private struct SettingsLink: View {
    let title: String
    let value: String?
    let systemImage: String

    var body: some View {
        HStack {
            SettingsLabel(title: title, systemImage: systemImage)
            Spacer()
            if let value {
                Text(value).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
    }
}
