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
    func testMountainDetailDismissesWithDownwardSwipe() throws {
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
        let favoriteButton = app.buttons["detail-favorite-button"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(closeButton.frame.minY, 44)
        XCTAssertTrue(app.staticTexts["山小屋情報を準備中"].exists)
        XCTAssertTrue(app.staticTexts["登山口情報を準備中"].exists)

        mountainDetail.swipeDown(velocity: .slow)

        XCTAssertTrue(mountainCard.waitForExistence(timeout: 2))
        XCTAssertFalse(mountainDetail.exists)
        XCTAssertFalse(closeButton.exists)
        XCTAssertFalse(favoriteButton.exists)
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
