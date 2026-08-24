//
//  YamaLensUITests.swift
//  YamaLensUITests
//
//  Created by kisaya on 2026/08/19.
//

import XCTest

final class YamaLensUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = makeApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testHomeShowsTanzawaMountains() throws {
        let app = makeApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["蛭ヶ岳"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testOfflineScreenSeparatesBuiltInDataFromDetailedPack() throws {
        let app = makeApplication()
        app.launch()

        let myTab = app.buttons["マイ"]
        XCTAssertTrue(myTab.waitForExistence(timeout: 2))
        myTab.tap()

        let offlineLink = app.buttons["offline-pack-link"]
        XCTAssertTrue(offlineLink.waitForExistence(timeout: 2))
        offlineLink.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-bootstrap-status"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-detail-pack-status"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["基本データ利用可能"].exists)
        XCTAssertTrue(app.staticTexts["未導入"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-surrounding-count"]
                .waitForExistence(timeout: 2)
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "オフラインデータ状態"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testInstalledOfflinePackageCanBeDeletedWithoutDeletingPersonalData() throws {
        let app = makeApplication(launchArguments: ["-ui-test-offline-installed"])
        app.launch()

        app.buttons["マイ"].tap()
        let offlineLink = app.buttons["offline-pack-link"]
        XCTAssertTrue(offlineLink.waitForExistence(timeout: 2))
        offlineLink.tap()

        XCTAssertTrue(app.staticTexts["保存済み"].waitForExistence(timeout: 3))
        let deleteButton = app.buttons["offline-delete-button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        if !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.isHittable)
        deleteButton.tap()

        let confirmation = app.alerts.buttons["削除"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.tap()

        XCTAssertTrue(app.staticTexts["未導入"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["基本データ利用可能"].exists)
    }

    @MainActor
    func testDevelopmentBundleInstallsSignedDetailedPackage() throws {
        let app = makeApplication()
        app.launch()
        app.buttons["マイ"].tap()
        let offlineLink = app.buttons["offline-pack-link"]
        XCTAssertTrue(offlineLink.waitForExistence(timeout: 2))
        offlineLink.tap()

        let developmentNotice = app.descendants(matching: .any)[
            "offline-development-bundle-notice"
        ]
        guard developmentNotice.waitForExistence(timeout: 3) else {
            throw XCTSkip("開発用パックがDebugアプリへ同梱されていません")
        }

        if app.staticTexts["保存済み"].exists {
            deleteDetailedPackage(in: app)
            XCTAssertTrue(app.staticTexts["未導入"].waitForExistence(timeout: 5))
        }

        let installButton = app.buttons["offline-install-button"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 3))
        if !installButton.isHittable {
            app.swipeUp()
        }
        installButton.tap()

        XCTAssertTrue(app.staticTexts["保存済み"].waitForExistence(timeout: 60))
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-installed-package-details"].exists
        )

        deleteDetailedPackage(in: app)
        XCTAssertTrue(app.staticTexts["未導入"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchFiltersMountains() throws {
        let app = makeApplication()
        app.launch()

        let searchButton = app.buttons["search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("塔ノ岳")

        XCTAssertTrue(app.buttons["search-result-塔ノ岳"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["search-result-蛭ヶ岳"].exists)
    }

    @MainActor
    func testMountainDetailShowsDaylightAndOfficialFacilities() throws {
        let app = makeApplication()
        app.launch()

        app.buttons["search-button"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("塔ノ岳")
        let result = app.buttons["search-result-塔ノ岳"]
        XCTAssertTrue(result.waitForExistence(timeout: 2))
        result.tap()

        let detail = app.descendants(matching: .any)["mountain-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 2))
        let daylight = app.descendants(matching: .any)["mountain-daylight-section"]
        for _ in 0..<5 where !daylight.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(daylight.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["日の出・日の入り"].exists)

        let facilityRow = app.buttons["facility-row-sonbutsu-sanso"]
        for _ in 0..<3 where !facilityRow.exists {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(facilityRow.waitForExistence(timeout: 2))
        XCTAssertTrue(facilityRow.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["mountain-facility-section"].exists
        )
        facilityRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["facility-detail-sheet"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["尊仏山荘"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["facility-structured-details"].exists
        )
        XCTAssertTrue(app.staticTexts["営業期間"].exists)
        XCTAssertTrue(app.staticTexts["通年"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["facility-official-link"].exists
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "施設情報の簡易詳細"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["facility-detail-close-button"].tap()
        let trailheadHeading = app.staticTexts["登山口"]
        for _ in 0..<4 where !trailheadHeading.isHittable {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(trailheadHeading.waitForExistence(timeout: 2))

        let trailheadRow = app.buttons["trailhead-row-okura-trailhead"]
        for _ in 0..<4 where !trailheadRow.isHittable {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(trailheadRow.waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.buttons["trailhead-row-yabitsu-pass-trailhead"].exists
        )
        trailheadRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trailhead-access-sheet"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["立ち寄り"].exists)
        let routeButton = app.buttons["trailhead-open-maps-button"]
        XCTAssertTrue(routeButton.exists)
        routeButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["mountain-route-sheet"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.staticTexts["現在地"].exists)
        XCTAssertTrue(app.buttons["route-open-maps-button"].exists)
    }

    @MainActor
    func testCoreMountainOffersFacilitiesAndExternalServices() throws {
        let app = makeApplication()
        app.launch()

        app.buttons["search-button"].tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("蛭ヶ岳")
        app.buttons["search-result-蛭ヶ岳"].tap()

        XCTAssertTrue(
            app.buttons["mountain-hero-photo-picker"].waitForExistence(timeout: 2)
        )
        let mountainHut = app.staticTexts["蛭ヶ岳山荘"]
        for _ in 0..<8 where !mountainHut.exists {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(mountainHut.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["西丹沢ビジターセンター登山口"].exists)

        let yamapLink = app.descendants(matching: .any)["mountain-yamap-link"]
        for _ in 0..<4 where !yamapLink.isHittable {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(yamapLink.waitForExistence(timeout: 2))
        XCTAssertTrue(yamapLink.isHittable)
    }

    @MainActor
    private func deleteDetailedPackage(in app: XCUIApplication) {
        let deleteButton = app.buttons["offline-delete-button"]
        if !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.isHittable)
        deleteButton.tap()
        let confirmation = app.alerts.buttons["削除"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.tap()
    }

    @MainActor
    func testSurroundingMountainExplainsLimitedDataScope() throws {
        let app = makeApplication()
        app.launch()

        let searchButton = app.buttons["search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.tap()

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("富士山")

        let result = app.buttons["search-result-富士山"]
        XCTAssertTrue(result.waitForExistence(timeout: 2))
        result.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["surrounding-candidate-notice"]
                .waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testNearbyMountainsAppearOnlyAfterLocationAction() throws {
        let app = makeApplication(launchArguments: ["-ui-test-location-granted"])
        app.launch()

        let locationButton = app.buttons["nearby-location-button"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["nearby-mountain-list"].exists)

        locationButton.tap()

        let nearbyList = app.descendants(matching: .any)["nearby-mountain-list"]
        XCTAssertTrue(nearbyList.waitForExistence(timeout: 2))
        let nearbyMountain = app.buttons["nearby-mountain-塔ノ岳"]
        XCTAssertTrue(nearbyMountain.waitForExistence(timeout: 2))
        nearbyList.swipeLeft()
        XCTAssertTrue(nearbyMountain.isHittable)
        nearbyMountain.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["mountain-detail-proximity"]
                .waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testDeniedLocationKeepsSearchAvailable() throws {
        let app = makeApplication(launchArguments: ["-ui-test-location-denied"])
        app.launch()

        let locationButton = app.buttons["nearby-location-button"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 2))
        locationButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["nearby-location-recovery"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.buttons["search-button"].exists)
        XCTAssertTrue(app.staticTexts["位置情報が許可されていません"].exists)
    }

    @MainActor
    func testCameraShowsHeadingCandidatesWithFixedSensors() throws {
        let app = makeApplication(
            launchArguments: ["-ui-test-location-granted", "-ui-test-camera-active"]
        )
        app.launch()

        let cameraTab = app.buttons["カメラ"]
        XCTAssertTrue(cameraTab.waitForExistence(timeout: 2))
        cameraTab.tap()

        let startButton = app.buttons["camera-start-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        startButton.tap()

        XCTAssertTrue(app.buttons["camera-label-塔ノ岳"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera-candidate-塔ノ岳"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["camera-search-button"].isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "カメラ方位候補"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testCameraGeneratesTerrainHorizonFromSignedDetailedPackage() throws {
        let app = makeApplication(
            launchArguments: ["-ui-test-location-granted", "-ui-test-camera-active"]
        )
        app.launch()
        app.buttons["マイ"].tap()
        let offlineLink = app.buttons["offline-pack-link"]
        XCTAssertTrue(offlineLink.waitForExistence(timeout: 2))
        offlineLink.tap()

        let developmentNotice = app.descendants(matching: .any)[
            "offline-development-bundle-notice"
        ]
        guard developmentNotice.waitForExistence(timeout: 3) else {
            throw XCTSkip("開発用パックがDebugアプリへ同梱されていません")
        }
        if !app.staticTexts["保存済み"].exists {
            let installButton = app.buttons["offline-install-button"]
            XCTAssertTrue(installButton.waitForExistence(timeout: 3))
            if !installButton.isHittable {
                app.swipeUp()
            }
            installButton.tap()
            XCTAssertTrue(app.staticTexts["保存済み"].waitForExistence(timeout: 60))
        }

        app.buttons["カメラ"].tap()
        let startButton = app.buttons["camera-start-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3))
        startButton.tap()

        let horizon = app.descendants(matching: .any)["camera-terrain-horizon-overlay"]
        XCTAssertTrue(horizon.waitForExistence(timeout: 30))
        XCTAssertFalse(
            app.descendants(matching: .any)["camera-terrain-horizon-unavailable"].exists
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "正式DEM予測稜線"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["マイ"].tap()
        deleteDetailedPackage(in: app)
        XCTAssertTrue(app.staticTexts["未導入"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCameraExplainsHowToRecoverFromHeadingInterference() throws {
        let app = makeApplication(
            launchArguments: [
                "-ui-test-location-granted",
                "-ui-test-camera-heading-unavailable"
            ]
        )
        app.launch()

        app.buttons["カメラ"].tap()
        let startButton = app.buttons["camera-start-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        startButton.tap()

        let recoveryNotice = app.descendants(matching: .any)["camera-heading-recovery"]
        XCTAssertTrue(recoveryNotice.waitForExistence(timeout: 3))
        XCTAssertEqual(
            recoveryNotice.label,
            "方位を再確認しています。金属や磁石を端末から離し、端末をゆっくり上下左右に動かしてください"
        )
        XCTAssertFalse(app.buttons["camera-label-塔ノ岳"].exists)
    }

    @MainActor
    func testCameraRestartsAfterReturningFromItsMountainDetail() throws {
        let app = makeApplication(
            launchArguments: ["-ui-test-location-granted", "-ui-test-camera-active"]
        )
        app.launch()

        app.buttons["カメラ"].tap()
        let startButton = app.buttons["camera-start-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        startButton.tap()

        let cameraLabel = app.buttons["camera-label-塔ノ岳"]
        XCTAssertTrue(cameraLabel.waitForExistence(timeout: 3))
        let adjustmentButton = app.buttons["camera-heading-adjust-button"]
        XCTAssertTrue(adjustmentButton.waitForExistence(timeout: 2))
        adjustmentButton.tap()
        let eastButton = app.buttons["camera-heading-east-button"]
        let correctionValue = app.descendants(matching: .any)["camera-heading-correction-value"]
        eastButton.press(forDuration: 1.2)
        XCTAssertNotEqual(correctionValue.label, "補正なし")
        XCTAssertNotEqual(correctionValue.label, "東へ1°")

        app.buttons["camera-heading-reset-button"].tap()
        XCTAssertEqual(correctionValue.label, "補正なし")
        eastButton.tap()
        XCTAssertEqual(
            correctionValue.label,
            "東へ1°"
        )
        let adjustmentScreenshot = XCTAttachment(screenshot: app.screenshot())
        adjustmentScreenshot.name = "手動方位補正"
        adjustmentScreenshot.lifetime = .keepAlways
        add(adjustmentScreenshot)
        app.buttons["camera-heading-adjust-done-button"].tap()

        cameraLabel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mountain-detail"].waitForExistence(timeout: 2))

        app.buttons["detail-close-button"].tap()

        XCTAssertTrue(cameraLabel.waitForExistence(timeout: 3))
        XCTAssertFalse(startButton.exists)
        XCTAssertTrue(adjustmentButton.label.contains("東へ1°"))

        adjustmentButton.tap()
        app.buttons["camera-heading-reset-button"].tap()
        XCTAssertEqual(
            correctionValue.label,
            "補正なし"
        )
    }

    @MainActor
    func testCameraDiagnosticRecordingRequiresExplicitStartAndDiscardConfirmation() throws {
        let app = makeApplication(
            launchArguments: ["-ui-test-location-granted", "-ui-test-camera-active"]
        )
        app.launch()

        app.buttons["カメラ"].tap()
        let cameraStartButton = app.buttons["camera-start-button"]
        XCTAssertTrue(cameraStartButton.waitForExistence(timeout: 2))
        cameraStartButton.tap()

        let diagnosticStartButton = app.buttons["camera-diagnostic-start"]
        XCTAssertTrue(diagnosticStartButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["camera-diagnostic-save"].exists)
        diagnosticStartButton.tap()

        let saveButton = app.buttons["camera-diagnostic-save"]
        let discardButton = app.buttons["camera-diagnostic-discard"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(discardButton.isHittable)
        discardButton.tap()
        XCTAssertTrue(app.alerts["保存せずに診断記録を破棄しますか？"].waitForExistence(timeout: 2))
        app.alerts.buttons["破棄"].tap()

        XCTAssertTrue(diagnosticStartButton.waitForExistence(timeout: 2))
        XCTAssertFalse(saveButton.exists)
    }

    @MainActor
    func testMountainDetailDismissesWithDownwardSwipe() throws {
        let app = makeApplication()
        app.launch()

        let searchButton = app.buttons["search-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        searchButton.tap()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        searchField.tap()
        searchField.typeText("蛭ヶ岳")
        let searchResult = app.buttons["search-result-蛭ヶ岳"]
        XCTAssertTrue(searchResult.waitForExistence(timeout: 2))
        searchResult.tap()

        let mountainDetail = app.descendants(matching: .any)
            .matching(identifier: "mountain-detail")
            .firstMatch
        XCTAssertTrue(mountainDetail.waitForExistence(timeout: 2))
        let dragStart = mountainDetail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let dragEnd = mountainDetail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)

        XCTAssertTrue(searchButton.waitForExistence(timeout: 2))
        XCTAssertTrue(mountainDetail.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testMountainDetailShowsWeatherStatesAndPreviousDaySummary() throws {
        let app = makeApplication(launchArguments: ["-ui-test-weather-loaded"])
        app.launch()

        let mountainCard = app.buttons
            .matching(identifier: "mountain-row-蛭ヶ岳")
            .firstMatch
        XCTAssertTrue(mountainCard.waitForExistence(timeout: 2))
        mountainCard.tap()

        let detail = app.descendants(matching: .any)["mountain-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 2))
        let weatherSummary = app.buttons["weather-summary-card"]
        for _ in 0..<3 where !weatherSummary.exists {
            detail.swipeUp()
        }
        XCTAssertTrue(weatherSummary.waitForExistence(timeout: 2))

        let summaryScreenshot = XCTAttachment(screenshot: app.screenshot())
        summaryScreenshot.name = "山詳細の天気概要"
        summaryScreenshot.lifetime = .keepAlways
        add(summaryScreenshot)

        weatherSummary.tap()

        let weatherDetail = app.descendants(matching: .any)["weather-detail"]
        XCTAssertTrue(weatherDetail.waitForExistence(timeout: 2))
        let currentWeather = app.descendants(matching: .any)["weather-current-card"]
        XCTAssertTrue(currentWeather.waitForExistence(timeout: 2))
        for _ in 0..<2 where !app.descendants(matching: .any)["weather-warnings"].exists {
            weatherDetail.swipeUp()
        }
        XCTAssertTrue(app.descendants(matching: .any)["weather-warnings"].exists)
        XCTAssertTrue(app.staticTexts["今後12時間の注意情報"].exists)

        let previousDay = app.descendants(matching: .any)["weather-previous-day-card"]
        for _ in 0..<3 where !previousDay.exists {
            weatherDetail.swipeUp()
        }
        XCTAssertTrue(previousDay.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["前日の気象サマリー（山頂付近）"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "天気の詳細"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testMountainDetailClosesWithBackButton() throws {
        let app = makeApplication()
        app.launch()

        let mountainCard = app.buttons
            .matching(identifier: "mountain-row-蛭ヶ岳")
            .firstMatch
        XCTAssertTrue(mountainCard.waitForExistence(timeout: 2))
        mountainCard.tap()

        let mountainDetail = app.descendants(matching: .any)
            .matching(identifier: "mountain-detail")
            .firstMatch
        XCTAssertTrue(mountainDetail.waitForExistence(timeout: 2))

        let closeButton = app.buttons["detail-close-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        closeButton.tap()

        XCTAssertTrue(mountainCard.waitForExistence(timeout: 2))
        XCTAssertFalse(mountainDetail.exists)
        XCTAssertFalse(closeButton.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApplication().launch()
        }
    }

    @MainActor
    private func makeApplication(launchArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        return app
    }
}
