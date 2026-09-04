import SwiftData
import SwiftUI

struct MyView: View {
    @Binding private var showsTerrainHorizon: Bool
    private let mountains: [Mountain]
    private let mountainWeatherRepository: any MountainWeatherRepository
    private let pointOfInterestRepository: any MountainPointOfInterestRepository
    private let diagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    private let diagnosticShareFileProvider: (any CameraDiagnosticShareFileProviding)?
    private let cameraProjector: MountainCameraProjector
    private let offlinePackageModel: OfflinePackageScreenModel
    private let offlinePackagePresentation: OfflinePackagePresentation
    @Query private var records: [UserMountainRecord]
    @State private var isSettingsPresented = false

    init(
        repository: any MountainRepository,
        pointOfInterestRepository: any MountainPointOfInterestRepository,
        mountainWeatherRepository: any MountainWeatherRepository,
        showsTerrainHorizon: Binding<Bool> = .constant(true),
        diagnosticLogRepository: (any CameraDiagnosticLogRepository)? = nil,
        diagnosticShareFileProvider: (any CameraDiagnosticShareFileProviding)? = nil,
        cameraProjector: MountainCameraProjector = MountainCameraProjector(),
        offlinePackageModel: OfflinePackageScreenModel,
        offlinePackagePresentation: OfflinePackagePresentation = .tanzawa
    ) {
        _showsTerrainHorizon = showsTerrainHorizon
        mountains = repository.fetchMountains()
        self.mountainWeatherRepository = mountainWeatherRepository
        self.pointOfInterestRepository = pointOfInterestRepository
        self.diagnosticLogRepository = diagnosticLogRepository
        self.diagnosticShareFileProvider = diagnosticShareFileProvider
        self.cameraProjector = cameraProjector
        self.offlinePackageModel = offlinePackageModel
        self.offlinePackagePresentation = offlinePackagePresentation
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
                        librarySection
                        offlineSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Mountain.self) {
                MountainDetailView(
                    mountain: $0,
                    weatherRepository: mountainWeatherRepository,
                    pointOfInterestRepository: pointOfInterestRepository
                )
            }
            .navigationDestination(for: MyMountainCollection.self) { collection in
                MyMountainCollectionView(
                    collection: collection,
                    mountains: mountains,
                    records: records
                )
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsPlaceholderView(
                    showsTerrainHorizon: $showsTerrainHorizon,
                    diagnosticLogRepository: diagnosticLogRepository,
                    diagnosticShareFileProvider: diagnosticShareFileProvider,
                    mountains: mountains,
                    cameraProjector: cameraProjector,
                    offlinePackageModel: offlinePackageModel,
                    offlinePackagePresentation: offlinePackagePresentation
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
                Text("記録")
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

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "保存した山", subtitle: "端末内に保存したお気に入りと閲覧履歴")
            libraryRow(collection: .favorites, count: favorites.count, icon: "star.fill", color: YamaColor.amber)
            libraryRow(collection: .summited, count: summited.count, icon: "flag.fill", color: YamaColor.moss)
            libraryRow(collection: .recent, count: recent.count, icon: "clock.fill", color: YamaColor.alpineTeal)
        }
    }

    private func libraryRow(collection: MyMountainCollection, count: Int, icon: String, color: Color) -> some View {
        NavigationLink(value: collection) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.12), in: Circle())
                Text(collection.title).font(.headline).foregroundStyle(YamaColor.primaryText)
                Spacer()
                Text("\(count)件").font(.subheadline).foregroundStyle(YamaColor.secondaryText)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(YamaColor.secondaryText)
            }
            .frame(minHeight: 62)
            .padding(.horizontal, 14)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(collection.title)、\(count)件")
    }

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "オフライン")
            NavigationLink {
                OfflineView(
                    model: offlinePackageModel,
                    presentation: offlinePackagePresentation,
                    coreMountainCount: mountains.filter { $0.coverageRole == .core }.count,
                    surroundingMountainCount: mountains.filter { $0.coverageRole == .surroundingCandidate }.count
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(YamaColor.alpineTeal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(offlinePackagePresentation.packageTitle)
                            .font(.headline)
                            .foregroundStyle(YamaColor.primaryText)
                        Text(
                            offlinePackagePresentation.isARTestOnly
                                ? "ARテスト用・詳細情報なし"
                                : "基本データ利用可能 ・ 丹沢 \(mountains.filter { $0.coverageRole == .core }.count)座"
                        )
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
