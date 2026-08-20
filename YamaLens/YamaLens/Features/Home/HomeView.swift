import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    private let mountains: [Mountain]
    private let locationModel: LocationSessionModel
    private let proximityCalculator: MountainProximityCalculator
    private let onSelectMountain: (MountainDetailPresentation) -> Void
    @Environment(\.openURL) private var openURL
    @Query private var records: [UserMountainRecord]
    @State private var isSearchPresented = false
    @State private var mountainCardFrames: [String: CGRect] = [:]

    init(
        repository: any MountainRepository,
        locationModel: LocationSessionModel,
        proximityCalculator: MountainProximityCalculator,
        onSelectMountain: @escaping (MountainDetailPresentation) -> Void
    ) {
        mountains = repository.fetchMountains()
        self.locationModel = locationModel
        self.proximityCalculator = proximityCalculator
        self.onSelectMountain = onSelectMountain
    }

    private var favorites: [Mountain] {
        let favoriteIDs = Set(records.filter(\.isFavorite).map(\.mountainID))
        return mountains.filter { favoriteIDs.contains($0.id) }
    }

    private var recentMountains: [Mountain] {
        let recentIDs = records
            .compactMap { record -> (String, Date)? in
                guard let date = record.lastViewedAt else { return nil }
                return (record.mountainID, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map(\.0)
        return recentIDs.compactMap { id in mountains.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TopographicBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        homeHeader
                        seasonalSection
                        nearbySection
                        favoritesSection
                        recentSection
                    }
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isSearchPresented) {
                MountainSearchView(
                    mountains: mountains,
                    currentLocationState: locationModel.state,
                    proximityCalculator: proximityCalculator
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var homeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("YamaLens")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(YamaColor.primaryText)
                Text("丹沢の山を見つける")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }

            Spacer()

            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("山を検索")
            .accessibilityIdentifier("search-button")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var seasonalSection: some View {
        posterSection(
            title: "今の時期の山",
            subtitle: "季節情報のある丹沢の山",
            mountains: Array(mountains.prefix(4)),
            badge: "季節の紹介"
        )
    }

    @ViewBuilder
    private var nearbySection: some View {
        switch locationModel.state {
        case .notRequested:
            locationRequestSection
        case .loading:
            locationLoadingSection
        case .available(let observation, let quality):
            nearbyResultsSection(observation: observation, quality: quality)
        case .denied:
            locationRecoverySection(
                title: "位置情報が許可されていません",
                message: "設定で「使用中のみ」を許可すると、現在地から近い山を表示できます。",
                actionTitle: "設定を開く",
                action: openLocationSettings
            )
        case .restricted:
            locationRecoverySection(
                title: "位置情報を利用できません",
                message: "端末の制限により利用できません。山一覧と検索はそのまま使えます。",
                actionTitle: "山を検索",
                action: { isSearchPresented = true }
            )
        case .insufficientAccuracy:
            locationRecoverySection(
                title: "現在地の精度が足りません",
                message: "空が見える場所へ移動して、もう一度確認してください。",
                actionTitle: "もう一度試す",
                action: requestLocation
            )
        case .unavailable:
            locationRecoverySection(
                title: "現在地を取得できません",
                message: "山一覧と検索は利用できます。環境を確認して再試行してください。",
                actionTitle: "もう一度試す",
                action: requestLocation
            )
        }
    }

    private var locationRequestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "この近くの山", subtitle: "位置情報は選んだときだけ使います")
                .padding(.horizontal, 18)

            Button(action: requestLocation) {
                HStack(spacing: 14) {
                    Image(systemName: "location.circle.fill")
                        .font(.title2)
                        .foregroundStyle(YamaColor.alpineTeal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("現在地から探す")
                            .font(.headline)
                            .foregroundStyle(YamaColor.primaryText)
                        Text("許可しなくても一覧と検索は利用できます")
                            .font(.caption)
                            .foregroundStyle(YamaColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(YamaColor.secondaryText)
                }
                .padding(16)
                .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .accessibilityHint("使用中のみの位置情報を使って、近い山を表示します")
            .accessibilityIdentifier("nearby-location-button")
        }
    }

    private var locationLoadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "この近くの山", subtitle: "現在地は保存しません")
                .padding(.horizontal, 18)

            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(YamaColor.alpineTeal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("現在地を確認中")
                        .font(.headline)
                        .foregroundStyle(YamaColor.primaryText)
                    Text("近い山を距離順に並べています")
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 18)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nearby-location-loading")
        }
    }

    private func nearbyResultsSection(
        observation: LocationObservation,
        quality: LocationObservationQuality
    ) -> some View {
        let nearbyMountains = proximityCalculator.nearbyMountains(
            from: observation.coordinate,
            mountains: mountains
        )
        let subtitle = quality == .good
            ? "現在地から近い順・位置情報は保存しません"
            : "位置精度が低いため、距離と順序は目安です"

        return VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "この近くの山", subtitle: subtitle)
                .padding(.horizontal, 18)

            if nearbyMountains.isEmpty {
                YamaEmptyCard(
                    title: "近くに登録済みの山がありません",
                    message: "現在地から150km以内に対象がありません。丹沢の山一覧は引き続き利用できます。",
                    systemImage: "location.slash"
                )
                .padding(.horizontal, 18)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(nearbyMountains.prefix(10)), id: \.mountain.id) { result in
                            let sourceID = "この近くの山-\(result.mountain.id)"
                            mountainPosterButton(
                                mountain: result.mountain,
                                sourceID: sourceID,
                                badge: MountainProximityText.summary(result.proximity)
                            )
                            .accessibilityIdentifier("nearby-mountain-\(result.mountain.id)")
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("nearby-mountain-list")
            }
        }
    }

    private func locationRecoverySection(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "この近くの山", subtitle: "山一覧と検索は位置情報なしでも使えます")
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: "location.slash.fill")
                    .font(.headline)
                    .foregroundStyle(YamaColor.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(YamaColor.alpineTeal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 18)
            .accessibilityIdentifier("nearby-location-recovery")
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if favorites.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                YamaSectionHeader(title: "お気に入り")
                YamaEmptyCard(
                    title: "お気に入りはまだありません",
                    message: "山詳細の星をタップすると、ここに表示されます。",
                    systemImage: "star"
                )
            }
            .padding(.horizontal, 18)
        } else {
            posterSection(title: "お気に入り", mountains: Array(favorites.prefix(4)))
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if recentMountains.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                YamaSectionHeader(title: "最近見た山")
                YamaEmptyCard(
                    title: "最近見た山はありません",
                    message: "検索や山カードから詳細を開くと記録されます。",
                    systemImage: "clock"
                )
            }
            .padding(.horizontal, 18)
        } else {
            posterSection(title: "最近見た山", mountains: recentMountains)
        }
    }

    private func posterSection(
        title: String,
        subtitle: String? = nil,
        mountains: [Mountain],
        badge: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 18)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(mountains) { mountain in
                        let sourceID = "\(title)-\(mountain.id)"
                        mountainPosterButton(
                            mountain: mountain,
                            sourceID: sourceID,
                            badge: badge
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func mountainPosterButton(
        mountain: Mountain,
        sourceID: String,
        badge: String?
    ) -> some View {
        Button {
            onSelectMountain(
                MountainDetailPresentation(
                    mountain: mountain,
                    sourceID: sourceID,
                    sourceArtworkFrame: artworkFrame(for: sourceID)
                )
            )
        } label: {
            MountainPosterCard(mountain: mountain, badge: badge)
                .onGeometryChange(for: CGRect.self) { geometry in
                    geometry.frame(in: .global)
                } action: { frame in
                    mountainCardFrames[sourceID] = frame
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mountain-row-\(mountain.id)")
    }

    private func requestLocation() {
        Task {
            await locationModel.requestLocation()
        }
    }

    private func openLocationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private func artworkFrame(for sourceID: String) -> CGRect {
        guard let cardFrame = mountainCardFrames[sourceID] else { return .zero }
        return CGRect(
            x: cardFrame.minX,
            y: cardFrame.minY,
            width: cardFrame.width,
            height: min(cardFrame.height, 148)
        )
    }
}

private struct MountainSearchView: View {
    let mountains: [Mountain]
    let currentLocationState: CurrentLocationState
    let proximityCalculator: MountainProximityCalculator
    private let searchService = MountainSearchService()
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var results: [Mountain] {
        searchService.search(mountains: mountains, query: searchText)
    }

    var body: some View {
        NavigationStack {
            List(results) { mountain in
                NavigationLink(value: mountain) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mountain.name)
                            .font(.headline)
                        Text("\(mountain.elevationMeters.formatted())m ・ \(mountain.regionName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let proximity = proximity(for: mountain) {
                            Label(
                                MountainProximityText.summary(proximity),
                                systemImage: "location"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("search-result-\(mountain.id)")
            }
            .searchable(text: $searchText, prompt: "山名・山域で検索")
            .navigationTitle("山を探す")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Mountain.self) { mountain in
                MountainDetailView(
                    mountain: mountain,
                    currentLocationState: currentLocationState,
                    proximityCalculator: proximityCalculator
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func proximity(for mountain: Mountain) -> MountainProximity? {
        guard case .available(let observation, _) = currentLocationState else { return nil }
        return proximityCalculator.proximity(
            from: observation.coordinate,
            to: mountain.coordinate
        )
    }
}
