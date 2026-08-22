import SwiftData
import SwiftUI

struct MyView: View {
    @Binding private var showsTerrainHorizon: Bool
    private let mountains: [Mountain]
    private let diagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    private let cameraProjector: MountainCameraProjector
    private let offlinePackageModel: OfflinePackageScreenModel
    @Query private var records: [UserMountainRecord]
    @State private var isSettingsPresented = false

    init(
        repository: any MountainRepository,
        showsTerrainHorizon: Binding<Bool> = .constant(true),
        diagnosticLogRepository: (any CameraDiagnosticLogRepository)? = nil,
        cameraProjector: MountainCameraProjector = MountainCameraProjector(),
        offlinePackageModel: OfflinePackageScreenModel
    ) {
        _showsTerrainHorizon = showsTerrainHorizon
        mountains = repository.fetchMountains()
        self.diagnosticLogRepository = diagnosticLogRepository
        self.cameraProjector = cameraProjector
        self.offlinePackageModel = offlinePackageModel
    }

    private var favorites: [Mountain] { mountains(matching: records.filter(\.isFavorite)) }
    private var summited: [Mountain] { mountains(matching: records.filter(\.isSummited)) }
    private var recent: [Mountain] {
        mountains(matching: records.filter { $0.lastViewedAt != nil }.sorted {
            ($0.lastViewedAt ?? .distantPast) > ($1.lastViewedAt ?? .distantPast)
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TopographicBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        summary
                        librarySection
                        offlineSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Mountain.self) { MountainDetailView(mountain: $0) }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsPlaceholderView(
                    showsTerrainHorizon: $showsTerrainHorizon,
                    diagnosticLogRepository: diagnosticLogRepository,
                    mountains: mountains,
                    cameraProjector: cameraProjector,
                    offlinePackageModel: offlinePackageModel
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("マイ")
                    .font(.largeTitle.bold())
                    .foregroundStyle(YamaColor.primaryText)
                Text("自分の山とオフライン情報")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }
            Spacer()
            Button { isSettingsPresented = true } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("設定")
            .accessibilityIdentifier("settings-button")
        }
        .padding(.top, 14)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            metric(value: summited.count, label: "登頂済み", icon: "flag.fill")
            Divider().overlay(.white.opacity(0.12)).frame(height: 50)
            metric(value: favorites.count, label: "お気に入り", icon: "star.fill")
            Divider().overlay(.white.opacity(0.12)).frame(height: 50)
            metric(value: recent.count, label: "最近見た", icon: "clock.fill")
        }
        .padding(.vertical, 18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08)) }
    }

    private func metric(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Label(value.formatted(), systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(YamaColor.moss)
            Text(label)
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "山の記録")
            libraryRow(title: "お気に入り", count: favorites.count, icon: "star.fill", color: YamaColor.amber)
            libraryRow(title: "登頂済み", count: summited.count, icon: "flag.fill", color: YamaColor.moss)
            libraryRow(title: "最近見た山", count: recent.count, icon: "clock.fill", color: YamaColor.alpineTeal)
        }
    }

    private func libraryRow(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: Circle())
            Text(title).font(.headline).foregroundStyle(YamaColor.primaryText)
            Spacer()
            Text("\(count)件").font(.subheadline).foregroundStyle(YamaColor.secondaryText)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(YamaColor.secondaryText)
        }
        .frame(minHeight: 62)
        .padding(.horizontal, 14)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "オフライン")
            NavigationLink {
                OfflineView(
                    model: offlinePackageModel,
                    coreMountainCount: mountains.filter { $0.coverageRole == .core }.count,
                    surroundingMountainCount: mountains.filter { $0.coverageRole == .surroundingCandidate }.count
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(YamaColor.alpineTeal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("丹沢オフラインパック")
                            .font(.headline)
                            .foregroundStyle(YamaColor.primaryText)
                        Text("基本データ利用可能 ・ 丹沢 \(mountains.filter { $0.coverageRole == .core }.count)座")
                            .font(.subheadline)
                            .foregroundStyle(YamaColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(YamaColor.secondaryText)
                }
                .padding(16)
                .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("offline-pack-link")
        }
    }

    private func mountains(matching records: [UserMountainRecord]) -> [Mountain] {
        records.compactMap { record in mountains.first { $0.id == record.mountainID } }
    }
}
