import Foundation
import Testing
@testable import YamaLens

@MainActor
struct OfflinePackageScreenModelTests {
    @Test("配布前は未導入と基本データ利用可能の状態を保つ")
    func loadsUnavailableDistribution() async {
        let manager = FakeOfflinePackageManager(
            snapshot: OfflinePackageManagementSnapshot(
                installedPackage: nil,
                distributionAvailability: .unavailable
            )
        )
        let model = OfflinePackageScreenModel(manager: manager)

        await model.load()

        #expect(model.state == .notInstalled(distribution: .unavailable))
    }

    @Test("保存済みパックの版・容量・作成日を読み込む")
    func loadsInstalledPackage() async {
        let package = testPackage
        let manager = FakeOfflinePackageManager(
            snapshot: OfflinePackageManagementSnapshot(
                installedPackage: package,
                distributionAvailability: .unavailable
            )
        )
        let model = OfflinePackageScreenModel(manager: manager)

        await model.load()

        #expect(
            model.state == .installed(
                package,
                distribution: .unavailable
            )
        )
    }

    @Test("導入処理の完了後に保存済み状態へ切り替える")
    func installsAvailablePackage() async {
        let package = testPackage
        let manager = FakeOfflinePackageManager(
            snapshot: OfflinePackageManagementSnapshot(
                installedPackage: nil,
                distributionAvailability: .available
            ),
            installationResult: .success(package)
        )
        let model = OfflinePackageScreenModel(manager: manager)
        await model.load()

        await model.install()

        #expect(model.state == .installed(package, distribution: .available))
        #expect(
            await manager.reportedProgress == [
                .downloading(completedBytes: 0, totalBytes: package.byteCount),
                .verifying,
            ]
        )
    }

    @Test("更新失敗時も直前の保存済みパックを表示する")
    func keepsInstalledPackageAfterUpdateFailure() async {
        let package = testPackage
        let manager = FakeOfflinePackageManager(
            snapshot: OfflinePackageManagementSnapshot(
                installedPackage: package,
                distributionAvailability: .available
            ),
            installationResult: .failure(.invalidData)
        )
        let model = OfflinePackageScreenModel(manager: manager)
        await model.load()

        await model.install()

        #expect(
            model.state == .failed(
                .invalidData,
                previousPackage: package,
                distribution: .available
            )
        )
    }

    @Test("詳細パック削除後は未導入へ戻る")
    func deletesInstalledPackage() async {
        let manager = FakeOfflinePackageManager(
            snapshot: OfflinePackageManagementSnapshot(
                installedPackage: testPackage,
                distributionAvailability: .unavailable
            )
        )
        let model = OfflinePackageScreenModel(manager: manager)
        await model.load()

        await model.deleteInstalledPackage()

        #expect(model.state == .notInstalled(distribution: .unavailable))
        #expect(await manager.deleteCount == 1)
    }

    private var testPackage: OfflinePackageSummary {
        OfflinePackageSummary(
            packageID: "jp.kanagawa.tanzawa",
            contentVersion: "1.0.0",
            byteCount: 218_000_000,
            createdAt: Date(timeIntervalSince1970: 1_787_011_200)
        )
    }
}

private actor FakeOfflinePackageManager: OfflinePackageManaging {
    private var snapshot: OfflinePackageManagementSnapshot
    private let installationResult: Result<
        OfflinePackageSummary,
        OfflinePackageManagementFailure
    >
    private(set) var reportedProgress: [OfflinePackageOperationProgress] = []
    private(set) var deleteCount = 0

    init(
        snapshot: OfflinePackageManagementSnapshot,
        installationResult: Result<
            OfflinePackageSummary,
            OfflinePackageManagementFailure
        > = .failure(.distributionUnavailable)
    ) {
        self.snapshot = snapshot
        self.installationResult = installationResult
    }

    func refresh() async throws -> OfflinePackageManagementSnapshot {
        snapshot
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        switch installationResult {
        case .success(let package):
            let downloading = OfflinePackageOperationProgress.downloading(
                completedBytes: 0,
                totalBytes: package.byteCount
            )
            reportedProgress.append(downloading)
            await progress(downloading)
            reportedProgress.append(.verifying)
            await progress(.verifying)
            snapshot = OfflinePackageManagementSnapshot(
                installedPackage: package,
                distributionAvailability: snapshot.distributionAvailability
            )
            return package
        case .failure(let failure):
            throw failure
        }
    }

    func deleteInstalledPackage() async throws {
        deleteCount += 1
        snapshot = OfflinePackageManagementSnapshot(
            installedPackage: nil,
            distributionAvailability: snapshot.distributionAvailability
        )
    }
}
