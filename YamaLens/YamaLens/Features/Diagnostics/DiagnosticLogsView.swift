import SwiftUI

struct DiagnosticLogsView: View {
    private enum DeleteTarget: Identifiable {
        case one(CameraDiagnosticLog)
        case all

        var id: String {
            switch self {
            case .one(let log):
                return log.id.uuidString
            case .all:
                return "all"
            }
        }
    }

    private let mountains: [Mountain]
    private let projector: MountainCameraProjector
    @State private var model: DiagnosticLogsScreenModel
    @State private var deleteTarget: DeleteTarget?

    init(
        repository: any CameraDiagnosticLogRepository,
        mountains: [Mountain],
        projector: MountainCameraProjector
    ) {
        self.mountains = mountains
        self.projector = projector
        _model = State(initialValue: DiagnosticLogsScreenModel(repository: repository))
    }

    var body: some View {
        List {
            Section {
                Label(
                    "記録開始後の位置・方位・姿勢・候補だけを端末内へ保存します。カメラ映像は保存しません。",
                    systemImage: "lock.iphone"
                )
                .font(.footnote)
            }

            switch model.state {
            case .idle, .loading:
                Section {
                    HStack {
                        ProgressView()
                        Text("診断ログを読み込んでいます")
                    }
                }
            case .failed:
                Section {
                    ContentUnavailableView(
                        "診断ログを読み込めません",
                        systemImage: "exclamationmark.triangle",
                        description: Text("再読み込みしても改善しない場合は、アプリを起動し直してください。")
                    )
                    Button("再読み込み") {
                        Task { await model.load() }
                    }
                }
            case .loaded(let logs):
                if logs.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "保存したログはありません",
                            systemImage: "waveform.path.ecg",
                            description: Text("カメラ画面で「診断記録」を開始すると、ここから再現できます。")
                        )
                    }
                } else {
                    Section {
                        ForEach(logs) { log in
                            logRow(log)
                        }
                    } header: {
                        Text("保存済み \(logs.count)件")
                    } footer: {
                        Text("保持していないログは\(CameraDiagnosticPolicy.default.maximumUnretainedLogAgeDays)日または\(CameraDiagnosticPolicy.default.maximumUnretainedLogCount)件の早い方で自動削除されます。")
                    }
                }
            }
        }
        .navigationTitle("診断ログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if hasLogs {
                    Button(role: .destructive) {
                        deleteTarget = .all
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("診断ログをすべて削除")
                }
            }
        }
        .task { await model.load() }
        .alert(item: $deleteTarget) { target in
            switch target {
            case .one(let log):
                Alert(
                    title: Text("この診断ログを削除しますか？"),
                    message: Text("削除するとリプレイできなくなります。"),
                    primaryButton: .destructive(Text("削除")) {
                        Task { await model.delete(log) }
                    },
                    secondaryButton: .cancel()
                )
            case .all:
                Alert(
                    title: Text("すべての診断ログを削除しますか？"),
                    message: Text("保持中のログも含め、元に戻せません。"),
                    primaryButton: .destructive(Text("すべて削除")) {
                        Task { await model.deleteAll() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(
            "操作を完了できませんでした",
            isPresented: Binding(
                get: { model.operationErrorMessage != nil },
                set: { if !$0 { model.clearOperationError() } }
            )
        ) {
            Button("閉じる", role: .cancel) { model.clearOperationError() }
        } message: {
            Text(model.operationErrorMessage ?? "もう一度お試しください。")
        }
    }

    private func logRow(_ log: CameraDiagnosticLog) -> some View {
        NavigationLink {
            DiagnosticReplayView(
                log: log,
                mountains: mountains,
                projector: projector
            )
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(log.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Spacer()
                    if log.isRetained {
                        Label("保持中", systemImage: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(YamaColor.moss)
                    }
                }
                Text("\(log.samples.count)サンプル・\(durationText(log))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let deletionDate = log.automaticDeletionDate {
                    Text("削除予定 \(deletionDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task { await model.setRetained(!log.isRetained, for: log) }
            } label: {
                Label(log.isRetained ? "保持を解除" : "保持", systemImage: log.isRetained ? "pin.slash" : "pin")
            }
            .tint(YamaColor.forest)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = .one(log)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private var hasLogs: Bool {
        guard case .loaded(let logs) = model.state else { return false }
        return !logs.isEmpty
    }

    private func durationText(_ log: CameraDiagnosticLog) -> String {
        Duration.seconds(max(0, log.endedAt.timeIntervalSince(log.startedAt)))
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}
