import Foundation
import Testing
@testable import YamaLens

struct SQLiteMountainRepositoryTests {
    @Test("同梱bootstrap SQLiteから丹沢の山と別名を読み込める")
    func loadsBundledMountainsAndAliases() throws {
        let databaseURL = try #require(
            BootstrapMountainRepository.databaseURL(in: .main)
        )
        let repository = try SQLiteMountainRepository(databaseURL: databaseURL)

        let mountains = repository.fetchMountains()

        #expect(mountains.count == 17)
        #expect(mountains.filter { $0.coverageRole == .core }.count == 6)
        #expect(mountains.filter { $0.coverageRole == .surroundingCandidate }.count == 11)
        let tonodake = try #require(mountains.first { $0.id == "塔ノ岳" })
        #expect(tonodake.aliases.contains("塔ヶ岳"))
        #expect(tonodake.regionName == "丹沢山地")
        #expect(tonodake.prefectureName == "神奈川県")
        #expect(tonodake.elevationMeters == 1_491)
        #expect(tonodake.yamapURL?.absoluteString == "https://yamap.com/mountains/245")
        let mountFuji = try #require(mountains.first { $0.id == "富士山" })
        #expect(mountFuji.coverageRole == .surroundingCandidate)
        #expect(mountFuji.regionName == "富士山周辺")
    }

    @Test("破損したSQLiteを山データとして使用しない")
    func rejectsCorruptedDatabase() throws {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "corrupted-bootstrap-(UUID().uuidString).sqlite")
        try Data("not-a-sqlite-database".utf8).write(to: temporaryURL)
        defer {
            // テスト専用一時ファイルの後始末であり、失敗しても検証結果へ影響しない。
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        do {
            _ = try SQLiteMountainRepository(databaseURL: temporaryURL)
            Issue.record("破損したSQLiteの読み込みが成功扱いになりました")
        } catch let error as SQLiteMountainRepositoryError {
            switch error {
            case .databaseCheckFailed, .sqliteFailure:
                break
            default:
                Issue.record("想定外のSQLiteエラーです: \(error)")
            }
        } catch {
            Issue.record("型付けされていないエラーです: \(error)")
        }
    }

    @Test("存在しないSQLiteを開けない")
    func rejectsMissingDatabase() {
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-bootstrap-(UUID().uuidString).sqlite")

        do {
            _ = try SQLiteMountainRepository(databaseURL: missingURL)
            Issue.record("存在しないSQLiteの読み込みが成功扱いになりました")
        } catch let error as SQLiteMountainRepositoryError {
            guard case .cannotOpenDatabase = error else {
                Issue.record("想定外のエラーです: \(error)")
                return
            }
        } catch {
            Issue.record("型付けされていないエラーです: \(error)")
        }
    }
}
