import Foundation
import SwiftUI

struct MountainDaylightSection: View {
    let daylight: MountainDaylight?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            YamaSectionHeader(title: "日の出・日の入り", subtitle: "山頂座標・今日")
            if let daylight {
                HStack(spacing: 12) {
                    timeColumn(
                        title: "日の出",
                        date: daylight.sunrise,
                        systemImage: "sunrise.fill",
                        color: YamaColor.amber
                    )
                    timeColumn(
                        title: "日の入り",
                        date: daylight.sunset,
                        systemImage: "sunset.fill",
                        color: YamaColor.alpineTeal
                    )
                }
                Text("地形による遮りや現地の明るさは反映していません。行動判断には余裕を持ってください。")
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
            } else {
                YamaEmptyCard(
                    title: "時刻を計算できません",
                    message: "山頂座標または日付を確認してください。",
                    systemImage: "sun.horizon"
                )
            }
        }
        .accessibilityIdentifier("mountain-daylight-section")
    }

    private func timeColumn(
        title: String,
        date: Date,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(YamaColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            YamaColor.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}
