import SwiftUI

struct MountainWeatherSection: View {
    let mountain: Mountain
    let model: MountainWeatherScreenModel
    private let evaluator = MountainWeatherEvaluator()
    @State private var isDetailPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isDetailPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    summaryHeader
                    summaryContent
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    YamaColor.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("時間別予報や前日の気象サマリーを表示します")
            .accessibilityIdentifier("weather-summary-card")

            if case .loaded(let content) = model.forecastState {
                sourceRow(content)
            }
        }
        .task(id: mountain.id) {
            await model.load(for: mountain)
        }
        .sheet(isPresented: $isDetailPresented) {
            NavigationStack {
                MountainWeatherDetailView(mountain: mountain, model: model)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("山頂付近の天気")
                .font(.title3.weight(.bold))
                .foregroundStyle(YamaColor.primaryText)
            Spacer(minLength: 8)
            Text("詳しく見る")
                .font(.caption.weight(.semibold))
                .foregroundStyle(YamaColor.alpineTeal)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(YamaColor.alpineTeal)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        switch model.forecastState {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("天気を確認中")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minHeight: 84)
        case .unavailable(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Label("天気を取得できません", systemImage: "cloud.slash")
                    .font(.headline)
                Text(MountainWeatherPresentation.failureText(failure))
                    .font(.caption)
                    .foregroundStyle(YamaColor.secondaryText)
                Text("タップして再試行や詳細を確認")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YamaColor.alpineTeal)
            }
            .frame(minHeight: 84)
        case .loaded(let content):
            loadedSummary(content)
        }
    }

    private func loadedSummary(
        _ content: MountainWeatherForecastContent
    ) -> some View {
        let forecast = content.forecast
        let warnings = evaluator.warnings(for: forecast, now: .now)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: forecast.current.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 42))
                    .frame(width: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(MountainWeatherPresentation.temperature(forecast.current.temperatureCelsius))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(MountainWeatherPresentation.conditionName(forecast.current.conditionCode))
                        .font(.subheadline.weight(.semibold))
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 7) {
                    Label(
                        "\(MountainWeatherPresentation.windDirectionName(forecast.current.windDirectionCode)) \(MountainWeatherPresentation.windSpeed(forecast.current.windSpeedMetersPerSecond))",
                        systemImage: "wind"
                    )
                    if let firstHour = forecast.hourly.first {
                        Label(
                            MountainWeatherPresentation.precipitation(firstHour.precipitationChance),
                            systemImage: "drop.fill"
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(YamaColor.secondaryText)
            }

            if !forecast.hourly.isEmpty {
                hourlyPreview(forecast.hourly)
            }

            if let warning = warnings.first {
                Label(warning.title, systemImage: MountainWeatherPresentation.warningIcon(warning.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YamaColor.amber)
            }
        }
        .foregroundStyle(YamaColor.primaryText)
    }

    private func hourlyPreview(_ hours: [MountainHourlyWeather]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(hours.prefix(3).enumerated()), id: \.offset) { index, hour in
                if index > 0 {
                    Divider()
                        .overlay(.white.opacity(0.10))
                }
                VStack(spacing: 6) {
                    Text(hour.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(YamaColor.secondaryText)
                    Image(systemName: hour.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.title3)
                    Text(MountainWeatherPresentation.temperature(hour.temperatureCelsius))
                        .font(.subheadline.weight(.bold))
                    Text(MountainWeatherPresentation.precipitation(hour.precipitationChance))
                        .font(.caption2)
                        .foregroundStyle(YamaColor.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 92)
            }
        }
        .background(
            YamaColor.raisedSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func sourceRow(_ content: MountainWeatherForecastContent) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label(
                    MountainWeatherPresentation.freshnessText(content.freshness),
                    systemImage: MountainWeatherPresentation.freshnessIcon(content.freshness)
                )
                .foregroundStyle(content.freshness == .fresh ? YamaColor.moss : YamaColor.amber)
                Text("取得 \(content.forecast.retrievedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(YamaColor.secondaryText)
            }
            Spacer(minLength: 8)
            Link(destination: content.forecast.legalPageURL) {
                Label("提供元", systemImage: "arrow.up.right")
            }
            .foregroundStyle(YamaColor.alpineTeal)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
    }
}

private enum MountainWeatherPresentation {
    static func temperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "℃"
    }

    static func windSpeed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "m/s"
    }

    static func precipitation(_ chance: Double) -> String {
        (chance * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func conditionName(_ code: String) -> String {
        switch code {
        case "clear", "mostlyClear": "晴れ"
        case "partlyCloudy": "晴れ時々曇り"
        case "cloudy", "mostlyCloudy": "曇り"
        case "drizzle", "rain", "heavyRain", "sunShowers": "雨"
        case "snow", "heavySnow", "flurries", "sunFlurries", "blizzard": "雪"
        case "sleet", "wintryMix", "freezingDrizzle", "freezingRain": "みぞれ・凍結性降水"
        case "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms", "thunderstorms": "雷雨"
        case "foggy", "haze": "霧・もや"
        case "windy", "breezy": "風が強い"
        default: "気象情報"
        }
    }

    static func windDirectionName(_ code: String) -> String {
        switch code {
        case "north": "北"
        case "northNortheast": "北北東"
        case "northeast": "北東"
        case "eastNortheast": "東北東"
        case "east": "東"
        case "eastSoutheast": "東南東"
        case "southeast": "南東"
        case "southSoutheast": "南南東"
        case "south": "南"
        case "southSouthwest": "南南西"
        case "southwest": "南西"
        case "westSouthwest": "西南西"
        case "west": "西"
        case "westNorthwest": "西北西"
        case "northwest": "北西"
        case "northNorthwest": "北北西"
        default: "風"
        }
    }

    static func warningIcon(_ kind: MountainWeatherWarningKind) -> String {
        switch kind {
        case .strongWind, .severeWind: "wind"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snowOrIce: "snowflake"
        case .rapidTemperatureDrop: "thermometer.low"
        case .officialAlert: "exclamationmark.shield.fill"
        }
    }

    static func freshnessText(_ freshness: WeatherFreshness) -> String {
        switch freshness {
        case .fresh: "最新"
        case .refreshRecommended: "更新を推奨"
        case .stale: "古い情報"
        }
    }

    static func freshnessIcon(_ freshness: WeatherFreshness) -> String {
        freshness == .fresh ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
    }

    static func failureText(_ failure: MountainWeatherDisplayFailure) -> String {
        switch failure {
        case .permissionDenied: "気象サービスを利用できません"
        case .temporarilyUnavailable: "一時的に通信またはサービスを利用できません"
        case .invalidData: "受信した情報を確認できません"
        case .storageUnavailable: "端末内キャッシュを利用できません"
        }
    }
}

private struct MountainWeatherDetailView: View {
    let mountain: Mountain
    let model: MountainWeatherScreenModel
    private let evaluator = MountainWeatherEvaluator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TopographicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailIntro
                    forecastContent
                    previousDayContent
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("\(mountain.name)の天気")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("天気の詳細を閉じる")
            }
        }
        .task(id: mountain.id) {
            await model.load(for: mountain)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("weather-detail")
    }

    private var detailIntro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("標高 \(mountain.elevationMeters.formatted())m・山頂付近")
                        .font(.subheadline)
                        .foregroundStyle(YamaColor.secondaryText)
                    Text("予報は変わることがあります。取得時刻と提供元を確認してください。")
                        .font(.caption)
                        .foregroundStyle(YamaColor.secondaryText)
                }
                Spacer(minLength: 12)
                Button {
                    Task { await model.refresh(for: mountain) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(YamaColor.alpineTeal)
                .accessibilityLabel("天気を更新")
                .accessibilityIdentifier("weather-refresh-button")
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var forecastContent: some View {
        switch model.forecastState {
        case .loading:
            loadingCard(title: "現在・予報を取得中")
        case .unavailable(let failure):
            unavailableCard(title: "現在・予報を取得できません", failure: failure)
        case .loaded(let content):
            currentWeatherCard(content)
            let warnings = evaluator.warnings(for: content.forecast, now: .now)
            if !warnings.isEmpty {
                warningsCard(warnings)
            }
            hourlyForecast(content.forecast.hourly)
            sourceAndFreshness(
                sourceName: content.forecast.sourceName,
                legalPageURL: content.forecast.legalPageURL,
                retrievedAt: content.forecast.retrievedAt,
                freshness: content.freshness,
                isRefreshing: content.isRefreshing,
                updateFailure: content.updateFailure
            )
        }
    }

    private func currentWeatherCard(
        _ content: MountainWeatherForecastContent
    ) -> some View {
        let current = content.forecast.current
        return HStack(spacing: 18) {
            Image(systemName: current.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44))
                .frame(width: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text("現在")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(YamaColor.alpineTeal)
                Text(temperature(current.temperatureCelsius))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(YamaColor.primaryText)
                Text(conditionName(current.conditionCode))
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Label(
                    "体感 \(temperature(current.apparentTemperatureCelsius))",
                    systemImage: "thermometer.medium"
                )
                Label(
                    "\(windDirectionName(current.windDirectionCode)) \(windSpeed(current.windSpeedMetersPerSecond))",
                    systemImage: "wind"
                )
            }
            .font(.caption)
            .foregroundStyle(YamaColor.secondaryText)
        }
        .padding(18)
        .background(
            YamaColor.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weather-current-card")
    }

    private func warningsCard(_ warnings: [MountainWeatherWarning]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今後12時間の注意情報", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(YamaColor.amber)
            ForEach(warnings) { warning in
                VStack(alignment: .leading, spacing: 3) {
                    if let detailsURL = warning.detailsURL {
                        Link(destination: detailsURL) {
                            warningLabel(warning)
                        }
                    } else {
                        warningLabel(warning)
                    }
                }
            }
            Text("予報と警報の事実を示すもので、登山可否を判定するものではありません。")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            YamaColor.amber.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(YamaColor.amber.opacity(0.35))
        }
        .accessibilityIdentifier("weather-warnings")
    }

    private func warningLabel(_ warning: MountainWeatherWarning) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: warningIcon(warning.kind))
                .foregroundStyle(YamaColor.amber)
            Text(warningText(warning))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(YamaColor.primaryText)
            if warning.detailsURL != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
        }
    }

    private func hourlyForecast(_ hours: [MountainHourlyWeather]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("時間ごと")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(hours.prefix(8).enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 9) {
                            Text(hour.date.formatted(date: .omitted, time: .shortened))
                                .font(.caption.weight(.semibold))
                            Image(systemName: hour.symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.title2)
                            Text(temperature(hour.temperatureCelsius))
                                .font(.headline)
                            Label(
                                "\(Int((hour.precipitationChance * 100).rounded()))%",
                                systemImage: "drop.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(YamaColor.secondaryText)
                            Text(windSpeed(hour.windSpeedMetersPerSecond))
                                .font(.caption2)
                                .foregroundStyle(YamaColor.secondaryText)
                        }
                        .frame(minWidth: 92, minHeight: 132)
                        .padding(.vertical, 12)
                        .background(
                            YamaColor.raisedSurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var previousDayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("前日の気象サマリー（山頂付近）", systemImage: "calendar.badge.clock")
                .font(.headline)
            switch model.previousDayState {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("前日の情報を取得中")
                }
                .foregroundStyle(YamaColor.secondaryText)
            case .unavailable(let failure):
                failureLabel(failure, prefix: "前日の情報を取得できません")
            case .loaded(let content):
                previousDayValues(content.summary)
                statusLine(
                    retrievedAt: content.summary.retrievedAt,
                    isRefreshing: content.isRefreshing,
                    updateFailure: content.updateFailure
                )
                Link(destination: content.summary.legalPageURL) {
                    Label("\(content.summary.sourceName)の提供元・法的情報", systemImage: "arrow.up.right")
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            YamaColor.raisedSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityIdentifier("weather-previous-day-card")
    }

    private func previousDayValues(_ summary: PreviousDayWeatherSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.targetDate.formatted(date: .long, time: .omitted))
                .font(.subheadline.weight(.semibold))
            LabeledContent(
                "最高 / 最低",
                value: "\(optionalTemperature(summary.highTemperatureCelsius)) / \(optionalTemperature(summary.lowTemperatureCelsius))"
            )
            LabeledContent(
                "降水量",
                value: optionalAmount(summary.precipitationMillimeters, unit: "mm")
            )
            LabeledContent(
                "降雪量",
                value: optionalAmount(summary.snowfallCentimeters, unit: "cm")
            )
            Text("山頂付近の前日の日別サマリーです。実測値や登山道状態ではありません。")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
    }

    private func sourceAndFreshness(
        sourceName: String,
        legalPageURL: URL,
        retrievedAt: Date,
        freshness: WeatherFreshness,
        isRefreshing: Bool,
        updateFailure: MountainWeatherDisplayFailure?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(freshnessText(freshness), systemImage: freshnessIcon(freshness))
                .font(.caption.weight(.semibold))
                .foregroundStyle(freshness == .fresh ? YamaColor.moss : YamaColor.amber)
            statusLine(
                retrievedAt: retrievedAt,
                isRefreshing: isRefreshing,
                updateFailure: updateFailure
            )
            Link(destination: legalPageURL) {
                Label("\(sourceName)の提供元・法的情報", systemImage: "arrow.up.right")
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func statusLine(
        retrievedAt: Date,
        isRefreshing: Bool,
        updateFailure: MountainWeatherDisplayFailure?
    ) -> some View {
        if isRefreshing {
            Label("更新中", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        } else {
            Text("取得 \(retrievedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        if let updateFailure {
            failureLabel(updateFailure, prefix: "更新できなかったため、保存済み情報を表示中")
        }
    }

    private func loadingCard(title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func unavailableCard(
        title: String,
        failure: MountainWeatherDisplayFailure
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "cloud.slash")
                .font(.headline)
            failureLabel(failure, prefix: nil)
            Text("通信できる場所で更新してください。山の基本情報やメモは引き続き利用できます。")
                .font(.caption)
                .foregroundStyle(YamaColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(YamaColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weather-unavailable-card")
    }

    private func failureLabel(
        _ failure: MountainWeatherDisplayFailure,
        prefix: String?
    ) -> some View {
        Label(
            [prefix, failureText(failure)].compactMap { $0 }.joined(separator: "。"),
            systemImage: "exclamationmark.circle"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(YamaColor.amber)
    }

    private func warningText(_ warning: MountainWeatherWarning) -> String {
        var components = [warning.title]
        if let date = warning.date {
            components.append(date.formatted(date: .omitted, time: .shortened))
        }
        if let value = warning.value {
            let unit = warning.kind == .rapidTemperatureDrop ? "℃低下" : "m/s"
            components.append(value.formatted(.number.precision(.fractionLength(0...1))) + unit)
        }
        return components.joined(separator: "・")
    }

    private func warningIcon(_ kind: MountainWeatherWarningKind) -> String {
        switch kind {
        case .strongWind, .severeWind: "wind"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .snowOrIce: "snowflake"
        case .rapidTemperatureDrop: "thermometer.low"
        case .officialAlert: "exclamationmark.shield.fill"
        }
    }

    private func freshnessText(_ freshness: WeatherFreshness) -> String {
        switch freshness {
        case .fresh: "最新の取得から1時間以内"
        case .refreshRecommended: "取得から1時間超・更新推奨"
        case .stale: "取得から3時間超・古い情報"
        }
    }

    private func freshnessIcon(_ freshness: WeatherFreshness) -> String {
        freshness == .fresh ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
    }

    private func failureText(_ failure: MountainWeatherDisplayFailure) -> String {
        switch failure {
        case .permissionDenied: "WeatherKitを利用できません"
        case .temporarilyUnavailable: "一時的に通信またはサービスを利用できません"
        case .invalidData: "受信した情報を確認できません"
        case .storageUnavailable: "端末内キャッシュを利用できません"
        }
    }

    private func temperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "℃"
    }

    private func optionalTemperature(_ value: Double?) -> String {
        value.map(temperature) ?? "未取得"
    }

    private func optionalAmount(_ value: Double?, unit: String) -> String {
        guard let value else { return "未取得" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + unit
    }

    private func windSpeed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "m/s"
    }

    private func conditionName(_ code: String) -> String {
        switch code {
        case "clear", "mostlyClear": "晴れ"
        case "partlyCloudy": "晴れ時々曇り"
        case "cloudy", "mostlyCloudy": "曇り"
        case "drizzle", "rain", "heavyRain", "sunShowers": "雨"
        case "snow", "heavySnow", "flurries", "sunFlurries", "blizzard": "雪"
        case "sleet", "wintryMix", "freezingDrizzle", "freezingRain": "みぞれ・凍結性降水"
        case "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms", "thunderstorms": "雷雨"
        case "foggy", "haze": "霧・もや"
        case "windy", "breezy": "風が強い"
        default: "気象情報"
        }
    }

    private func windDirectionName(_ code: String) -> String {
        switch code {
        case "north": "北"
        case "northNortheast": "北北東"
        case "northeast": "北東"
        case "eastNortheast": "東北東"
        case "east": "東"
        case "eastSoutheast": "東南東"
        case "southeast": "南東"
        case "southSoutheast": "南南東"
        case "south": "南"
        case "southSouthwest": "南南西"
        case "southwest": "南西"
        case "westSouthwest": "西南西"
        case "west": "西"
        case "westNorthwest": "西北西"
        case "northwest": "北西"
        case "northNorthwest": "北北西"
        default: "風"
        }
    }
}
