import XCTest

/// Not a correctness test — walks the flow and attaches a screenshot at each step so the
/// visual design (coral theme, grid canvas, palette, export layout) can be reviewed without
/// relying on unreliable host-level mouse-click simulation in this environment.
final class PerlerBeadAppScreenshotWalkthrough: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreenshotsAlongFullFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()
        attachScreenshot(app, name: "01-project-list-empty")

        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.buttons["useSampleImageButton"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "02-pick-image-step")

        app.buttons["useSampleImageButton"].tap()
        XCTAssertTrue(app.buttons["confirmCropButton"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "03-crop-step")

        app.buttons["confirmCropButton"].tap()
        XCTAssertTrue(app.buttons["gridSizeOption_16"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "04-grid-size-step")

        app.buttons["gridSizeOption_48"].tap()
        app.buttons["generatePatternButton"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))
        // Give the editor a beat to finish laying out the canvas + palette after the nav push.
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app, name: "05-pattern-editor")

        // "保存" saves straight to the photo library with no confirmation sheet, so there's no
        // separate export screen left to screenshot here.
        app.buttons["exportButton"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(app, name: "06-after-save")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
