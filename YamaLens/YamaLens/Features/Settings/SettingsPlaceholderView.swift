import SwiftUI
import SwiftData
import UIKit

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showsTerrainHorizon: Bool
    let diagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let mountains: [Mountain]
    let cameraProjector: MountainCameraProjector
    let offlinePackageModel: OfflinePackageScreenModel
    let offlinePackagePresentation: OfflinePackagePresentation
    @AppStorage("externalMaps.application") private var mapApplicationRawValue = ExternalMapApplication.appleMaps.rawValue
    @AppStorage("externalBrowser.application") private var browserApplicationRawValue = ExternalBrowserApplication.defaultBrowser.rawValue
#if DEBUG
    @AppStorage(DevelopmentTanzawaTerrainProfile.selectionStorageKey)
    private var developmentTerrainProfileRawValue = ""
#endif
    @Query private var savedDeparturePoints: [SavedDeparturePoint]

    private var mapApplication: ExternalMapApplication {
        ExternalMapApplication(rawValue: mapApplicationRawValue) ?? .appleMaps
    }

    private var browserApplication: ExternalBrowserApplication {
        ExternalBrowserApplication(rawValue: browserApplicationRawValue) ?? .defaultBrowser
    }

#if DEBUG
    private var developmentTerrainProfileTitle: String {
        DevelopmentTanzawaTerrainProfile(rawValue: developmentTerrainProfileRawValue)?.title
            ?? "未選択"
    }
#endif

    init(
        showsTerrainHorizon: Binding<Bool> = .constant(true),
        diagnosticLogRepository: (any CameraDiagnosticLogRepository)? = nil,
        mountains: [Mountain] = [],
        cameraProjector: MountainCameraProjector = MountainCameraProjector(),
        offlinePackageModel: OfflinePackageScreenModel,
        offlinePackagePresentation: OfflinePackagePresentation = .tanzawa
    ) {
        _showsTerrainHorizon = showsTerrainHorizon
        self.diagnosticLogRepository = diagnosticLogRepository
        self.mountains = mountains
        self.cameraProjector = cameraProjector
        self.offlinePackageModel = offlinePackageModel
        self.offlinePackagePresentation = offlinePackagePresentation
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        OfflineView(
                            model: offlinePackageModel,
                            presentation: offlinePackagePresentation,
                            coreMountainCount: mountains.filter { $0.coverageRole == .core }.count,
                            surroundingMountainCount: mountains.filter { $0.coverageRole == .surroundingCandidate }.count
                        )
                    } label: {
                        SettingsLink(
                            title: "保存済みパックを管理",
                            value: offlinePackagePresentation.packageTitle,
                            systemImage: "arrow.down.circle"
                        )
                    }
                    LabeledContent {
                        Text("丹沢 \(mountains.filter { $0.coverageRole == .core }.count)座・周辺 \(mountains.filter { $0.coverageRole == .surroundingCandidate }.count)座")
                            .foregroundStyle(.secondary)
                    } label: {
                        SettingsLabel(title: "内蔵基本データ", systemImage: "mountain.2")
                    }
                } header: {
                    Text("オフラインパック")
                } footer: {
                    Text("パックを削除しても、山ノート・お気に入り・登頂済みはこのiPhoneに残ります。")
                }

                Section("アクセス") {
                    NavigationLink {
                        SavedDeparturePointSettingsView()
                    } label: {
                        SettingsLink(
                            title: "よく使う出発駅",
                            value: savedDeparturePoints.first?.name ?? "未登録",
                            systemImage: "tram"
                        )
                    }
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

                Section("プライバシーと情報") {
                    NavigationLink {
                        PermissionHelpView()
                    } label: {
                        SettingsLink(title: "権限と端末設定", value: nil, systemImage: "hand.raised")
                    }
                    NavigationLink {
                        DataSourcesView()
                    } label: {
                        SettingsLink(title: "データと出典", value: nil, systemImage: "book.closed")
                    }
                    NavigationLink {
                        AboutYamaLensView()
                    } label: {
                        SettingsLink(title: "YamaLensについて", value: "0.1.0", systemImage: "info.circle")
                    }
                }

                if let diagnosticLogRepository {
                    Section {
                        Toggle(isOn: $showsTerrainHorizon) {
                            SettingsLabel(title: "稜線を表示", systemImage: "waveform.path")
                        }
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
                        Text("Debugビルドでだけ表示されます。診断ログは明示的に保存した場合だけ端末内へ残り、カメラ映像は保存しません。")
                    }
                }

#if DEBUG
                Section {
                    NavigationLink {
                        DevelopmentTerrainProfileSettingsView()
                    } label: {
                        SettingsLink(
                            title: "地形精度の比較",
                            value: developmentTerrainProfileTitle,
                            systemImage: "square.3.layers.3d.down.right"
                        )
                    }
                } header: {
                    Text("地形テスト")
                } footer: {
                    Text("Debugビルドだけの現地検証用です。選択後はアプリを終了して開き直してください。通常版には表示されません。")
                }
#endif

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

#if DEBUG
private struct DevelopmentTerrainProfileSettingsView: View {
    @AppStorage(DevelopmentTanzawaTerrainProfile.selectionStorageKey)
    private var selectedProfileRawValue = ""
    @State private var isRestartNoticePresented = false

    private var selectedProfile: DevelopmentTanzawaTerrainProfile? {
        DevelopmentTanzawaTerrainProfile(rawValue: selectedProfileRawValue)
    }

    var body: some View {
        List {
            Section {
                ForEach(DevelopmentTanzawaTerrainProfile.allCases, id: \.self) { profile in
                    Button {
                        selectedProfileRawValue = profile.rawValue
                        isRestartNoticePresented = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.title)
                                Text(profile.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedProfile == profile {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(YamaColor.alpineTeal)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(profile.title)
                    .accessibilityValue(
                        selectedProfile == profile ? "選択中" : "未選択"
                    )
                    .accessibilityAddTraits(
                        selectedProfile == profile ? .isSelected : []
                    )
                    .accessibilityIdentifier("development-terrain-profile-\(profile.rawValue)")
                }
            } header: {
                Text("丹沢の地形データ")
            } footer: {
                Text("3種類を同じ地点・同じ向きで比べるための開発用操作です。あらかじめ各パックを保存しておくと、現地では通信なしで切り替えられます。")
            }
        }
        .navigationTitle("地形精度の比較")
        .navigationBarTitleDisplayMode(.inline)
        .alert("再起動が必要です", isPresented: $isRestartNoticePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("選択を保存しました。アプリを完全に終了してから開き直すと、選択した地形データで候補を計算します。")
        }
    }
}
#endif

private struct PermissionHelpView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Label("カメラ・位置情報は、山候補を表示する直前にだけ求めます。許可しなくても、山の一覧、検索、詳細、山ノートは利用できます。", systemImage: "camera")
                Label("権限を変更する場合は、iPhoneの設定からYamaLensを開いてください。", systemImage: "gearshape")
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Button("iPhoneの設定を開く") {
                        openURL(settingsURL)
                    }
                }
            } header: {
                Text("カメラ・位置情報")
            }
        }
        .navigationTitle("権限と端末設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataSourcesView: View {
    var body: some View {
        List {
            Section("天気") {
                LabeledContent("提供元", value: "WeatherKit")
                Text("天気の取得日時と対象地点は、山詳細で各情報と一緒に表示します。通信できないときは、利用できる保存済み情報だけを表示します。")
            }
            Section("地形・山の情報") {
                Text("山頂・地形・施設情報は、確認済みの出典をパック作成時に取り込みます。施設の変動情報はアプリ内だけで判断せず、公式情報も確認してください。")
            }
            Section("端末内の個人データ") {
                Text("山ノート、お気に入り、登頂済み、よく使う出発駅名はこのiPhone内に保存します。カメラ映像、位置履歴、検索履歴は保存しません。")
            }
        }
        .navigationTitle("データと出典")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutYamaLensView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("バージョン", value: "0.1.0")
                LabeledContent("対応地域", value: "丹沢山地")
            }
            Section {
                Text("YamaLensは、山を調べ、見えている山の候補を確認し、自分の記録を端末内に残すためのアプリです。経路案内や登山の可否判断は行いません。")
            }
        }
        .navigationTitle("YamaLensについて")
        .navigationBarTitleDisplayMode(.inline)
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
