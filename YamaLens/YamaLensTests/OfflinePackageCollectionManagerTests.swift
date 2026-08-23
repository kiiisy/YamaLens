import Foundation
import Testing
@testable import YamaLens

struct OfflinePackageCollectionManagerTests {
    @Test("全パック保存済みなら容量を合算して保存済みとする")
    func aggregatesInstalledPackages() async throws {
        let first = CollectionFakeOfflinePackageManager(
            package: package(id: "first", bytes: 100)
        )
        let second = CollectionFakeOfflinePackageManager(
            package: package(id: "second", bytes: 200)
        )
        let manager = OfflinePackageCollectionManager(managers: [first, second])

        let snapshot = try await manager.refresh()

        #expect(snapshot.installedPackage?.byteCount == 300)
        #expect(snapshot.distributionAvailability == .developmentBundle)
    }

    @Test("一部だけ未保存なら不足分だけを保存する")
    func installsOnlyMissingPackages() async throws {
        let first = CollectionFakeOfflinePackageManager(
            package: package(id: "first", bytes: 100)
        )
        let second = CollectionFakeOfflinePackageManager(
            package: nil,
            installationPackage: package(id: "second", bytes: 200)
        )
        let manager = OfflinePackageCollectionManager(managers: [first, second])

        let installed = try await manager.install { _ in }

        #expect(installed.byteCount == 300)
        #expect(await first.installCount == 0)
        #expect(await second.installCount == 1)
    }

    @Test("一式の削除は各山域パックを削除する")
    func deletesEveryPackage() async throws {
        let first = CollectionFakeOfflinePackageManager(
            package: package(id: "first", bytes: 100)
        )
        let second = CollectionFakeOfflinePackageManager(
            package: package(id: "second", bytes: 200)
        )
        let manager = OfflinePackageCollectionManager(managers: [first, second])

        try await manager.deleteInstalledPackage()

        #expect(await first.deleteCount == 1)
        #expect(await second.deleteCount == 1)
    }

    private func package(id: String, bytes: Int64) -> OfflinePackageSummary {
        OfflinePackageSummary(
            packageID: id,
            contentVersion: "1.0.0",
            byteCount: bytes,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private actor CollectionFakeOfflinePackageManager: OfflinePackageManaging {
    private var package: OfflinePackageSummary?
    private let installationPackage: OfflinePackageSummary?
    private(set) var installCount = 0
    private(set) var deleteCount = 0

    init(
        package: OfflinePackageSummary?,
        installationPackage: OfflinePackageSummary? = nil
    ) {
        self.package = package
        self.installationPackage = installationPackage
    }

    func refresh() async throws -> OfflinePackageManagementSnapshot {
        OfflinePackageManagementSnapshot(
            installedPackage: package,
            distributionAvailability: .developmentBundle
        )
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        installCount += 1
        guard let installationPackage else {
            throw OfflinePackageManagementFailure.distributionUnavailable
        }
        package = installationPackage
        await progress(.verifying)
        return installationPackage
    }

    func deleteInstalledPackage() async throws {
        deleteCount += 1
        package = nil
    }
}
