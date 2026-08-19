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

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testHomeShowsTanzawaMountains() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["蛭ヶ岳"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSearchFiltersMountains() throws {
        let app = XCUIApplication()
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
    func testMountainDetailDismissesWithDownwardSwipe() throws {
        let app = XCUIApplication()
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

        mountainDetail.swipeDown()

        XCTAssertTrue(mountainCard.waitForExistence(timeout: 2))
        XCTAssertFalse(mountainDetail.exists)
        XCTAssertFalse(closeButton.exists)
        XCTAssertFalse(favoriteButton.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
