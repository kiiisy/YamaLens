import SwiftUI

struct OfflineView: View {
    let model: OfflinePackageScreenModel
    let coreMountainCount: Int
    let surroundingMountainCount: Int
    @State private var isDeleteConfirmationPresented = false

    init(
        model: OfflinePackageScreenModel,
        coreMountainCount: Int = 0,
        surroundingMountainCount: Int = 0
    ) {
        self.model = model
        self.coreMountainCount = coreMountainCount
        self.surroundingMountainCount = surroundingMountainCount
    }

    var body: some View {
        ZStack {
            TopographicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    availabilitySummary
                    bootstrapCard
                    detailedPackCard
                    dataProtectionNote
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("オフラインパック")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .alert(
            "丹沢詳細パックを削除しますか？",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("削除", role: .destructive) {
                Task { await model.deleteInstalledPackage() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("詳細地形と施設データを削除します。山ノート・お気に入り・登頂済みは削除されません。")
        }
    }

    private var availabilitySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("オフライン利用", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                Spacer()
                Text("基本データ利用可能")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.moss)
            }
            Text("通信がなくても、丹沢の山を一覧・検索できます。AR識別用に、富士山など周辺の主要山頂も収録しています。")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-bootstrap-status")
    }

    private var bootstrapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [YamaColor.forest.opacity(0.8), YamaColor.deepForest],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(.white.opacity(0.13))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("丹沢山地")
                        .font(.title.bold())
                    Text("アプリ内蔵の基本データ")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(18)
            }
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 16) {
                Label("利用可能", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.moss)

                featureRow("山名・別名・標高・山頂座標", icon: "list.bullet.rectangle")
                featureRow("一覧・検索・基本詳細", icon: "magnifyingglass")
                featureRow("カメラ候補の基礎となる山頂情報", icon: "camera.viewfinder")

                LabeledContent("丹沢の山") {
                    Text("\(coreMountainCount)座")
                        .foregroundStyle(YamaColor.primaryText)
                }
                .font(.subheadline)

                LabeledContent("周辺候補") {
                    Text("\(surroundingMountainCount)座")
                        .foregroundStyle(YamaColor.primaryText)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("offline-surrounding-count")
            }
            .padding(18)
        }
        .background(YamaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)) }
    }

    private var detailedPackCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("丹沢詳細パック")
                        .font(.headline)
                    Text("詳細地形・施設・出典データ")
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }
                Spacer()
                detailedPackStatusBadge
            }
            detailedPackContent
        }
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)) }
    }

    @ViewBuilder
    private var detailedPackStatusBadge: some View {
        switch model.state {
        case .installed:
            statusBadge("保存済み", color: YamaColor.moss)
        case .downloading:
            statusBadge("取得中", color: YamaColor.alpineTeal)
        case .verifying:
            statusBadge("検証中", color: YamaColor.alpineTeal)
        case .deleting:
            statusBadge("削除中", color: YamaColor.amber)
        case .failed:
            statusBadge("確認が必要", color: YamaColor.amber)
        case .loading:
            statusBadge("確認中", color: YamaColor.secondaryText)
        case .notInstalled:
            statusBadge("未導入", color: YamaColor.amber)
        }
    }

    @ViewBuilder
    private var detailedPackContent: some View {
        switch model.state {
        case .loading:
            progressRow("保存状態を確認しています")

        case .notInstalled(let distribution):
            Text("詳細パックがなくても、内蔵の基本データで一覧・検索・基本詳細を利用できます。")
                .font(.subheadline)
                .foregroundStyle(YamaColor.secondaryText)
            if distribution == .available {
                Button {
                    Task { await model.install() }
                } label: {
                    Label("丹沢詳細パックを保存", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
                .accessibilityIdentifier("offline-install-button")
            } else {
                Label("ダウンロード提供前", systemImage: "shippingbox")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.secondaryText)
            }

        case .installed(let package, let distribution):
            installedPackageDetails(package)
            if distribution == .available {
                Button {
                    Task { await model.install() }
                } label: {
                    Label("更新を確認", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("offline-update-button")
            }
            deleteButton

        case .downloading(let completedBytes, let totalBytes, let previousPackage):
            downloadingProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes
            )
            if previousPackage != nil {
                Text("更新が完了するまで、現在のパックを使い続けます。")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
            }

        case .verifying(let previousPackage):
            progressRow("署名とデータの整合性を確認しています")
            if previousPackage != nil {
                Text("検証に失敗しても、現在のパックは保持されます。")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
            }

        case .deleting:
            progressRow("詳細パックを削除しています")

        case .failed(let failure, let previousPackage, let distribution):
            failureContent(failure)
            if let previousPackage {
                Text("保存済みのバージョン \(previousPackage.contentVersion) はそのまま利用できます。")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
                deleteButton
            }
            if failure.canRetry, distribution == .available {
                Button {
                    Task { await model.install() }
                } label: {
                    Label("もう一度試す", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
                .accessibilityIdentifier("offline-retry-button")
            }
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("offline-detail-pack-status")
    }

    private func installedPackageDetails(_ package: OfflinePackageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("詳細地形をAR候補の見通し判定に使用します", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YamaColor.moss)
            LabeledContent("バージョン", value: package.contentVersion)
            LabeledContent("使用容量", value: byteCount(package.byteCount))
            LabeledContent(
                "データ作成日",
                value: package.createdAt.formatted(date: .abbreviated, time: .omitted)
            )
        }
        .font(.subheadline)
        .foregroundStyle(YamaColor.primaryText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-installed-package-details")
    }

    @ViewBuilder
    private func downloadingProgress(
        completedBytes: Int64,
        totalBytes: Int64?
    ) -> some View {
        if let totalBytes, totalBytes > 0 {
            ProgressView(
                value: Double(min(completedBytes, totalBytes)),
                total: Double(totalBytes)
            ) {
                Text("詳細パックをダウンロード中")
            } currentValueLabel: {
                Text("\(byteCount(completedBytes)) / \(byteCount(totalBytes))")
            }
            .tint(YamaColor.alpineTeal)
            Text("残り \(byteCount(max(totalBytes - completedBytes, 0)))")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        } else {
            progressRow("詳細パックをダウンロード中")
        }
    }

    private func progressRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(YamaColor.alpineTeal)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YamaColor.primaryText)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func failureContent(_ failure: OfflinePackageManagementFailure) -> some View {
        Label {
            Text(failureMessage(failure))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(YamaColor.amber)
        }
        .font(.subheadline)
        .foregroundStyle(YamaColor.secondaryText)
        .accessibilityIdentifier("offline-package-error")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("詳細パックを削除", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("offline-delete-button")
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatStyle(style: .file).format(value)
    }

    private func failureMessage(_ failure: OfflinePackageManagementFailure) -> String {
        switch failure {
        case .temporaryFailure:
            return "通信が安定してから、もう一度お試しください。"
        case .distributionUnavailable:
            return "配布データを取得できません。基本データは引き続き利用できます。"
        case .insufficientStorage(let requiredBytes, let availableBytes):
            if let requiredBytes, let availableBytes {
                return "必要容量は \(byteCount(requiredBytes))、現在の空き容量は \(byteCount(availableBytes)) です。iPhoneの保存容量を確認してください。"
            }
            return "空き容量が不足しています。iPhoneの保存容量を確認してください。"
        case .invalidData:
            return "パックを安全に確認できなかったため、導入しませんでした。"
        case .cancelled:
            return "ダウンロードを中止しました。"
        case .internalFailure:
            return "保存状態を確認できませんでした。基本データは引き続き利用できます。"
        }
    }

    private func featureRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(YamaColor.primaryText)
    }

    private var dataProtectionNote: some View {
        Label {
            Text("詳細パックを追加・更新・削除しても、山ノート・お気に入り・登頂済みは別領域で保持します。")
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(YamaColor.moss)
        }
        .font(.footnote)
        .foregroundStyle(YamaColor.secondaryText)
        .padding(16)
        .background(YamaColor.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
