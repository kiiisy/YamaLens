import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let diagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let mountains: [Mountain]
    let cameraProjector: MountainCameraProjector

    init(
        diagnosticLogRepository: (any CameraDiagnosticLogRepository)? = nil,
        mountains: [Mountain] = [],
        cameraProjector: MountainCameraProjector = MountainCameraProjector()
    ) {
        self.diagnosticLogRepository = diagnosticLogRepository
        self.mountains = mountains
        self.cameraProjector = cameraProjector
    }

    var body: some View {
        NavigationStack {
            List {
                Section("カメラ表示") {
                    Toggle(isOn: .constant(true)) {
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
                    SettingsLink(title: "地図アプリ", value: "毎回選択", systemImage: "map")
                }

                Section("オフライン") {
                    NavigationLink {
                        DownloadSettingsView()
                    } label: {
                        SettingsLabel(title: "ダウンロード設定", systemImage: "arrow.down.circle")
                    }
                    SettingsLink(title: "丹沢パック", value: "未保存", systemImage: "mountain.2")
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

private struct DownloadSettingsView: View {
    @State private var automaticDownloads = false
    @State private var wifiOnly = true
    @State private var mobileData = false

    var body: some View {
        Form {
            Section {
                Toggle("自動ダウンロード", isOn: $automaticDownloads)
                Toggle("Wi-Fi接続時のみ", isOn: $wifiOnly)
                    .disabled(!automaticDownloads)
                Toggle("モバイル通信を使用", isOn: $mobileData)
                    .disabled(!automaticDownloads || wifiOnly)
            } footer: {
                Text("自動ダウンロードは初期状態ではオフです。オンにした場合もWi-Fi接続時のみを推奨します。")
            }

            Section("保存容量") {
                LabeledContent("保存容量の上限", value: "1GB")
                LabeledContent("現在の使用量", value: "0MB")
            }

            Section {
                Button("パックの更新を確認") {}
            }
        }
        .navigationTitle("ダウンロード設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
