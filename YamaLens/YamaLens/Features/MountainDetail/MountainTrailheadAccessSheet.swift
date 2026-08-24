import SwiftUI

struct MountainTrailheadAccessSheet: View {
    let guide: TrailheadAccessGuide
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("externalMaps.application") private var mapApplicationRawValue = ExternalMapApplication.appleMaps.rawValue
    @State private var accessMode: TrailheadAccessMode = .publicTransport
    @State private var pendingMapSearch: ExternalMapSearch?
    @State private var isResolvingNearbySearch = false
    @State private var selectedStop: MountainPointOfInterest?
    @State private var routeDestination: MountainRouteDestination?
    private let nearbySearchCenterResolver: any NearbySearchCenterResolving

    init(
        guide: TrailheadAccessGuide,
        nearbySearchCenterResolver: any NearbySearchCenterResolving = MapKitNearbySearchCenterResolver()
    ) {
        self.guide = guide
        self.nearbySearchCenterResolver = nearbySearchCenterResolver
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identityHeader
                accessModePicker
                accessPointsSection
                representativeStopsSection
                nearbySearchSection
                privacyNotice
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(TopographicBackground())
        .navigationTitle("登山口へのアクセス")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("閉じる")
                .accessibilityIdentifier("trailhead-access-close-button")
            }
        }
        .confirmationDialog(
            "地図アプリを選択",
            isPresented: Binding(
                get: { pendingMapSearch != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingMapSearch = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingMapSearch {
                Button("Appleマップ") {
                    openAppleMaps(search: pendingMapSearch)
                }
                if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
                    Button("Google Maps") {
                        openGoogleMaps(search: pendingMapSearch)
                    }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(item: $selectedStop) { point in
            NavigationStack {
                MountainFacilityDetailSheet(point: point)
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $routeDestination) { destination in
            NavigationStack {
                MountainRouteSheet(destination: destination)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("trailhead-access-sheet")
        .preferredColorScheme(.dark)
    }

    private var identityHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.hiking")
                .font(.title2.weight(.semibold))
                .foregroundStyle(YamaColor.alpineTeal)
                .frame(width: 58, height: 58)
                .background(YamaColor.alpineTeal.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.trailhead.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(YamaColor.primaryText)
                Text("出発地は地図アプリで選べます")
                    .font(.subheadline)
                    .foregroundStyle(YamaColor.secondaryText)
            }
        }
    }

    private var accessModePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(
                title: "アクセス手段",
                subtitle: "使う手段を選ぶと、必要な情報だけを表示します"
            )

            Picker("アクセス手段", selection: $accessMode) {
                if hasPublicTransportAccess {
                    Label("公共交通", systemImage: "bus.fill")
                        .tag(TrailheadAccessMode.publicTransport)
                }

                if hasCarAccess {
                    Label("車", systemImage: "car.fill")
                        .tag(TrailheadAccessMode.car)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("trailhead-access-mode-picker")
            .onAppear {
                if !hasPublicTransportAccess, hasCarAccess {
                    accessMode = .car
                }
            }
        }
    }

    @ViewBuilder
    private var accessPointsSection: some View {
        if !selectedAccessPoints.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                YamaSectionHeader(
                    title: accessMode.sectionTitle,
                    subtitle: accessMode.sectionSubtitle
                )
                VStack(spacing: 0) {
                    ForEach(Array(selectedAccessPoints.enumerated()), id: \.element.id) { index, point in
                        accessPointRow(point)
                        if index < selectedAccessPoints.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.10))
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    guard let point = selectedAccessPoints.first else { return }
                    routeDestination = MountainRouteDestination(
                        point: point,
                        suggestedMode: accessMode.travelMode
                    )
                } label: {
                    Label(accessMode.mapButtonTitle, systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(YamaColor.forest)
                .accessibilityIdentifier("trailhead-open-maps-button")
            }
        } else {
            YamaEmptyCard(
                title: accessMode.emptyTitle,
                message: "公式サイトや地図アプリで最新情報をご確認ください。",
                systemImage: accessMode.systemImage
            )
        }
    }

    private var selectedAccessPoints: [MountainPointOfInterest] {
        guide.accessPoints.filter { accessMode.includes($0.type) }
    }

    private var hasPublicTransportAccess: Bool {
        guide.accessPoints.contains { TrailheadAccessMode.publicTransport.includes($0.type) }
    }

    private var hasCarAccess: Bool {
        guide.accessPoints.contains { TrailheadAccessMode.car.includes($0.type) }
    }

    private func accessPointRow(_ point: MountainPointOfInterest) -> some View {
        Button {
            routeDestination = MountainRouteDestination(
                point: point,
                suggestedMode: accessMode.travelMode
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: point.type.systemImage)
                    .foregroundStyle(YamaColor.alpineTeal)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.name)
                    Text(point.type.displayName)
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(YamaColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(YamaColor.primaryText)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.name)、\(point.type.displayName)を地図アプリで開く")
    }

    @ViewBuilder
    private var representativeStopsSection: some View {
        if !representativeHotSprings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                YamaSectionHeader(
                    title: "代表的な温泉",
                    subtitle: "営業情報は公式サイトで確認"
                )
                VStack(spacing: 0) {
                    ForEach(Array(representativeHotSprings.enumerated()), id: \.element.id) { index, point in
                        Button {
                            selectedStop = point
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: point.type.systemImage)
                                    .foregroundStyle(YamaColor.alpineTeal)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(point.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(YamaColor.primaryText)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(YamaColor.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(point.name)の公式情報を確認")
                        if index < representativeHotSprings.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.10))
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var representativeHotSprings: [MountainPointOfInterest] {
        guide.accessPoints.filter { $0.type == .hotSpring }
    }

    private var nearbySearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(
                title: "立ち寄り",
                subtitle: "店舗情報は地図アプリで最新情報を確認"
            )
            VStack(spacing: 0) {
                ForEach(Array(guide.nearbySearchAreas.enumerated()), id: \.element.id) { index, area in
                    nearbySearchRow(area)
                    if index < guide.nearbySearchAreas.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.10))
                            .padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func nearbySearchRow(_ area: NearbySearchArea) -> some View {
        Menu {
            Button("コンビニを探す") {
                openNearbySearch(query: "コンビニ", around: area)
            }
            Button("食事を探す") {
                openNearbySearch(query: "食事", around: area)
            }
            Button("温泉を探す") {
                openNearbySearch(query: "温泉", around: area)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(YamaColor.alpineTeal)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(area.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.primaryText)
                Spacer(minLength: 12)
                Text("探す")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.alpineTeal)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(YamaColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .disabled(isResolvingNearbySearch)
        .accessibilityLabel("\(area.name)周辺を探す")
        .accessibilityHint("コンビニ、食事、温泉を選べます")
    }

    private var privacyNotice: some View {
        Label(
            "現在地の利用は地図アプリ側で選べます。YamaLensはこの操作のために位置情報を取得しません。",
            systemImage: "hand.raised")
        .font(.footnote)
        .foregroundStyle(YamaColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openNearbySearch(query: String, around area: NearbySearchArea) {
        isResolvingNearbySearch = true
        Task {
            let center = await nearbySearchCenterResolver.resolveCenter(for: area.name)
            await MainActor.run {
                isResolvingNearbySearch = false
                openMaps(ExternalMapSearch(query: query, center: center))
            }
        }
    }

    private func openMaps(query: String) {
        openMaps(ExternalMapSearch(query: query, center: nil))
    }

    private func openMaps(_ search: ExternalMapSearch) {
        switch ExternalMapApplication(rawValue: mapApplicationRawValue) ?? .appleMaps {
        case .appleMaps:
            openAppleMaps(search: search)
        case .googleMaps:
            if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
                openGoogleMaps(search: search)
            } else {
                openAppleMaps(search: search)
            }
        case .askEveryTime:
            pendingMapSearch = search
        }
    }

    private func openAppleMaps(search: ExternalMapSearch) {
        guard let url = ExternalMapURLBuilder.appleMapsURL(for: search) else { return }
        openURL(url)
    }

    private func openGoogleMaps(search: ExternalMapSearch) {
        guard let url = ExternalMapURLBuilder.googleMapsURL(for: search) else { return }
        openURL(url)
    }
}

private enum TrailheadAccessMode: Hashable {
    case publicTransport
    case car

    var sectionTitle: String {
        switch self {
        case .publicTransport: "公共交通で行く"
        case .car: "車で行く"
        }
    }

    var sectionSubtitle: String {
        switch self {
        case .publicTransport: "バス停・ケーブルカーの場所を地図で確認できます"
        case .car: "駐車場の場所を地図で確認できます"
        }
    }

    var mapButtonTitle: String {
        switch self {
        case .publicTransport: "公共交通の入口を地図で開く"
        case .car: "駐車場を地図で開く"
        }
    }

    var travelMode: ExternalMapTravelMode {
        switch self {
        case .publicTransport: .publicTransport
        case .car: .driving
        }
    }

    var emptyTitle: String {
        switch self {
        case .publicTransport: "公共交通の情報はまだありません"
        case .car: "駐車場の情報はまだありません"
        }
    }

    var systemImage: String {
        switch self {
        case .publicTransport: "bus"
        case .car: "car"
        }
    }

    func includes(_ type: MountainPointOfInterestType) -> Bool {
        switch self {
        case .publicTransport: type == .publicTransport || type == .cableway
        case .car: type == .parking
        }
    }
}
