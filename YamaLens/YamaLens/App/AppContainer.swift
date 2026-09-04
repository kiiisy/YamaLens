import Foundation
import OSLog
import SwiftUI
import UIKit

@MainActor
struct AppContainer {
    let mountainRepository: any MountainRepository
    let cameraMountains: [Mountain]
    let mountainPointOfInterestRepository: any MountainPointOfInterestRepository
    let locationObservationProvider: any LocationObservationProvider
    let proximityCalculator: MountainProximityCalculator
    let cameraObservationProvider: any CameraObservationProvider
    let cameraPreview: AnyView
    let cameraDiagnosticLogRepository: (any CameraDiagnosticLogRepository)?
    let cameraDiagnosticShareFileProvider: (any CameraDiagnosticShareFileProviding)?
    let cameraDiagnosticVideoRecorder: (any CameraDiagnosticVideoRecording)?
    let cameraDiagnosticDevice: CameraDiagnosticDevice?
    let terrainVisibilityResolver: (any TerrainVisibilityResolving)?
    let terrainHorizonResolver: (any TerrainHorizonResolving)?
    let terrainPackageCoverages: [TerrainPackageCoverage]
    let offlinePackageManager: any OfflinePackageManaging
    let offlinePackagePresentation: OfflinePackagePresentation
    let mountainWeatherRepository: any MountainWeatherRepository

    init(
        mountainRepository: any MountainRepository = BootstrapMountainRepository(),
        locationObservationProvider: (any LocationObservationProvider)? = nil,
        proximityCalculator: MountainProximityCalculator = MountainProximityCalculator(),
        backgroundEventsDidFinish: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.mountainRepository = mountainRepository
        let packageSelections = Self.developmentOfflinePackageSelections()
        let primaryPackageSelection = packageSelections.first ?? .tanzawa
        terrainPackageCoverages = packageSelections.map(\.terrainCoverage)
        offlinePackagePresentation = packageSelections.count > 1
            ? .fieldTestSet
            : primaryPackageSelection.presentation
        cameraMountains = Self.makeCameraMountains(
            selections: packageSelections,
            fallbackRepository: mountainRepository
        )
        mountainPointOfInterestRepository = BootstrapMountainPointOfInterestRepository()
        self.locationObservationProvider = locationObservationProvider
            ?? Self.makeLocationObservationProvider()
        self.proximityCalculator = proximityCalculator
        mountainWeatherRepository = Self.makeMountainWeatherRepository()
        if let offlinePackageRootURL = Self.offlinePackageRootURL() {
            let offlinePackageStore = OfflinePackageStore(
                rootURL: offlinePackageRootURL,
                validator: OfflinePackageValidator(
                    publicKeys: OfflinePackageVerificationKeys.all
                )
            )
            let offlinePackageDownloader = BackgroundOfflinePackageFileDownloader(
                rootURL: offlinePackageRootURL,
                backgroundEventsDidFinish: backgroundEventsDidFinish
            )
            let terrainResolver: any TerrainVisibilityResolving & TerrainHorizonResolving
            if packageSelections.count > 1 {
                terrainResolver = AutomaticOfflinePackageTerrainResolver(
                    store: offlinePackageStore,
                    coverages: packageSelections.map(\.terrainCoverage)
                )
            } else {
                terrainResolver = ActiveOfflinePackageTerrainVisibilityResolver(
                    store: offlinePackageStore,
                    packageID: primaryPackageSelection.packageID
                )
            }
            terrainVisibilityResolver = terrainResolver
            terrainHorizonResolver = terrainResolver
            offlinePackageManager = Self.makeOfflinePackageManager(
                store: offlinePackageStore,
                downloader: offlinePackageDownloader,
                selections: packageSelections
            )
        } else {
            terrainVisibilityResolver = nil
            terrainHorizonResolver = nil
            offlinePackageManager = UnavailableOfflinePackageManager()
        }
        let diagnosticVideoRecorder: ARCameraDiagnosticVideoRecorder?
#if DEBUG
        diagnosticVideoRecorder = ARCameraDiagnosticVideoRecorder()
#else
        diagnosticVideoRecorder = nil
#endif
        let cameraDependencies = Self.makeCameraDependencies(
            diagnosticVideoRecorder: diagnosticVideoRecorder
        )
        cameraObservationProvider = cameraDependencies.provider
        cameraPreview = cameraDependencies.preview
        cameraDiagnosticVideoRecorder = diagnosticVideoRecorder
#if DEBUG
        cameraDiagnosticLogRepository = FileCameraDiagnosticLogRepository()
        let diagnosticShareFileProvider = FileCameraDiagnosticShareFileProvider()
        cameraDiagnosticShareFileProvider = diagnosticShareFileProvider
        Task { await diagnosticShareFileProvider.removeExpiredShareFiles() }
        cameraDiagnosticDevice = CameraDiagnosticDevice(
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "未取得",
            operatingSystemVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model
        )
#else
        cameraDiagnosticLogRepository = nil
        cameraDiagnosticShareFileProvider = nil
        cameraDiagnosticDevice = nil
#endif
    }

    private static func offlinePackageRootURL() -> URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appending(path: "OfflinePackages", directoryHint: .isDirectory)
    }

    private static func makeOfflinePackageManager(
        store: OfflinePackageStore,
        downloader: BackgroundOfflinePackageFileDownloader,
        selections: [DevelopmentOfflinePackageSelection]
    ) -> any OfflinePackageManaging {
        let primarySelection = selections.first ?? .tanzawa
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-test-offline-installed") {
            return FixedOfflinePackageManager()
        }
        var developmentManagers: [any OfflinePackageManaging] = []
        developmentManagers.reserveCapacity(selections.count)
        for selection in selections {
            guard let manager = developmentOfflinePackageManager(
                store: store,
                selection: selection
            ) else {
                Logger(subsystem: "com.kiiisy.YamaLens", category: "OfflinePackage")
                    .error("A required development package is unavailable")
                return UnavailableOfflinePackageManager()
            }
            developmentManagers.append(manager)
        }
        if developmentManagers.count > 1 {
            return OfflinePackageCollectionManager(managers: developmentManagers)
        }
        if let manager = developmentManagers.first {
            return manager
        }
#endif
        do {
            let sourceResolver = try OfflinePackageDistribution.tanzawaSourceResolver()
            let validator = OfflinePackageValidator(
                publicKeys: OfflinePackageVerificationKeys.all
            )
            return OfflinePackageManagementService(
                packageID: OfflinePackageDistribution.tanzawaPackageID,
                store: store,
                installer: OfflinePackageInstaller(
                    store: store,
                    validator: validator,
                    fileDownloader: downloader
                ),
                sourceResolver: sourceResolver,
                activeStagingIdentifiers: {
                    await downloader.activeStagingIdentifiers()
                }
            )
        } catch {
            Logger(subsystem: "com.kiiisy.YamaLens", category: "OfflinePackage")
                .fault("The production package distribution is invalid")
            return OfflinePackageManagementService(
                packageID: primarySelection.packageID,
                store: store,
                activeStagingIdentifiers: {
                    await downloader.activeStagingIdentifiers()
                }
            )
        }
    }

#if DEBUG
    private static func developmentOfflinePackageManager(
        store: OfflinePackageStore,
        selection: DevelopmentOfflinePackageSelection
    ) -> (any OfflinePackageManaging)? {
        guard let packageDirectoryURL = developmentPackageDirectoryURL(
            subdirectory: selection.bundleSubdirectory
        ) else {
            return nil
        }
        let source: OfflinePackageSource
        do {
            source = try OfflinePackageSource.developmentBundle(
                packageID: selection.packageID,
                directoryURL: packageDirectoryURL
            )
        } catch {
            return nil
        }
        let validator = OfflinePackageValidator(
            publicKeys: OfflinePackageVerificationKeys.all
        )
        return OfflinePackageManagementService(
            packageID: selection.packageID,
            store: store,
            installer: OfflinePackageInstaller(
                store: store,
                validator: validator,
                fileDownloader: DevelopmentBundleOfflinePackageFileDownloader(
                    sourceDirectoryURL: packageDirectoryURL
                )
            ),
            source: source,
            availableDistribution: .developmentBundle
        )
    }

    private static func developmentPackageDirectoryURL(
        subdirectory: String
    ) -> URL? {
        let packageDirectoryName = String(subdirectory.split(separator: "/").last ?? "")
        if !packageDirectoryName.isEmpty,
           let bundleURL = Bundle.main.url(
               forResource: packageDirectoryName,
               withExtension: "bundle"
           ) {
            return bundleURL
        }
        if let manifestURL = Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: subdirectory
        ) {
            return manifestURL.deletingLastPathComponent()
        }
        guard subdirectory == DevelopmentOfflinePackageSelection.tanzawa.bundleSubdirectory else {
            return nil
        }
        return Bundle.main.url(forResource: "manifest", withExtension: "json")?
            .deletingLastPathComponent()
    }
#endif

    private static func developmentOfflinePackageSelections()
        -> [DevelopmentOfflinePackageSelection] {
#if DEBUG
        if let terrainProfile = DevelopmentTanzawaTerrainProfile.selected(
            from: ProcessInfo.processInfo.arguments,
            storedRawValue: UserDefaults.standard.string(
                forKey: DevelopmentTanzawaTerrainProfile.selectionStorageKey
            )
        ) {
            return [.tanzawaTerrainTest(terrainProfile)]
        }
        if ProcessInfo.processInfo.arguments.contains("-ar-test-pack-takao-jinba") {
            return [.takaoJinbaARTest]
        }
        if ProcessInfo.processInfo.arguments.contains("-ar-test-pack-yatsugatake") {
            return [.yatsugatakeARTest]
        }
        if ProcessInfo.processInfo.arguments.contains("-ar-test-pack-senjogatake") {
            return [.senjogatakeARTest]
        }
        if ProcessInfo.processInfo.arguments.contains("-ar-test-pack-nantaisan") {
            return [.nantaisanARTest]
        }
        if ProcessInfo.processInfo.arguments.contains("-ar-test-pack-tanigawadake") {
            return [.tanigawadakeARTest]
        }
        return DevelopmentOfflinePackageSelection.all
#else
        return [.tanzawa]
#endif
    }

    private static func makeCameraMountains(
        selections: [DevelopmentOfflinePackageSelection],
        fallbackRepository: any MountainRepository
    ) -> [Mountain] {
        let fallbackMountains = fallbackRepository.fetchMountains()
#if DEBUG
        guard selections.contains(where: { $0.presentation.isARTestOnly }) else {
            return fallbackMountains
        }
        var mountains = selections.count > 1 ? fallbackMountains : []
        var knownMountainIDs = Set(mountains.map(\.id))
        for selection in selections where selection.presentation.isARTestOnly {
            guard let packageDirectoryURL = developmentPackageDirectoryURL(
                subdirectory: selection.bundleSubdirectory
            ) else {
                continue
            }
            do {
                let repository = try SQLiteMountainRepository(
                    databaseURL: packageDirectoryURL.appending(path: "catalog.sqlite")
                )
                for mountain in repository.fetchMountains()
                    where knownMountainIDs.insert(mountain.id).inserted {
                    mountains.append(mountain)
                }
            } catch {
                Logger(subsystem: "com.kiiisy.YamaLens", category: "OfflinePackage")
                    .error("An AR test catalog could not be loaded")
            }
        }
        return mountains.isEmpty ? fallbackMountains : mountains
#else
        return fallbackMountains
#endif
    }

    private static func makeLocationObservationProvider() -> any LocationObservationProvider {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-location-granted") {
            return FixedLocationObservationProvider(
                result: .success(
                    LocationObservation(
                        coordinate: GeoCoordinate(latitude: 35.4700, longitude: 139.1450),
                        altitudeMeters: 1_300,
                        horizontalAccuracyMeters: 8,
                        verticalAccuracyMeters: 8,
                        observedAt: .now
                    )
                )
            )
        }
        if arguments.contains("-ui-test-location-denied") {
            return FixedLocationObservationProvider(result: .failure(.denied))
        }
#endif
        return CoreLocationObservationProvider()
    }

    private static func makeMountainWeatherRepository() -> any MountainWeatherRepository {
#if DEBUG
        // Apple Developer Programへ加入するまでは、通常の開発起動でも
        // WeatherKit認証に依存せず気象UIを確認できるようにする。
        // 実サービスの確認時だけSchemeへ -use-live-weatherkit を追加する。
        if !ProcessInfo.processInfo.arguments.contains("-use-live-weatherkit") {
            return FixedMountainWeatherRepository(now: .now)
        }
#endif
        return CachedMountainWeatherRepository()
    }

    private static func makeCameraDependencies(
        diagnosticVideoRecorder: ARCameraDiagnosticVideoRecorder?
    ) -> (
        provider: any CameraObservationProvider,
        preview: AnyView
    ) {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-test-camera-active") {
            let provider = FixedCameraObservationProvider(
                result: .success(()),
                observation: CameraPoseObservation(
                    trueBearingDegrees: 137,
                    pitchDegrees: 2,
                    headingAccuracyDegrees: 5,
                    observedAt: .now,
                    trackingQuality: .normal,
                    projectionGeometry: testProjectionGeometry(facingDegrees: 137)
                )
            )
            return (provider, AnyView(Color(red: 0.14, green: 0.24, blue: 0.22)))
        }
        if arguments.contains("-ui-test-camera-heading-unavailable") {
            let provider = FixedCameraObservationProvider(
                result: .success(()),
                observation: CameraPoseObservation(
                    trueBearingDegrees: 34,
                    pitchDegrees: 2,
                    headingAccuracyDegrees: 5,
                    observedAt: .now,
                    trackingQuality: .normal,
                    projectionGeometry: testProjectionGeometry(facingDegrees: 34)
                ),
                becomesTemporarilyUnavailable: true
            )
            return (provider, AnyView(Color(red: 0.14, green: 0.24, blue: 0.22)))
        }
        if arguments.contains("-ui-test-camera-denied") {
            let provider = FixedCameraObservationProvider(
                result: .failure(.denied),
                observation: nil
            )
            return (provider, AnyView(YamaColor.canvas))
        }
#endif
        let adapter = ARCameraSessionAdapter(
            diagnosticVideoRecorder: diagnosticVideoRecorder
        )
        return (adapter, AnyView(ARCameraPreview(adapter: adapter)))
    }

#if DEBUG
    private static func testProjectionGeometry(
        facingDegrees: Double
    ) -> CameraProjectionGeometry {
        let radians = facingDegrees * .pi / 180
        let viewport = ViewportSize(width: 393, height: 700)
        let focalLength = 421.0
        return CameraProjectionGeometry(
            cameraRightInWorld: SpatialVector(
                x: cos(radians),
                y: 0,
                z: sin(radians)
            ),
            cameraUpInWorld: SpatialVector(x: 0, y: 1, z: 0),
            cameraBackInWorld: SpatialVector(
                x: -sin(radians),
                y: 0,
                z: cos(radians)
            ),
            focalLengthXPixels: focalLength,
            focalLengthYPixels: focalLength,
            principalPointXPixels: viewport.width / 2,
            principalPointYPixels: viewport.height / 2,
            imageSizePixels: viewport,
            normalizedImageToViewport: NormalizedImageTransform(
                a: 1,
                b: 0,
                c: 0,
                d: 1,
                translationX: 0,
                translationY: 0
            ),
            viewportSizePoints: viewport,
            horizontalFieldOfViewDegrees: 50,
            verticalFieldOfViewDegrees: 80
        )
    }
#endif
}

nonisolated enum DevelopmentTanzawaTerrainProfile: String, CaseIterable, Sendable {
    case detailed
    case standard
    case compact

    static let selectionStorageKey = "development.tanzawaTerrainProfile"

    static func selected(from arguments: [String]) -> Self? {
        guard let argumentIndex = arguments.firstIndex(of: "-tanzawa-terrain-profile"),
              arguments.indices.contains(argumentIndex + 1) else {
            return nil
        }
        return Self(rawValue: arguments[argumentIndex + 1])
    }

    /// Xcodeの起動引数を優先し、ない場合だけ開発用設定に保存した選択を使う。
    static func selected(from arguments: [String], storedRawValue: String?) -> Self? {
        selected(from: arguments) ?? Self(rawValue: storedRawValue ?? "")
    }

    var title: String {
        switch self {
        case .detailed:
            return "詳細（約4m）"
        case .standard:
            return "標準（約8m）"
        case .compact:
            return "軽量（約16m）"
        }
    }

    var description: String {
        switch self {
        case .detailed:
            return "約4m中心・現行の比較基準"
        case .standard:
            return "約8m中心・容量と精度の中間"
        case .compact:
            return "約16m中心・容量を優先"
        }
    }

    var packageDirectoryName: String {
        "tanzawa-\(rawValue)-v1"
    }

    var packageID: String {
        switch self {
        case .detailed:
            return "jp.kanagawa.tanzawa"
        case .standard, .compact:
            return "jp.kanagawa.tanzawa.terrain-\(rawValue)-test"
        }
    }
}

private struct DevelopmentOfflinePackageSelection {
    let packageID: String
    let bundleSubdirectory: String
    let presentation: OfflinePackagePresentation
    let terrainCoverage: TerrainPackageCoverage

    static let tanzawa = DevelopmentOfflinePackageSelection(
        packageID: "jp.kanagawa.tanzawa",
        bundleSubdirectory: "DevelopmentOfflinePackages/tanzawa-detailed-v1",
        presentation: .tanzawa,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.kanagawa.tanzawa",
            displayName: "丹沢山地",
            north: 35.60,
            south: 35.30,
            east: 139.30,
            west: 138.95
        )
    )

    static func tanzawaTerrainTest(
        _ terrainProfile: DevelopmentTanzawaTerrainProfile
    ) -> DevelopmentOfflinePackageSelection {
        DevelopmentOfflinePackageSelection(
            packageID: terrainProfile.packageID,
            bundleSubdirectory: "DevelopmentOfflinePackages/\(terrainProfile.packageDirectoryName)",
            presentation: OfflinePackagePresentation(
                regionTitle: "丹沢山地",
                packageTitle: "丹沢 \(terrainProfile.title) 地形テストパック",
                packageSubtitle: "地形粒度の比較用・施設・出典データ",
                installButtonTitle: "\(terrainProfile.title) パックを保存",
                cameraContextTitle: "丹沢・\(terrainProfile.title)・地形比較",
                isARTestOnly: false
            ),
            terrainCoverage: TerrainPackageCoverage(
                packageID: terrainProfile.packageID,
                displayName: "丹沢・\(terrainProfile.title)",
                north: 35.60,
                south: 35.30,
                east: 139.30,
                west: 138.95
            )
        )
    }

    static let takaoJinbaARTest = DevelopmentOfflinePackageSelection(
        packageID: "jp.tokyo.takao-jinba.ar-test",
        bundleSubdirectory: "DevelopmentOfflinePackages/takao-jinba-ar-test-v1",
        presentation: .takaoJinbaARTest,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.tokyo.takao-jinba.ar-test",
            displayName: "高尾・陣馬",
            north: 35.70,
            south: 35.60,
            east: 139.27,
            west: 139.10
        )
    )

    static let yatsugatakeARTest = DevelopmentOfflinePackageSelection(
        packageID: "jp.yatsugatake.ar-test",
        bundleSubdirectory: "DevelopmentOfflinePackages/yatsugatake-ar-test-v1",
        presentation: .yatsugatakeARTest,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.yatsugatake.ar-test",
            displayName: "八ヶ岳",
            north: 36.11,
            south: 35.90,
            east: 138.43,
            west: 138.29
        )
    )

    static let senjogatakeARTest = DevelopmentOfflinePackageSelection(
        packageID: "jp.southern-alps.senjogatake.ar-test",
        bundleSubdirectory: "DevelopmentOfflinePackages/senjogatake-ar-test-v1",
        presentation: .senjogatakeARTest,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.southern-alps.senjogatake.ar-test",
            displayName: "仙丈ヶ岳・南アルプス北部",
            north: 35.82,
            south: 35.56,
            east: 138.32,
            west: 138.10
        )
    )

    static let nantaisanARTest = DevelopmentOfflinePackageSelection(
        packageID: "jp.nikko.nantaisan.ar-test",
        bundleSubdirectory: "DevelopmentOfflinePackages/nantaisan-ar-test-v1",
        presentation: .nantaisanARTest,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.nikko.nantaisan.ar-test",
            displayName: "男体山・日光連山",
            north: 36.87,
            south: 36.68,
            east: 139.60,
            west: 139.30
        )
    )

    static let tanigawadakeARTest = DevelopmentOfflinePackageSelection(
        packageID: "jp.tanigawa.tanigawadake.ar-test",
        bundleSubdirectory: "DevelopmentOfflinePackages/tanigawadake-ar-test-v1",
        presentation: .tanigawadakeARTest,
        terrainCoverage: TerrainPackageCoverage(
            packageID: "jp.tanigawa.tanigawadake.ar-test",
            displayName: "谷川岳・谷川連峰",
            north: 36.92,
            south: 36.75,
            east: 139.03,
            west: 138.75
        )
    )

    static let all: [DevelopmentOfflinePackageSelection] = [
        .tanzawa,
        .takaoJinbaARTest,
        .yatsugatakeARTest,
        .senjogatakeARTest,
        .nantaisanARTest,
        .tanigawadakeARTest,
    ]
}

#if DEBUG
private actor FixedMountainWeatherRepository: MountainWeatherRepository {
    private let now: Date

    init(now: Date) {
        self.now = now
    }

    func cachedForecast(for mountainID: String) async throws -> MountainWeatherForecast? {
        try forecast(mountainID: mountainID)
    }

    func cachedPreviousDaySummary(
        for mountainID: String
    ) async throws -> PreviousDayWeatherSummary? {
        try previousDaySummary(mountainID: mountainID)
    }

    func refreshForecast(
        for mountain: Mountain,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> MountainWeatherForecast {
        try forecast(mountainID: mountain.id)
    }

    func refreshPreviousDaySummary(
        for mountain: Mountain,
        targetDate: Date,
        timeZoneIdentifier: String,
        reason: WeatherRefreshReason,
        now: Date
    ) async throws -> PreviousDayWeatherSummary {
        try previousDaySummary(mountainID: mountain.id)
    }

    private func forecast(mountainID: String) throws -> MountainWeatherForecast {
        guard let legalURL = URL(
            string: "https://weatherkit.apple.com/legal-attribution.html"
        ) else {
            throw MountainWeatherRepositoryError.invalidData
        }
        let current = MountainCurrentWeather(
            observedAt: now,
            conditionCode: "partlyCloudy",
            symbolName: "cloud.sun.fill",
            temperatureCelsius: 7,
            apparentTemperatureCelsius: 4,
            windSpeedMetersPerSecond: 6.2,
            windDirectionCode: "northwest"
        )
        let hourly = (0..<8).map(makeHour(offset:))
        return MountainWeatherForecast(
            mountainID: mountainID,
            current: current,
            hourly: hourly,
            alerts: [],
            retrievedAt: now,
            sourceName: "Apple Weather（テスト用固定値・実際の予報ではありません）",
            legalPageURL: legalURL
        )
    }

    private func makeHour(offset: Int) -> MountainHourlyWeather {
        let isRain = offset >= 4
        return MountainHourlyWeather(
            date: now.addingTimeInterval(Double(offset) * 60 * 60),
            conditionCode: isRain ? "rain" : "partlyCloudy",
            symbolName: isRain ? "cloud.rain.fill" : "cloud.sun.fill",
            temperatureCelsius: 7 - Double(offset) * 0.8,
            windSpeedMetersPerSecond: offset == 3 ? 10.4 : 6.2,
            precipitationChance: isRain ? 0.7 : 0.2,
            hasThunderstorm: false,
            hasSnowOrIce: false
        )
    }

    private func previousDaySummary(
        mountainID: String
    ) throws -> PreviousDayWeatherSummary {
        guard let targetDate = MountainWeatherCalendar.previousDayStart(now: now),
              let legalURL = URL(
                  string: "https://weatherkit.apple.com/legal-attribution.html"
              ) else {
            throw MountainWeatherRepositoryError.invalidData
        }
        return PreviousDayWeatherSummary(
            mountainID: mountainID,
            targetDate: targetDate,
            timeZoneIdentifier: MountainWeatherCalendar.timeZoneIdentifier,
            precipitationMillimeters: 12.4,
            snowfallCentimeters: nil,
            highTemperatureCelsius: 9,
            lowTemperatureCelsius: 2,
            retrievedAt: now,
            sourceName: "Apple Weather（テスト用固定値・実際の予報ではありません）",
            legalPageURL: legalURL
        )
    }
}
#endif

#if DEBUG
@MainActor
private final class FixedLocationObservationProvider: LocationObservationProvider {
    private let result: Result<LocationObservation, LocationObservationFailure>

    init(result: Result<LocationObservation, LocationObservationFailure>) {
        self.result = result
    }

    func authorizationState() -> LocationAuthorizationState {
        switch result {
        case .success:
            return .authorized
        case .failure(.denied):
            return .denied
        case .failure(.restricted):
            return .restricted
        case .failure:
            return .unavailable
        }
    }

    func requestCurrentLocation() async -> Result<LocationObservation, LocationObservationFailure> {
        result
    }
}

@MainActor
private final class FixedCameraObservationProvider: CameraObservationProvider {
    private let result: Result<Void, CameraSessionFailure>
    private let observation: CameraPoseObservation?
    private let becomesTemporarilyUnavailable: Bool

    init(
        result: Result<Void, CameraSessionFailure>,
        observation: CameraPoseObservation?,
        becomesTemporarilyUnavailable: Bool = false
    ) {
        self.result = result
        self.observation = observation
        self.becomesTemporarilyUnavailable = becomesTemporarilyUnavailable
    }

    func start() async -> Result<Void, CameraSessionFailure> {
        result
    }

    func observations() -> AsyncStream<CameraObservationUpdate> {
        AsyncStream { continuation in
            if let observation {
                continuation.yield(.pose(
                    CameraPoseObservation(
                        trueBearingDegrees: observation.trueBearingDegrees,
                        pitchDegrees: observation.pitchDegrees,
                        headingAccuracyDegrees: observation.headingAccuracyDegrees,
                        observedAt: .now,
                        trackingQuality: observation.trackingQuality,
                        projectionGeometry: observation.projectionGeometry
                    )
                ))
            }
            if becomesTemporarilyUnavailable {
                continuation.yield(.temporarilyUnavailable)
            }
        }
    }

    func stop() {}
}

private actor FixedOfflinePackageManager: OfflinePackageManaging {
    private var installedPackage: OfflinePackageSummary? = OfflinePackageSummary(
        packageID: "jp.kanagawa.tanzawa",
        contentVersion: "1.0.0",
        byteCount: 218_000_000,
        createdAt: Date(timeIntervalSince1970: 1_787_011_200)
    )

    func refresh() async throws -> OfflinePackageManagementSnapshot {
        OfflinePackageManagementSnapshot(
            installedPackage: installedPackage,
            distributionAvailability: .unavailable
        )
    }

    func install(
        progress: @escaping @Sendable (OfflinePackageOperationProgress) async -> Void
    ) async throws -> OfflinePackageSummary {
        throw OfflinePackageManagementFailure.distributionUnavailable
    }

    func deleteInstalledPackage() async throws {
        installedPackage = nil
    }
}
#endif
