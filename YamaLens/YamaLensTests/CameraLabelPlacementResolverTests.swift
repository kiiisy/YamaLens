import CoreGraphics
import Testing
@testable import YamaLens

@MainActor
struct CameraLabelPlacementResolverTests {
    @Test("同じ方向にあるラベルを重ならない位置へ配置する")
    func separatesOverlappingLabels() {
        let anchors = (1...5).map { index in
            CameraLabelAnchor(
                id: "mountain-\(index)",
                point: CGPoint(x: 196, y: 360)
            )
        }

        let placements = CameraLabelPlacementResolver().resolve(
            anchors: anchors,
            viewportSize: CGSize(width: 393, height: 852)
        )
        let frames = placements.map { placement in
            CGRect(
                x: placement.labelCenter.x - 84,
                y: placement.labelCenter.y - 27,
                width: 168,
                height: 54
            )
        }

        #expect(placements.count == 5)
        for firstIndex in frames.indices {
            for secondIndex in frames.indices where secondIndex > firstIndex {
                #expect(!frames[firstIndex].intersects(frames[secondIndex]))
            }
        }
    }

    @Test("ラベルを画面端と下部操作領域の外側に保つ")
    func keepsLabelsInsideAvailableArea() {
        let anchors = [
            CameraLabelAnchor(id: "left-top", point: CGPoint(x: 0, y: 0)),
            CameraLabelAnchor(id: "right-bottom", point: CGPoint(x: 393, y: 852))
        ]

        let placements = CameraLabelPlacementResolver().resolve(
            anchors: anchors,
            viewportSize: CGSize(width: 393, height: 852)
        )

        for placement in placements {
            #expect(placement.labelCenter.x >= 94)
            #expect(placement.labelCenter.x <= 299)
            #expect(placement.labelCenter.y >= 99)
            #expect(placement.labelCenter.y <= 575)
        }
    }

    @Test("アクセシビリティ文字サイズでも5件のラベルを分離する")
    func separatesAccessibilitySizedLabels() {
        let anchors = (1...5).map { index in
            CameraLabelAnchor(
                id: "mountain-\(index)",
                point: CGPoint(x: 196, y: 340)
            )
        }
        let labelSize = CGSize(width: 190, height: 78)

        let placements = CameraLabelPlacementResolver(labelSize: labelSize).resolve(
            anchors: anchors,
            viewportSize: CGSize(width: 393, height: 852)
        )
        let frames = placements.map { placement in
            CGRect(
                x: placement.labelCenter.x - labelSize.width / 2,
                y: placement.labelCenter.y - labelSize.height / 2,
                width: labelSize.width,
                height: labelSize.height
            )
        }

        for firstIndex in frames.indices {
            for secondIndex in frames.indices where secondIndex > firstIndex {
                #expect(!frames[firstIndex].intersects(frames[secondIndex]))
            }
        }
    }
}
