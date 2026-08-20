import Foundation
import Testing
@testable import YamaLens

struct HeadingCandidateSelectorTests {
    private let selector = HeadingCandidateSelector()

    @Test("北の0度境界を越えて最も近い方位を選ぶ")
    func sortsAcrossNorthBoundary() {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let north = mountain(id: "north", latitude: 36, longitude: 139)
        let east = mountain(id: "east", latitude: 35, longitude: 140)

        let candidates = selector.candidates(
            from: origin,
            facing: 359,
            mountains: [east, north]
        )

        #expect(candidates.map(\.mountain.id) == ["north", "east"])
        #expect(candidates[0].angularDifferenceDegrees < 2)
    }

    @Test("候補一覧を最大10件に制限する")
    func limitsCandidateTrayToTenMountains() {
        let origin = GeoCoordinate(latitude: 35, longitude: 139)
        let mountains = (1...12).map { index in
            mountain(
                id: String(format: "%02d", index),
                latitude: 35 + Double(index) * 0.01,
                longitude: 139
            )
        }

        let candidates = selector.candidates(
            from: origin,
            facing: 0,
            mountains: mountains
        )

        #expect(candidates.count == 10)
        #expect(candidates.map(\.mountain.id) == (1...10).map { String(format: "%02d", $0) })
    }

    @Test("不正な方位では候補を返さない")
    func rejectsInvalidBearing() {
        let candidates = selector.candidates(
            from: GeoCoordinate(latitude: 35, longitude: 139),
            facing: .nan,
            mountains: [mountain(id: "north", latitude: 36, longitude: 139)]
        )

        #expect(candidates.isEmpty)
    }

    private func mountain(id: String, latitude: Double, longitude: Double) -> Mountain {
        Mountain(
            id: id,
            name: id,
            aliases: [],
            regionName: "テスト山域",
            prefectureName: "神奈川県",
            elevationMeters: 1_000,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude)
        )
    }
}
