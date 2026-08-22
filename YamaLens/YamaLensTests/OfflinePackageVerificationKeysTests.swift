import Testing
@testable import YamaLens

struct OfflinePackageVerificationKeysTests {
    @Test("開発用パック公開鍵をEd25519の32byte表現で登録する")
    func registersDevelopmentPublicKey() throws {
        let key = try #require(
            OfflinePackageVerificationKeys.all[
                OfflinePackageVerificationKeys.developmentKeyID
            ]
        )

        #expect(OfflinePackageVerificationKeys.all.count == 1)
        #expect(key.count == 32)
    }
}
