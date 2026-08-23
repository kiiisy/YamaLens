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
        let tonodakeTrailheads = repository.fetchTrailheadAccessGuides(for: "塔ノ岳")

        #expect(tonodake.count == 8)
        #expect(ooyama.count == 3)
        #expect(tonodake.contains { $0.type == .mountainHut && $0.name == "尊仏山荘" })
        #expect(ooyama.contains { $0.type == .cableway && $0.name == "大山ケーブルカー" })
        #expect(tonodake.allSatisfy { $0.officialURL.scheme == "https" })
        #expect(tonodake.allSatisfy { !$0.sourceProvider.isEmpty })
        #expect(tonodakeTrailheads.map(\.trailhead.name) == ["大倉登山口", "ヤビツ峠登山口"])
        #expect(tonodakeTrailheads.allSatisfy { $0.accessPoints.count == 2 })
        #expect(tonodakeTrailheads[0].nearbySearchAreas.map(\.name) == ["大倉登山口", "渋沢駅"])
        #expect(tonodakeTrailheads[1].nearbySearchAreas.map(\.name) == ["ヤビツ峠", "秦野駅"])
    }

    @Test("施設未登録の山には空配列を返す")
    func returnsEmptyForMountainWithoutFacilities() throws {
        let databaseURL = try #require(
            BootstrapMountainRepository.databaseURL(in: .main)
        )
        let repository = try SQLiteMountainPointOfInterestRepository(databaseURL: databaseURL)

        #expect(repository.fetchPointsOfInterest(for: "蛭ヶ岳").isEmpty)
        #expect(repository.fetchTrailheadAccessGuides(for: "蛭ヶ岳").isEmpty)
    }
}
