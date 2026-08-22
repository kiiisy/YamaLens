import Foundation
import SwiftUI

struct MountainFacilitySection: View {
    let pointsOfInterest: [MountainPointOfInterest]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if pointsOfInterest.isEmpty {
                emptyState
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        YamaSectionHeader(title: group.title)
                        ForEach(group.points) { point in
                            facilityCard(point)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("mountain-facility-section")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "山小屋・アクセス情報")
            YamaEmptyCard(
                title: "公式情報を確認中",
                message: "この山に紐づく施設情報はまだ登録されていません。推測値は表示しません。",
                systemImage: "building.2"
            )
        }
    }

    private var groups: [FacilityGroup] {
        [
            FacilityGroup(
                id: "mountain-huts",
                title: "山小屋",
                points: pointsOfInterest.filter { $0.type == .mountainHut }
            ),
            FacilityGroup(
                id: "trailhead-access",
                title: "登山口・交通",
                points: pointsOfInterest.filter {
                    [.trailhead, .parking, .publicTransport, .cableway].contains($0.type)
                }
            ),
            FacilityGroup(
                id: "nearby",
                title: "立ち寄り情報",
                points: pointsOfInterest.filter { $0.type == .hotSpring }
            ),
        ]
        .filter { !$0.points.isEmpty }
    }

    private func facilityCard(_ point: MountainPointOfInterest) -> some View {
        Link(destination: point.officialURL) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: point.type.systemImage)
                    .font(.headline)
                    .foregroundStyle(YamaColor.alpineTeal)
                    .frame(width: 36, height: 36)
                    .background(YamaColor.alpineTeal.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(point.name)
                        .font(.headline)
                        .foregroundStyle(YamaColor.primaryText)
                    Text(point.summary)
                        .font(.subheadline)
                        .foregroundStyle(YamaColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(
                        "\(point.sourceProvider)・確認 \(point.checkedAt.formatted(.dateTime.year().month().day()))",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption)
                    .foregroundStyle(YamaColor.moss)
                }

                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                YamaColor.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(point.name)、\(point.type.displayName)、提供元 \(point.sourceProvider)")
        .accessibilityHint("公式ページを開きます")
        .accessibilityIdentifier("facility-\(point.id)")
    }
}

private struct FacilityGroup: Identifiable {
    let id: String
    let title: String
    let points: [MountainPointOfInterest]
}

private extension MountainPointOfInterestType {
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
