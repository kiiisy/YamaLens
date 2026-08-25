import CryptoKit
import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageReleaseIndexValidatorTests {
    @Test("署名済みの配布一覧から指定版のパックを選ぶ")
    func validatesSignedReleaseIndex() throws {
        let fixture = try ReleaseIndexFixture.make(contentVersion: "1.0.2")
        let index = try fixture.validator.validate(
            indexData: fixture.indexData,
            signatureData: fixture.signatureData,
            expectedPackageID: fixture.packageID
        )

        #expect(index.contentVersion == "1.0.2")
        #expect(index.packageID == fixture.packageID)
    }

    @Test("改ざんされた配布一覧を受け付けない")
    func rejectsModifiedReleaseIndex() throws {
        let fixture = try ReleaseIndexFixture.make(contentVersion: "1.0.2")
        let modifiedSignature = Data(repeating: 0, count: 64)

        #expect(throws: OfflinePackageReleaseIndexError.invalidSignature) {
            try fixture.validator.validate(
                indexData: fixture.indexData,
                signatureData: modifiedSignature,
                expectedPackageID: fixture.packageID
            )
        }
    }

    @Test("別地域を指す配布一覧を受け付けない")
    func rejectsUnexpectedPackageID() throws {
        let fixture = try ReleaseIndexFixture.make(contentVersion: "1.0.2")

        #expect(throws: OfflinePackageReleaseIndexError.invalidIndex) {
            try fixture.validator.validate(
                indexData: fixture.indexData,
                signatureData: fixture.signatureData,
                expectedPackageID: "jp.example.other-region"
            )
        }
    }
}

private struct ReleaseIndexFixture {
    let packageID: String
    let indexData: Data
    let signatureData: Data
    let validator: OfflinePackageReleaseIndexValidator

    static func make(contentVersion: String) throws -> Self {
        let privateKey = Curve25519.Signing.PrivateKey()
        let packageID = "jp.kanagawa.tanzawa"
        let keyID = "test-release-key-01"
        let object: [String: Any] = [
            "contentVersion": contentVersion,
            "formatVersion": 1,
            "keyID": keyID,
            "packageID": packageID,
            "signatureAlgorithm": "Ed25519",
        ]
        let indexData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return Self(
            packageID: packageID,
            indexData: indexData,
            signatureData: try privateKey.signature(for: indexData),
            validator: OfflinePackageReleaseIndexValidator(
                publicKeys: [keyID: privateKey.publicKey.rawRepresentation]
            )
        )
    }
}
