import SwiftUI

struct MountainFacilityDetailSheet: View {
    let point: MountainPointOfInterest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("externalBrowser.application") private var browserApplicationRawValue = ExternalBrowserApplication.defaultBrowser.rawValue
    @State private var showsBrowserChoice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identityHeader
                summaryCard
                sourceCard
                officialInformationNotice
                officialLink
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(TopographicBackground())
        .navigationTitle("施設情報")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("閉じる")
                .accessibilityIdentifier("facility-detail-close-button")
            }
        }
        .confirmationDialog(
            "ブラウザを選択",
            isPresented: $showsBrowserChoice,
            titleVisibility: .visible
        ) {
            Button("既定のブラウザ") {
                openURL(point.officialURL)
            }
            if ExternalBrowserApplicationAvailability.isChromeAvailable {
                Button("Chrome") {
                    openInChrome()
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .accessibilityIdentifier("facility-detail-sheet")
        .preferredColorScheme(.dark)
    }

    private var identityHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: point.type.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(YamaColor.alpineTeal)
                .frame(width: 58, height: 58)
                .background(YamaColor.alpineTeal.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(point.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(YamaColor.primaryText)
                Text(point.type.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YamaColor.alpineTeal)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("facility-detail-title")
    }

    private var summaryCard: some View {
        Text(point.summary)
            .font(.body)
            .foregroundStyle(YamaColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                YamaColor.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }

    private var sourceCard: some View {
        VStack(spacing: 0) {
            informationRow(title: "提供元", value: point.sourceProvider, systemImage: "building.columns")
            Divider()
                .overlay(.white.opacity(0.10))
                .padding(.leading, 48)
            informationRow(
                title: "最終確認",
                value: point.checkedAt.formatted(.dateTime.year().month().day()),
                systemImage: "checkmark.seal"
            )
        }
        .padding(.horizontal, 16)
        .background(
            YamaColor.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func informationRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(YamaColor.alpineTeal)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(YamaColor.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(YamaColor.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }

    private var officialInformationNotice: some View {
        Label(
            "営業時間・料金・運行状況などは変わる場合があります。最新情報は公式サイトで確認してください。",
            systemImage: "info.circle"
        )
        .font(.footnote)
        .foregroundStyle(YamaColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var officialLink: some View {
        Button {
            openOfficialWebsite()
        } label: {
            Label("公式サイトを開く", systemImage: "safari")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(YamaColor.forest)
        .accessibilityLabel("\(point.sourceProvider)の公式サイトをブラウザで開く")
        .accessibilityIdentifier("facility-official-link")
    }

    private func openOfficialWebsite() {
        switch ExternalBrowserApplication(rawValue: browserApplicationRawValue) ?? .defaultBrowser {
        case .defaultBrowser:
            openURL(point.officialURL)
        case .chrome:
            openInChrome()
        case .askEveryTime:
            showsBrowserChoice = true
        }
    }

    private func openInChrome() {
        guard
            ExternalBrowserApplicationAvailability.isChromeAvailable,
            let chromeURL = ExternalBrowserURLBuilder.chromeURL(for: point.officialURL)
        else {
            openURL(point.officialURL)
            return
        }
        openURL(chromeURL)
    }
}
