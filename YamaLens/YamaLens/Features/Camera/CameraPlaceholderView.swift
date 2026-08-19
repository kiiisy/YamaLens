import SwiftUI

struct CameraPlaceholderView: View {
    @Binding var selectedTab: YamaTab

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.20, blue: 0.21), YamaColor.canvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                cameraRidges

                VStack(spacing: 0) {
                    statusBar
                    Spacer()
                    permissionCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var cameraRidges: some View {
        VStack {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 230))
                .foregroundStyle(.white.opacity(0.045))
                .offset(y: 40)
        }
        .accessibilityHidden(true)
    }

    private var statusBar: some View {
        HStack {
            Label("丹沢パック未保存", systemImage: "arrow.down.circle")
            Spacer()
            Label("候補待機中", systemImage: "scope")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(YamaColor.primaryText)
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(.regularMaterial, in: Capsule())
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(YamaColor.alpineTeal)
                VStack(alignment: .leading, spacing: 5) {
                    Text("カメラで山候補を探す")
                        .font(.title3.bold())
                    Text("カメラ・位置情報・端末姿勢から、見えている可能性が高い山を候補として表示します。")
                        .font(.subheadline)
                        .foregroundStyle(YamaColor.secondaryText)
                }
            }

            Text("映像と正確な位置は端末外へ送信しません。許可しなくても一覧と検索を利用できます。")
                .font(.footnote)
                .foregroundStyle(YamaColor.secondaryText)

            Button("カメラを使う") {}
                .buttonStyle(.borderedProminent)
                .tint(YamaColor.forest)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

            Button("検索から山を選ぶ") { selectedTab = .home }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("camera-search-button")
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
