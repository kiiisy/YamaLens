import Foundation
import Testing
@testable import YamaLens

struct SQLiteMountainPointOfInterestRepositoryTests {
    @Test("同梱SQLiteから山に紐づく公式施設情報を読み込める")
    func loadsOfficialFacilitiesForMountain() throws {
        let databaseURL = try #require(
            BootstrapMountainRepository.databaseURL(in: .main)
        )
        let repository = try SQLiteMountainPointOfInterestRepository(databaseURL: databaseURL)

        let tonodake = repository.fetchPointsOfInterest(for: "塔ノ岳")
        let ooyama = repository.fetchPointsOfInterest(for: "大山")
        let tanzawasan = repository.fetchPointsOfInterest(for: "丹沢山")
        let hirugatake = repository.fetchPointsOfInterest(for: "蛭ヶ岳")
        let hinokiboramaru = repository.fetchPointsOfInterest(for: "檜洞丸")
        let nabewariyama = repository.fetchPointsOfInterest(for: "鍋割山")
        let tonodakeTrailheads = repository.fetchTrailheadAccessGuides(for: "塔ノ岳")

        #expect(tonodake.count == 8)
        #expect(ooyama.count == 4)
        #expect(tonodake.contains { $0.type == .mountainHut && $0.name == "尊仏山荘" })
        #expect(ooyama.contains { $0.type == .cableway && $0.name == "大山ケーブルカー" })
        #expect(tanzawasan.contains { $0.type == .mountainHut && $0.name == "みやま山荘" })
        #expect(hirugatake.contains { $0.type == .mountainHut && $0.name == "蛭ヶ岳山荘" })
        #expect(hinokiboramaru.contains { $0.type == .mountainHut && $0.name == "青ヶ岳山荘" })
        #expect(nabewariyama.contains { $0.type == .mountainHut && $0.name == "鍋割山荘" })
        #expect(tonodake.allSatisfy { $0.officialURL.scheme == "https" })
        #expect(tonodake.allSatisfy { !$0.sourceProvider.isEmpty })
        #expect(tonodakeTrailheads.map(\.trailhead.name) == ["大倉登山口", "ヤビツ峠登山口"])
        #expect(tonodakeTrailheads[0].accessPoints.map(\.name) == [
            "大倉バス停", "秦野戸川公園 大倉駐車場", "弘法の里湯"
        ])
        #expect(tonodakeTrailheads[1].accessPoints.count == 2)
        #expect(tonodakeTrailheads[0].nearbySearchAreas.map(\.name) == ["大倉登山口", "渋沢駅"])
        #expect(tonodakeTrailheads[1].nearbySearchAreas.map(\.name) == ["ヤビツ峠", "秦野駅"])
    }

    @Test("正式対象外の周辺候補には施設情報を補完しない")
    func returnsEmptyForMountainWithoutFacilities() throws {
        let databaseURL = try #require(
            BootstrapMountainRepository.databaseURL(in: .main)
        )
        let repository = try SQLiteMountainPointOfInterestRepository(databaseURL: databaseURL)

        #expect(repository.fetchPointsOfInterest(for: "富士山").isEmpty)
        #expect(repository.fetchTrailheadAccessGuides(for: "富士山").isEmpty)
    }
}
