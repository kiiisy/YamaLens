import SwiftUI

struct OfflineView: View {
    @State private var isDownloadConfirmationPresented = false

    var body: some View {
        ZStack {
            TopographicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    storageSummary
                    packCard
                    explanation
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("オフラインパック")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .confirmationDialog("丹沢パックを保存しますか？", isPresented: $isDownloadConfirmationPresented) {
            Button("保存を開始") {}
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("実際のダウンロード機能はデータパックの準備後に有効になります。")
        }
    }

    private var storageSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("保存容量", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("0MB / 1GB").foregroundStyle(YamaColor.secondaryText)
            }
            ProgressView(value: 0, total: 1)
                .tint(YamaColor.alpineTeal)
            Text("MVPでは丹沢山地だけを提供します")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var packCard: some View {
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
                    Text("オフラインパック")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(18)
            }
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 16) {
                Label("未保存", systemImage: "icloud.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.amber)

                featureRow("山頂・山小屋・登山口の基本情報", icon: "list.bullet.rectangle")
                featureRow("カメラ候補に必要な地形データ", icon: "camera.viewfinder")
                featureRow("圏外での山詳細閲覧", icon: "wifi.slash")

                Button("丹沢パックを保存") {
                    isDownloadConfirmationPresented = true
                }
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(18)
        }
        .background(YamaColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)) }
    }

    private func featureRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(YamaColor.primaryText)
    }

    private var explanation: some View {
        Label {
            Text("パックを削除しても、山ノート・お気に入り・登頂済みは削除されません。")
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
