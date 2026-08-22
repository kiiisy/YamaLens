import SwiftUI

struct OfflineView: View {
    let coreMountainCount: Int
    let surroundingMountainCount: Int

    init(coreMountainCount: Int = 0, surroundingMountainCount: Int = 0) {
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
                Text("未導入")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YamaColor.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(YamaColor.amber.opacity(0.14), in: Capsule())
            }

            Text("地形による見通し判定や山小屋・登山口情報に使用する詳細パックは、現在準備中です。基本データは引き続き利用できます。")
                .font(.subheadline)
                .foregroundStyle(YamaColor.secondaryText)

            Label("ダウンロード提供前", systemImage: "shippingbox")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YamaColor.secondaryText)
        }
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-detail-pack-status")
    }

    private func featureRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(YamaColor.primaryText)
    }

    private var dataProtectionNote: some View {
        Label {
            Text("詳細パックを追加・更新・削除する機能を導入しても、山ノート・お気に入り・登頂済みは別領域で保持します。")
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
