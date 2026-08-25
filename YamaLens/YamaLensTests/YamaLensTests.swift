//
//  YamaLensTests.swift
//  YamaLensTests
//
//  Created by kisaya on 2026/08/19.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import YamaLens

@MainActor
struct YamaLensTests {

    private let service = MountainSearchService()
    private let mountains = BootstrapMountainRepository().fetchMountains()

    @Test("空の検索語では丹沢の全山を返す")
    func emptyQueryReturnsAllMountains() {
        let result = service.search(mountains: mountains, query: "")

        #expect(result == mountains)
    }

    @Test("山名の一部で検索できる")
    func searchesByMountainName() {
        let result = service.search(mountains: mountains, query: "塔ノ")

        #expect(result.map(\.name) == ["塔ノ岳"])
    }

    @Test("別名と空白を正規化して検索できる")
    func searchesByAliasAndNormalizedWhitespace() {
        let result = service.search(mountains: mountains, query: "  とうのだけ ")

        #expect(result.map(\.name) == ["塔ノ岳"])
    }

    @Test("一致しない検索語では空結果を返す")
    func unmatchedQueryReturnsEmptyResult() {
        let result = service.search(mountains: mountains, query: "存在しない山")

        #expect(result.isEmpty)
    }

    @Test("個人の山記録は未選択状態から始まる")
    func userMountainRecordHasSafeDefaults() {
        let record = UserMountainRecord(mountainID: "塔ノ岳")

        #expect(record.isFavorite == false)
        #expect(record.isSummited == false)
        #expect(record.beforeNote.isEmpty)
        #expect(record.duringNote.isEmpty)
        #expect(record.afterNote.isEmpty)
        #expect(record.lastViewedAt == nil)
    }

    @Test("よく使う出発駅は同じ1件を置き換えられる")
    func savedDeparturePointCanBeReplaced() throws {
        let point = SavedDeparturePoint(
            name: "JR新宿駅",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        point.replace(
            name: "都営地下鉄新宿駅",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(point.identifier == "frequent-departure-station")
        #expect(point.name == "都営地下鉄新宿駅")
        #expect(point.updatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test(
        "縦長と横長の写真を同じヒーロー領域へ収める",
        arguments: [
            CGSize(width: 300, height: 1_200),
            CGSize(width: 1_200, height: 300),
        ]
    )
    func heroImageKeepsFixedContainerSize(imageSize: CGSize) throws {
        let sourceImage = UIGraphicsImageRenderer(size: imageSize).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        let imageData = try #require(sourceImage.jpegData(compressionQuality: 0.8))
        let renderer = ImageRenderer(
            content: MountainHeroImageView(
                mountain: mountains[0],
                imageData: imageData,
                height: 350
            )
            .frame(width: 390)
        )
        renderer.scale = 1

        let renderedImage = try #require(renderer.uiImage)

        #expect(renderedImage.size == CGSize(width: 390, height: 350))
    }

}
