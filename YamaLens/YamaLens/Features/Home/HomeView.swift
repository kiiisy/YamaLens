import SwiftData
import SwiftUI

struct HomeView: View {
    private let mountains: [Mountain]
    private let onSelectMountain: (MountainDetailPresentation) -> Void
    @Query private var records: [UserMountainRecord]
    @State private var isSearchPresented = false
    @State private var mountainCardFrames: [String: CGRect] = [:]

    init(
        repository: any MountainRepository,
        onSelectMountain: @escaping (MountainDetailPresentation) -> Void
    ) {
        mountains = repository.fetchMountains()
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
                MountainSearchView(mountains: mountains)
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

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "この近くの山", subtitle: "位置情報は選んだときだけ使います")
                .padding(.horizontal, 18)

            Button(action: {}) {
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
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
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
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("search-result-\(mountain.id)")
            }
            .searchable(text: $searchText, prompt: "山名・山域で検索")
            .navigationTitle("山を探す")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Mountain.self) { mountain in
                MountainDetailView(mountain: mountain)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
