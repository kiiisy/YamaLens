import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageStoreTests {
    @Test("検証済みパックだけをactiveへ切り替える")
    func installsValidatedPackage() async throws {
        let root = try makeTemporaryDirectory(named: "install")
        defer { removeTemporaryDirectory(root) }
        let keyFixture = try OfflinePackageFixture.make(at: root.appending(path: "key-fixture"))
        try FileManager.default.removeItem(at: keyFixture.directoryURL)
        let store = OfflinePackageStore(
            rootURL: root.appending(path: "OfflinePackages"),
            validator: OfflinePackageValidator(publicKeys: keyFixture.publicKeys)
        )
        let staging = try await store.prepareStagingDirectory(identifier: "download-v1")
        let fixture = try OfflinePackageFixture.make(at: staging)

        let installed = try await store.install(stagedPackageURL: fixture.directoryURL)
        let activeURL = try await store.activePackageURL(packageID: fixture.packageID)

        #expect(installed.contentVersion == "1.0.0")
        #expect(activeURL == installed.directoryURL)
        #expect(FileManager.default.fileExists(atPath: installed.directoryURL.path))
    }

    @Test("更新パックの検証失敗時に直前版を保持する")
    func keepsPreviousPackageWhenUpdateIsInvalid() async throws {
        let root = try makeTemporaryDirectory(named: "rollback")
        defer { removeTemporaryDirectory(root) }
        let storeRoot = root.appending(path: "OfflinePackages")
        let firstStaging = storeRoot
            .appending(path: "Staging")
            .appending(path: "download-v1")
        let firstFixture = try OfflinePackageFixture.make(at: firstStaging)
        let store = OfflinePackageStore(
            rootURL: storeRoot,
            validator: OfflinePackageValidator(publicKeys: firstFixture.publicKeys)
        )
        let firstInstalled = try await store.install(stagedPackageURL: firstFixture.directoryURL)

        let secondStaging = try await store.prepareStagingDirectory(identifier: "download-v2")
        let secondFixture = try OfflinePackageFixture.make(
            at: secondStaging,
            contentVersion: "1.1.0"
        )
        try Data(repeating: 0, count: 64).write(to: secondFixture.signatureURL)

        await #expect(throws: OfflinePackageValidationError.invalidSignature) {
            try await store.install(stagedPackageURL: secondFixture.directoryURL)
        }
        let activeURL = try await store.activePackageURL(packageID: firstFixture.packageID)
        #expect(activeURL == firstInstalled.directoryURL)
    }

    @Test("パック領域へFile Protectionとバックアップ除外を設定する")
    func appliesProtectionAndBackupExclusion() async throws {
        let root = try makeTemporaryDirectory(named: "protection")
        defer { removeTemporaryDirectory(root) }
        let store = OfflinePackageStore(
            rootURL: root.appending(path: "OfflinePackages"),
            validator: OfflinePackageValidator(publicKeys: [:])
        )

        let staging = try await store.prepareStagingDirectory(identifier: "attributes")
        let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
        let resourceValues = try staging.resourceValues(forKeys: [.isExcludedFromBackupKey])

        let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        // Simulatorの一時ファイルシステムはFile Protection属性を返さない場合がある。
        if let protection {
            #expect(protection == .completeUntilFirstUserAuthentication)
        }
#else
        #expect(protection == .completeUntilFirstUserAuthentication)
#endif
        #expect(resourceValues.isExcludedFromBackup == true)
    }

    @Test("readyToInstallで中断した導入を再検証して復旧する")
    func recoversReadyToInstallJournal() async throws {
        let root = try makeTemporaryDirectory(named: "recovery")
        defer { removeTemporaryDirectory(root) }
        let storeRoot = root.appending(path: "OfflinePackages")
        let packageRoot = storeRoot
            .appending(path: "Installed")
            .appending(path: "jp.kanagawa.tanzawa")
        let versionURL = packageRoot
            .appending(path: "Versions")
            .appending(path: "1.0.0")
        let fixture = try OfflinePackageFixture.make(at: versionURL)
        let journal: [String: String] = [
            "packageID": fixture.packageID,
            "contentVersion": fixture.contentVersion,
            "state": "readyToInstall",
        ]
        let journalData = try JSONSerialization.data(withJSONObject: journal)
        try journalData.write(to: packageRoot.appending(path: "install-journal.json"))
        let store = OfflinePackageStore(
            rootURL: storeRoot,
            validator: OfflinePackageValidator(publicKeys: fixture.publicKeys)
        )

        let recovered = try await store.recoverPendingInstall(packageID: fixture.packageID)
        let activeURL = try await store.activePackageURL(packageID: fixture.packageID)

        #expect(recovered?.contentVersion == "1.0.0")
        #expect(activeURL?.standardizedFileURL.path == versionURL.standardizedFileURL.path)
        #expect(!FileManager.default.fileExists(atPath: packageRoot.appending(path: "install-journal.json").path))
    }

    @Test("一時領域以外を破棄対象として受け付けない")
    func rejectsDiscardOutsideStagingRoot() async throws {
        let root = try makeTemporaryDirectory(named: "discard-scope")
        defer { removeTemporaryDirectory(root) }
        let store = OfflinePackageStore(
            rootURL: root.appending(path: "OfflinePackages"),
            validator: OfflinePackageValidator(publicKeys: [:])
        )

        await #expect(throws: OfflinePackageStoreError.invalidStagingLocation) {
            try await store.discardStagingDirectory(root.appending(path: "unrelated"))
        }
    }

    @Test("保存済みパックの表示情報を返してパック領域だけを削除する")
    func reportsAndDeletesInstalledPackage() async throws {
        let root = try makeTemporaryDirectory(named: "summary-delete")
        defer { removeTemporaryDirectory(root) }
        let storeRoot = root.appending(path: "OfflinePackages")
        let staging = storeRoot
            .appending(path: "Staging")
            .appending(path: "download-v1")
        let fixture = try OfflinePackageFixture.make(at: staging)
        let store = OfflinePackageStore(
            rootURL: storeRoot,
            validator: OfflinePackageValidator(publicKeys: fixture.publicKeys)
        )
        _ = try await store.install(stagedPackageURL: staging)

        let summary = try #require(
            try await store.activePackageSummary(packageID: fixture.packageID)
        )
        #expect(summary.contentVersion == fixture.contentVersion)
        #expect(summary.byteCount > 0)

        try await store.deletePackage(packageID: fixture.packageID)

        #expect(try await store.activePackageURL(packageID: fixture.packageID) == nil)
    }

    @Test("24時間を超えた孤立一時領域だけを削除する")
    func discardsOnlyExpiredOrphanedStagingDirectories() async throws {
        let root = try makeTemporaryDirectory(named: "orphan-cleanup")
        defer { removeTemporaryDirectory(root) }
        let store = OfflinePackageStore(
            rootURL: root.appending(path: "OfflinePackages"),
            validator: OfflinePackageValidator(publicKeys: [:])
        )
        let expired = try await store.prepareStagingDirectory(identifier: "expired")
        let preserved = try await store.prepareStagingDirectory(identifier: "preserved")
        let recent = try await store.prepareStagingDirectory(identifier: "recent")
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let oldDate = cutoff.addingTimeInterval(-1)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: expired.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: preserved.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: cutoff],
            ofItemAtPath: recent.path
        )

        let removed = try await store.discardOrphanedStagingDirectories(
            olderThan: cutoff,
            preserving: ["preserved"]
        )

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: expired.path))
        #expect(FileManager.default.fileExists(atPath: preserved.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "YamaLensOfflinePackageStoreTests")
            .appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeTemporaryDirectory(_ url: URL) {
        // テスト専用領域の後始末であり、失敗しても検証結果へ影響しない。
        try? FileManager.default.removeItem(at: url)
    }
}
