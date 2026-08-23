import Foundation
import SwiftUI

struct MountainFacilitySection: View {
    let mountainName: String
    let pointsOfInterest: [MountainPointOfInterest]
    let trailheadAccessGuides: [TrailheadAccessGuide]
    @Environment(\.openURL) private var openURL
    @AppStorage("externalMaps.application") private var mapApplicationRawValue = ExternalMapApplication.appleMaps.rawValue
    @State private var selectedPoint: MountainPointOfInterest?
    @State private var selectedTrailhead: TrailheadAccessGuide?
    @State private var pendingMapSearch: ExternalMapSearch?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            YamaSectionHeader(
                title: "施設情報",
                subtitle: mountainHuts.isEmpty && trailheadAccessGuides.isEmpty
                    ? nil
                    : "山小屋と登山口を確認"
            )
            .accessibilityIdentifier("mountain-facility-section")

            if mountainHuts.isEmpty && trailheadAccessGuides.isEmpty {
                emptyState
            } else {
                if !mountainHuts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        YamaSectionHeader(title: "山小屋")
                        facilityCards
                    }
                }

                if !trailheadAccessGuides.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        YamaSectionHeader(
                            title: "登山口",
                            subtitle: "選ぶとアクセスと周辺検索を確認"
                        )
                        trailheadCards
                    }
                }
            }
        }
        .sheet(item: $selectedPoint) { point in
            NavigationStack {
                MountainFacilityDetailSheet(point: point)
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedTrailhead) { guide in
            NavigationStack {
                MountainTrailheadAccessSheet(guide: guide)
            }
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
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
                Button("Appleマップ") { openAppleMaps(search: pendingMapSearch) }
                if ExternalMapApplicationAvailability.isGoogleMapsAvailable {
                    Button("Google Maps") { openGoogleMaps(search: pendingMapSearch) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            YamaEmptyCard(
                title: "公式情報を確認中",
                message: "この山に紐づく施設情報はまだ登録されていません。推測値は表示しません。",
                systemImage: "building.2"
            )

            Button {
                openMaps(query: mountainName)
            } label: {
                Label("地図で\(mountainName)を開く", systemImage: "map")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(YamaColor.alpineTeal)
            .accessibilityIdentifier("mountain-generic-map-button")
        }
    }

    private var mountainHuts: [MountainPointOfInterest] {
        pointsOfInterest.filter { $0.type == .mountainHut }
    }

    @ViewBuilder
    private var facilityCards: some View {
        if mountainHuts.count == 1, let point = mountainHuts.first {
            facilityCard(point)
        } else {
            LazyVGrid(columns: twoColumnLayout, spacing: 12) {
                ForEach(mountainHuts) { point in
                    facilityCard(point)
                }
            }
        }
    }

    @ViewBuilder
    private var trailheadCards: some View {
        if trailheadAccessGuides.count == 1, let guide = trailheadAccessGuides.first {
            trailheadCard(guide)
        } else {
            LazyVGrid(columns: twoColumnLayout, spacing: 12) {
                ForEach(trailheadAccessGuides) { guide in
                    trailheadCard(guide)
                }
            }
        }
    }

    private var twoColumnLayout: [GridItem] {
        [
            GridItem(.flexible(minimum: 140), spacing: 12),
            GridItem(.flexible(minimum: 140), spacing: 12),
        ]
    }

    private func facilityCard(_ point: MountainPointOfInterest) -> some View {
        Button {
            selectedPoint = point
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: point.type.systemImage)
                    .font(.headline)
                    .foregroundStyle(YamaColor.alpineTeal)
                    .frame(width: 40, height: 40)
                    .background(YamaColor.alpineTeal.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(point.name)
                        .font(.headline)
                        .foregroundStyle(YamaColor.primaryText)
                    Text("確認 \(point.checkedAt.formatted(.dateTime.year().month().day()))")
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }

                if mountainHuts.count == 1 {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YamaColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                YamaColor.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.name)、\(point.type.displayName)、提供元 \(point.sourceProvider)")
        .accessibilityHint("施設の詳細を表示します")
        .accessibilityIdentifier("facility-row-\(point.id)")
    }

    private func trailheadCard(_ guide: TrailheadAccessGuide) -> some View {
        Button {
            selectedTrailhead = guide
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "figure.hiking")
                    .font(.headline)
                    .foregroundStyle(YamaColor.alpineTeal)
                    .frame(width: 40, height: 40)
                    .background(YamaColor.alpineTeal.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(guide.trailhead.name)
                        .font(.headline)
                        .foregroundStyle(YamaColor.primaryText)
                    Text(accessSummary(for: guide))
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }

                Text("アクセスを見る")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.alpineTeal)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(guide.trailhead.name)、\(accessSummary(for: guide))")
        .accessibilityHint("アクセスと立ち寄り検索を表示します")
        .accessibilityIdentifier("trailhead-row-\(guide.id)")
    }

    private func accessSummary(for guide: TrailheadAccessGuide) -> String {
        let labels = guide.accessPoints.map(\.type.displayName)
        return labels.isEmpty ? "アクセス情報を確認" : labels.joined(separator: "・")
    }

    private func openMaps(query: String) {
        let search = ExternalMapSearch(query: query, center: nil)
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

extension MountainPointOfInterestType {
    var displayName: String {
        switch self {
        case .mountainHut: "山小屋"
        case .trailhead: "登山口"
        case .parking: "駐車場"
        case .publicTransport: "公共交通"
        case .cableway: "ケーブルカー"
        case .hotSpring: "温泉"
        }
    }

    var systemImage: String {
        switch self {
        case .mountainHut: "house.lodge.fill"
        case .trailhead: "figure.hiking"
        case .parking: "parkingsign.circle.fill"
        case .publicTransport: "bus.fill"
        case .cableway: "tram.fill"
        case .hotSpring: "drop.fill"
        }
    }
}
