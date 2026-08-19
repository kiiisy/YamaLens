//
//  YamaLensTests.swift
//  YamaLensTests
//
//  Created by kisaya on 2026/08/19.
//

import Testing
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

}
