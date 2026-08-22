import SwiftData
import SwiftUI

enum MountainDetailDismissalStyle {
    case zoomToSource
    case dragged
}

struct MountainDetailView: View {
    let mountain: Mountain
    private let currentLocationState: CurrentLocationState
    private let proximityCalculator: MountainProximityCalculator
    private let onClose: ((MountainDetailDismissalStyle) -> Void)?
    private let overlayTopInset: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [UserMountainRecord]
    @State private var isNotesPresented = false
    @State private var dismissDragDistance: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @State private var scrollOffset: CGFloat = 0

    init(
        mountain: Mountain,
        currentLocationState: CurrentLocationState = .notRequested,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator(),
        overlayTopInset: CGFloat? = nil,
        onClose: ((MountainDetailDismissalStyle) -> Void)? = nil
    ) {
        self.mountain = mountain
        self.currentLocationState = currentLocationState
        self.proximityCalculator = proximityCalculator
        self.overlayTopInset = overlayTopInset
        self.onClose = onClose
    }

    private var record: UserMountainRecord? {
        records.first { $0.mountainID == mountain.id }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TopographicBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        hero
                        surroundingCandidateNotice
                        statusCard
                        weatherSection
                        facilitySection
                        accessSection
                        notesSection
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(isDraggingToDismiss)
                .offset(y: scrollBounceCompensation)
                .accessibilityIdentifier("mountain-detail")
                .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in
                    scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }

                if onClose != nil {
                    detailHeader(topInset: overlayTopInset ?? geometry.safeAreaInsets.top)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: detailCornerRadius,
                    style: .continuous
                )
            )
            .scaleEffect(detailScale)
            .offset(y: dismissDragDistance)
            .simultaneousGesture(dismissGesture(containerHeight: geometry.size.height))
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(onClose == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if onClose == nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { toggleFavorite() } label: {
                        Image(systemName: record?.isFavorite == true ? "star.fill" : "star")
                    }
                    .accessibilityLabel(record?.isFavorite == true ? "お気に入りから外す" : "お気に入りに追加")
                    ShareLink(item: "\(mountain.name) \(mountain.elevationMeters)m") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("共有")
                }
            }
        }
        .task { markViewed() }
        .sheet(isPresented: $isNotesPresented) {
            if let record {
                MountainNotesView(mountain: mountain, record: record)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var surroundingCandidateNotice: some View {
        if mountain.coverageRole == .surroundingCandidate {
            VStack(alignment: .leading, spacing: 8) {
                Label("周辺候補データ", systemImage: "binoculars.fill")
                    .font(.headline)
                    .foregroundStyle(YamaColor.alpineTeal)
                Text("丹沢から見える可能性のある山として、名称・標高・座標を収録しています。詳細地形・施設情報は未対応です。")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                YamaColor.surface,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .padding(.horizontal, 18)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("surrounding-candidate-notice")
        }
    }

    private var detailScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return 1 - min(dismissDragDistance / 1_600, 0.18)
    }

    private var detailCornerRadius: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(dismissDragDistance / 8, 30)
    }

    private var scrollBounceCompensation: CGFloat {
        guard isDraggingToDismiss else { return 0 }
        return min(scrollOffset, 0)
    }

    private func dismissGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard onClose != nil else { return }
                let downwardDistance = value.translation.height
                let horizontalDistance = abs(value.translation.width)
                let isPrimarilyDownward = downwardDistance > horizontalDistance * 1.2

                guard isDraggingToDismiss || scrollOffset <= 1 else { return }
                guard isDraggingToDismiss || isPrimarilyDownward else { return }
                guard downwardDistance > 0 else { return }

                isDraggingToDismiss = true
                dismissDragDistance = downwardDistance
            }
            .onEnded { value in
                guard isDraggingToDismiss else { return }

                let shouldDismiss = value.translation.height > 120
                    || value.predictedEndTranslation.height > 260

                if shouldDismiss {
                    let finishDismissal = {
                        onClose?(.dragged)
                    }

                    if reduceMotion {
                        finishDismissal()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dismissDragDistance = max(containerHeight, value.translation.height)
                        } completion: {
                            finishDismissal()
                        }
                    }
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                        dismissDragDistance = 0
                    }
                }

                isDraggingToDismiss = false
            }
    }

    private func detailHeader(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                onClose?(.zoomToSource)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("戻る")
            .accessibilityIdentifier("detail-close-button")

            Spacer()

            Button { toggleFavorite() } label: {
                Image(systemName: record?.isFavorite == true ? "star.fill" : "star")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(record?.isFavorite == true ? "お気に入りから外す" : "お気に入りに追加")
            .accessibilityIdentifier("detail-favorite-button")

            ShareLink(item: "\(mountain.name) \(mountain.elevationMeters)m") {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("共有")
            .accessibilityIdentifier("detail-share-button")
        }
        .padding(.horizontal, 14)
        .padding(.top, topInset + 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hero: some View {
        MountainArtworkView(mountain: mountain, height: 350)
            .overlay {
                LinearGradient(colors: [.clear, YamaColor.canvas], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(mountain.regionName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YamaColor.moss)
                    Text(mountain.name)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("標高 \(mountain.elevationMeters.formatted())m ・ \(mountain.prefectureName)")
                        .font(.subheadline)
                        .foregroundStyle(YamaColor.secondaryText)
                    locationSummary
                }
                .foregroundStyle(YamaColor.primaryText)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
    }

    @ViewBuilder
    private var locationSummary: some View {
        switch currentLocationState {
        case .available(let observation, let quality):
            if let proximity = proximityCalculator.proximity(
                from: observation.coordinate,
                to: mountain.coordinate
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    Text(MountainProximityText.summary(proximity))
                    if quality == .reduced {
                        Text("目安")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(YamaColor.amber.opacity(0.18), in: Capsule())
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(quality == .good ? YamaColor.alpineTeal : YamaColor.amber)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    quality == .good
                        ? "現在地から\(MountainProximityText.summary(proximity))"
                        : "現在地から\(MountainProximityText.summary(proximity))、位置精度が低いため目安"
                )
                .accessibilityIdentifier("mountain-detail-proximity")
            } else {
                unavailableLocationSummary("距離・方角を計算できません")
            }
        case .loading:
            unavailableLocationSummary("距離・方角を確認中")
        case .notRequested:
            unavailableLocationSummary("距離・方角は未取得")
        case .denied, .restricted, .insufficientAccuracy, .unavailable:
            unavailableLocationSummary("距離・方角を利用できません")
        }
    }

    private func unavailableLocationSummary(_ message: String) -> some View {
        Label(message, systemImage: "location.slash")
            .font(.caption)
            .foregroundStyle(YamaColor.secondaryText)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(record?.isSummited == true ? "登頂済み" : "未登頂", systemImage: record?.isSummited == true ? "flag.fill" : "flag")
                    .font(.headline)
                    .foregroundStyle(record?.isSummited == true ? YamaColor.moss : YamaColor.secondaryText)
                Spacer()
                Button(record?.isSummited == true ? "取り消す" : "登頂済みにする") {
                    toggleSummited()
                }
                .font(.subheadline.weight(.semibold))
            }
            Divider().overlay(.white.opacity(0.1))
            Label("登山可否は判定しません。最新の公式情報と現地状況を確認してください。", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 18)
    }

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                YamaSectionHeader(title: "山頂付近の天気")
                Spacer()
                Text("未取得")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YamaColor.amber)
            }

            HStack(spacing: 12) {
                unavailableWeatherCard(title: "現在・予報", icon: "cloud.sun")
                unavailableWeatherCard(title: "時間ごと", icon: "chart.xyaxis.line")
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("前日の気象サマリー", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Text("前日のWeatherKit日別サマリーは、現在・予報と分けて表示します。対象日、提供元、取得日時を確認できます。")
                    .font(.footnote)
                    .foregroundStyle(YamaColor.secondaryText)
                Text("前日の情報を取得できません")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.amber)
            }
            .padding(16)
            .background(YamaColor.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 18)
    }

    private func unavailableWeatherCard(title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(YamaColor.alpineTeal)
            Text(title).font(.headline)
            Text("データ未取得").font(.caption).foregroundStyle(YamaColor.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(16)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var facilitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            facilityEmptySection(
                title: "山小屋",
                emptyTitle: "山小屋情報を準備中",
                message: "営業期間や予約方法を、公式情報と最終確認日付きで掲載します。",
                icon: "house.lodge"
            )
            facilityEmptySection(
                title: "登山口",
                emptyTitle: "登山口情報を準備中",
                message: "登山口、駐車場、公共交通の一次情報を確認後に掲載します。",
                icon: "figure.hiking"
            )
        }
        .padding(.horizontal, 18)
    }

    private func facilityEmptySection(
        title: String,
        emptyTitle: String,
        message: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: title)
            YamaEmptyCard(
                title: emptyTitle,
                message: message,
                systemImage: icon
            )
        }
    }

    private var accessSection: some View {
        Button(action: {}) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("登山口へのアクセス")
                        .font(.headline)
                    Text("出発地と地図アプリを毎回選びます")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(YamaColor.forest, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "山ノート", subtitle: "このiPhone内に保存")
            HStack(spacing: 10) {
                notePhase("行く前", icon: "backpack")
                notePhase("山行中", icon: "figure.hiking")
                notePhase("行ったあと", icon: "checkmark.seal")
            }
            Button("山ノートを開く") {
                _ = ensureRecord()
                isNotesPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(YamaColor.forest)
            .controlSize(.large)
        }
        .padding(.horizontal, 18)
    }

    private func notePhase(_ title: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(YamaColor.moss)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(YamaColor.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @discardableResult
    private func ensureRecord() -> UserMountainRecord {
        if let record { return record }
        let newRecord = UserMountainRecord(mountainID: mountain.id)
        modelContext.insert(newRecord)
        return newRecord
    }

    private func markViewed() {
        ensureRecord().lastViewedAt = .now
    }

    private func toggleFavorite() {
        let record = ensureRecord()
        record.isFavorite.toggle()
    }

    private func toggleSummited() {
        let record = ensureRecord()
        record.isSummited.toggle()
        record.summitedAt = record.isSummited ? .now : nil
    }
}

private struct MountainNotesView: View {
    let mountain: Mountain
    @Bindable var record: UserMountainRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("行く前") { TextEditor(text: $record.beforeNote).frame(minHeight: 100) }
                Section("山行中") { TextEditor(text: $record.duringNote).frame(minHeight: 100) }
                Section("行ったあと") { TextEditor(text: $record.afterNote).frame(minHeight: 100) }
                Section {
                    Text("山ノートはこのiPhone内に保存されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(mountain.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
    }
}
