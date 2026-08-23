import Foundation
import OSLog

nonisolated struct BootstrapMountainRepository: MountainRepository {
    private static let logger = Logger(
        subsystem: "com.kiiisy.YamaLens",
        category: "BootstrapMountainRepository"
    )

    private let repository: any MountainRepository

    init(bundle: Bundle = .main) {
        guard let databaseURL = Self.databaseURL(in: bundle) else {
            Self.logger.fault("Bundled bootstrap SQLite was not found; using emergency mountain data")
            repository = EmergencyMountainRepository()
            return
        }

        do {
            repository = try SQLiteMountainRepository(databaseURL: databaseURL)
        } catch {
            Self.logger.fault("Bundled bootstrap SQLite could not be read; using emergency mountain data")
            repository = EmergencyMountainRepository()
        }
    }

    func fetchMountains() -> [Mountain] {
        repository.fetchMountains()
    }

    static func databaseURL(in bundle: Bundle) -> URL? {
        if let nestedURL = bundle.url(
            forResource: "bootstrap",
            withExtension: "sqlite",
            subdirectory: "Bootstrap"
        ) {
            return nestedURL
        }
        return bundle.url(forResource: "bootstrap", withExtension: "sqlite")
    }
}

/// アプリBundleの構成不備でも検索経路を失わないためだけに使用する最小の退避データ。
private nonisolated struct EmergencyMountainRepository: MountainRepository {
    func fetchMountains() -> [Mountain] {
        [
            Mountain(
                id: "蛭ヶ岳",
                name: "蛭ヶ岳",
                aliases: ["ひるがたけ"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1673,
                coordinate: GeoCoordinate(latitude: 35.4863889, longitude: 139.1388889),
                yamapURL: URL(string: "https://yamap.com/mountains/33")
            ),
            Mountain(
                id: "丹沢山",
                name: "丹沢山",
                aliases: ["たんざわさん"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1567,
                coordinate: GeoCoordinate(latitude: 35.4741667, longitude: 139.1627778),
                yamapURL: URL(string: "https://yamap.com/mountains/110")
            ),
            Mountain(
                id: "塔ノ岳",
                name: "塔ノ岳",
                aliases: ["とうのだけ", "塔ヶ岳"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1491,
                coordinate: GeoCoordinate(latitude: 35.4541667, longitude: 139.1633333),
                yamapURL: URL(string: "https://yamap.com/mountains/245")
            ),
            Mountain(
                id: "檜洞丸",
                name: "檜洞丸",
                aliases: ["ひのきぼらまる"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1601,
                coordinate: GeoCoordinate(latitude: 35.4790567, longitude: 139.1027937),
                yamapURL: URL(string: "https://yamap.com/mountains/16167")
            ),
            Mountain(
                id: "鍋割山",
                name: "鍋割山",
                aliases: ["なべわりやま"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1273,
                coordinate: GeoCoordinate(latitude: 35.4437799, longitude: 139.1413847),
                yamapURL: URL(string: "https://yamap.com/mountains/248")
            ),
            Mountain(
                id: "大山",
                name: "大山",
                aliases: ["おおやま", "阿夫利山"],
                regionName: "丹沢山地",
                prefectureName: "神奈川県",
                elevationMeters: 1252,
                coordinate: GeoCoordinate(latitude: 35.4408333, longitude: 139.2313889),
                yamapURL: URL(string: "https://yamap.com/mountains/32")
            ),
        ]
    }
}
