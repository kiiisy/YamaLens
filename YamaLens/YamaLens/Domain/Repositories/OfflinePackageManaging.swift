nonisolated protocol OfflinePackageManaging: Sendable {
    func refresh() async throws -> OfflinePackageManagementSnapshot

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary

    func deleteInstalledPackage() async throws
}

nonisolated struct OfflinePackagePresentation: Equatable, Sendable {
    let regionTitle: String
    let packageTitle: String
    let packageSubtitle: String
    let installButtonTitle: String
    let cameraContextTitle: String
    let isARTestOnly: Bool

    var showsUpdateAction: Bool {
        self != .fieldTestSet
    }

    static let tanzawa = OfflinePackagePresentation(
        regionTitle: "丹沢山地",
        packageTitle: "丹沢詳細パック",
        packageSubtitle: "詳細地形・施設・出典データ",
        installButtonTitle: "丹沢詳細パックを保存",
        cameraContextTitle: "丹沢・技術試作",
        isARTestOnly: false
    )

    static let takaoJinbaARTest = OfflinePackagePresentation(
        regionTitle: "高尾・陣馬",
        packageTitle: "高尾・陣馬 ARテストパック",
        packageSubtitle: "山頂候補・詳細地形・出典データ",
        installButtonTitle: "ARテストパックを保存",
        cameraContextTitle: "高尾・陣馬・ARテスト",
        isARTestOnly: true
    )

    static let yatsugatakeARTest = OfflinePackagePresentation(
        regionTitle: "八ヶ岳",
        packageTitle: "八ヶ岳 ARテストパック",
        packageSubtitle: "山頂候補・詳細地形・出典データ",
        installButtonTitle: "ARテストパックを保存",
        cameraContextTitle: "八ヶ岳・ARテスト",
        isARTestOnly: true
    )

    static let senjogatakeARTest = OfflinePackagePresentation(
        regionTitle: "仙丈ヶ岳・南アルプス北部",
        packageTitle: "仙丈ヶ岳 ARテストパック",
        packageSubtitle: "山頂候補・詳細地形・出典データ",
        installButtonTitle: "ARテストパックを保存",
        cameraContextTitle: "仙丈ヶ岳・ARテスト",
        isARTestOnly: true
    )

    static let nantaisanARTest = OfflinePackagePresentation(
        regionTitle: "男体山・日光連山",
        packageTitle: "男体山 ARテストパック",
        packageSubtitle: "山頂候補・詳細地形・出典データ",
        installButtonTitle: "ARテストパックを保存",
        cameraContextTitle: "男体山・ARテスト",
        isARTestOnly: true
    )

    static let tanigawadakeARTest = OfflinePackagePresentation(
        regionTitle: "谷川岳・谷川連峰",
        packageTitle: "谷川岳 ARテストパック",
        packageSubtitle: "山頂候補・詳細地形・出典データ",
        installButtonTitle: "ARテストパックを保存",
        cameraContextTitle: "谷川岳・ARテスト",
        isARTestOnly: true
    )

    static let fieldTestSet = OfflinePackagePresentation(
        regionTitle: "丹沢・高尾・八ヶ岳・南アルプス・日光・谷川",
        packageTitle: "ARフィールドテストパック一式",
        packageSubtitle: "6山域の山頂候補・実DEM・出典データ",
        installButtonTitle: "すべてのテストパックを保存",
        cameraContextTitle: "複数山域・自動選択",
        isARTestOnly: true
    )
}
