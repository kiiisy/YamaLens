nonisolated protocol OfflinePackageManaging: Sendable {
    func refresh() async throws -> OfflinePackageManagementSnapshot

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary

    func deleteInstalledPackage() async throws
}
