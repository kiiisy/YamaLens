import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum MountainDetailDismissalStyle {
    case zoomToSource
    case dragged
}

struct MountainDetailView: View {
    let mountain: Mountain
    private let currentLocationState: CurrentLocationState
    private let proximityCalculator: MountainProximityCalculator
    private let pointsOfInterest: [MountainPointOfInterest]
    private let trailheadAccessGuides: [TrailheadAccessGuide]
    private let daylight: MountainDaylight?
    private let onClose: ((MountainDetailDismissalStyle) -> Void)?
    private let overlayTopInset: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [UserMountainRecord]
    @State private var selectedNotePhase: MountainNotePhase?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoSelectionError: String?
    @State private var dismissDragDistance: CGFloat = 0
    @State private var isDraggingToDismiss = false
    @State private var scrollOffset: CGFloat = 0
    @State private var weatherModel: MountainWeatherScreenModel

    init(
        mountain: Mountain,
        weatherRepository: any MountainWeatherRepository,
        pointOfInterestRepository: any MountainPointOfInterestRepository,
        currentLocationState: CurrentLocationState = .notRequested,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator(),
        daylightCalculator: MountainDaylightCalculator = MountainDaylightCalculator(),
        daylightDate: Date = .now,
        daylightTimeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt,
        overlayTopInset: CGFloat? = nil,
        onClose: ((MountainDetailDismissalStyle) -> Void)? = nil
    ) {
        self.mountain = mountain
        self.currentLocationState = currentLocationState
        self.proximityCalculator = proximityCalculator
        pointsOfInterest = pointOfInterestRepository.fetchPointsOfInterest(for: mountain.id)
        trailheadAccessGuides = pointOfInterestRepository.fetchTrailheadAccessGuides(for: mountain.id)
        daylight = daylightCalculator.daylight(
            on: daylightDate,
            at: mountain.coordinate,
            timeZone: daylightTimeZone
        )
        self.overlayTopInset = overlayTopInset
        self.onClose = onClose
        _weatherModel = State(
            initialValue: MountainWeatherScreenModel(repository: weatherRepository)
        )
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
                        MountainDaylightSection(daylight: daylight)
                            .padding(.horizontal, 18)
                        MountainFacilitySection(
                            mountainName: mountain.name,
                            pointsOfInterest: pointsOfInterest,
                            trailheadAccessGuides: trailheadAccessGuides
                        )
                            .padding(.horizontal, 18)
                        externalServiceSection
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
        .sheet(item: $selectedNotePhase) { phase in
            if let record {
                MountainNotesView(mountain: mountain, record: record, phase: phase)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await saveSelectedPhoto(item) }
        }
        .alert("写真を設定できません", isPresented: Binding(
            get: { photoSelectionError != nil },
            set: { isPresented in
                if !isPresented { photoSelectionError = nil }
            }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(photoSelectionError ?? "")
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

    @ViewBuilder
    private var hero: some View {
        let hasCustomHeroImage = record?.heroImageData != nil

        heroArtwork
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
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(
                        hasCustomHeroImage ? "写真を変更" : "写真を設定",
                        systemImage: hasCustomHeroImage ? "photo.badge.arrow.down" : "photo.badge.plus"
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(hasCustomHeroImage ? "山の写真を変更" : "山の写真を設定")
                .accessibilityIdentifier("mountain-hero-photo-picker")
                .padding(.trailing, 18)
                .padding(.bottom, 92)
            }
            .contextMenu {
                if record?.heroImageData != nil {
                    Button("写真を削除", role: .destructive) {
                        ensureRecord().heroImageData = nil
                    }
                }
            }
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let data = record?.heroImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 350)
                .clipped()
                .accessibilityHidden(true)
        } else {
            MountainArtworkView(mountain: mountain, height: 350)
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
        MountainWeatherSection(mountain: mountain, model: weatherModel)
        .padding(.horizontal, 18)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "山ノート", subtitle: "このiPhone内に保存")
            HStack(spacing: 10) {
                notePhase(.before, icon: "backpack")
                notePhase(.during, icon: "figure.hiking")
                notePhase(.after, icon: "checkmark.seal")
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var externalServiceSection: some View {
        if let yamapURL = mountain.yamapURL {
            VStack(alignment: .leading, spacing: 12) {
                YamaSectionHeader(
                    title: "外部サービス",
                    subtitle: "対象の山を別のアプリで確認"
                )
                Link(destination: yamapURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "map")
                            .foregroundStyle(YamaColor.moss)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YAMAPで見る")
                                .font(.headline)
                                .foregroundStyle(YamaColor.primaryText)
                            Text("山ページから登山計画を作成できます")
                                .font(.caption)
                                .foregroundStyle(YamaColor.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(YamaColor.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(
                        YamaColor.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("YAMAPで\(mountain.name)を見る")
                .accessibilityHint("YAMAPがインストール済みならアプリ、未インストールならWebで開きます")
                .accessibilityIdentifier("mountain-yamap-link")
                Text("外部サービスの情報・計画はYamaLensの安全判断ではありません。")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
            }
            .padding(.horizontal, 18)
        }
    }

    private func notePhase(_ phase: MountainNotePhase, icon: String) -> some View {
        Button {
            _ = ensureRecord()
            selectedNotePhase = phase
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(YamaColor.moss)
                Text(phase.title).font(.caption.weight(.semibold)).foregroundStyle(YamaColor.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Text(notePreview(for: phase))
                .font(.subheadline)
        } preview: {
            NotePreviewCard(phase: phase, text: noteText(for: phase))
        }
        .accessibilityLabel("山ノート、\(phase.title)")
        .accessibilityHint("タップで入力します。長押しで保存済みメモをプレビューします")
        .accessibilityIdentifier("mountain-note-\(phase.rawValue)")
    }

    private func noteText(for phase: MountainNotePhase) -> String {
        guard let record else { return "" }
        switch phase {
        case .before: return record.beforeNote
        case .during: return record.duringNote
        case .after: return record.afterNote
        }
    }

    private func notePreview(for phase: MountainNotePhase) -> String {
        let text = noteText(for: phase).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "\(phase.title)のメモはまだありません" : text
    }

    private func saveSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoSelectionError = "選択した写真を読み込めませんでした。別の写真を選んでください。"
                return
            }
            guard let image = UIImage(data: data), let compressedData = image.yamaLensHeroImageData else {
                photoSelectionError = "この形式の写真は設定できません。別の写真を選んでください。"
                return
            }
            ensureRecord().heroImageData = compressedData
        } catch {
            photoSelectionError = "写真の読み込みに失敗しました。もう一度お試しください。"
        }
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

private enum MountainNotePhase: String, Identifiable {
    case before
    case during
    case after

    var id: String { rawValue }

    var title: String {
        switch self {
        case .before: "行く前"
        case .during: "山行中"
        case .after: "行ったあと"
        }
    }
}

private struct NotePreviewCard: View {
    let phase: MountainNotePhase
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phase.title)
                .font(.headline)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "まだメモはありません" : text)
                .font(.subheadline)
                .lineLimit(6)
        }
        .padding(18)
    }
}

private struct MountainNotesView: View {
    let mountain: Mountain
    @Bindable var record: UserMountainRecord
    let phase: MountainNotePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(phase.title) {
                    TextEditor(text: noteBinding)
                        .frame(minHeight: 180)
                }
                Section {
                    Text("山ノートはこのiPhone内に保存されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(mountain.name)・\(phase.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
    }

    private var noteBinding: Binding<String> {
        switch phase {
        case .before: $record.beforeNote
        case .during: $record.duringNote
        case .after: $record.afterNote
        }
    }
}

private extension UIImage {
    var yamaLensHeroImageData: Data? {
        let maximumDimension: CGFloat = 1_600
        let longestSide = max(size.width, size.height)
        let targetSize: CGSize
        if longestSide > maximumDimension {
            let scale = maximumDimension / longestSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}
