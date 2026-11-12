import XCTest

/// Tests that the viewer opens the SVG files of the test suite.
final class InternalAppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testOpeningAFileOfTheTestSuite() throws {
    let app = XCUIApplication()
    app.launch()

    // The folders of the test suite.
    app.buttons["custom"].tap()
    app.buttons["color"].tap()
    app.buttons["color-functions"].tap()

    // A comparison of the file, which steps to the next file of the folder.
    XCTAssertTrue(app.navigationBars["color-functions"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.segmentedControls.buttons["SVGView"].exists)
    XCTAssertTrue(app.segmentedControls.buttons["WebView"].exists)
    XCTAssertTrue(app.staticTexts["1 / 4"].exists)
    app.buttons["Next"].tap()
    XCTAssertTrue(app.navigationBars["color-mix-none"].waitForExistence(timeout: 10))
  }
}
