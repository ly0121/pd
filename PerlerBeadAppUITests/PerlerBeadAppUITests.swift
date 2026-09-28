import XCTest

final class PerlerBeadAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Drives the full happy path end to end: new project -> sample image (substituting for the
    /// system photo picker, which can't be reliably automated) -> crop confirm -> grid size pick
    /// -> generate -> lands in the pattern editor -> export sheet opens with a rendered image.
    /// This is the primary evidence that BeadCore + BeadPersistence + the SwiftUI layer are wired
    /// together correctly, not just that each compiles in isolation.
    func testFullProjectCreationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        let newProjectButton = app.buttons["newProjectButton"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 5))
        newProjectButton.tap()

        let useSampleImageButton = app.buttons["useSampleImageButton"]
        XCTAssertTrue(useSampleImageButton.waitForExistence(timeout: 5))
        useSampleImageButton.tap()

        let confirmCropButton = app.buttons["confirmCropButton"]
        XCTAssertTrue(confirmCropButton.waitForExistence(timeout: 5))
        confirmCropButton.tap()

        let gridSizeOption16 = app.buttons["gridSizeOption_16"]
        XCTAssertTrue(gridSizeOption16.waitForExistence(timeout: 5))
        gridSizeOption16.tap()

        let generateButton = app.buttons["generatePatternButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        // Generation runs the full BeadCore pipeline (Vision saliency + SLIC + palette
        // optimization + noise cleanup) on a background thread; on a 16x16 grid this should
        // complete well within 30s even on a slow CI simulator.
        let exportButton = app.buttons["exportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 30))

        exportButton.tap()
        let closeButton = app.buttons["关闭"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
    }

    /// Verifies the project list persists and re-displays a project after the app "restarts"
    /// (a fresh XCUIApplication launch reconnects to the same on-disk SwiftData store), proving
    /// BeadProjectRepository's persistence is real and not just in-memory for the session.
    func testCreatedProjectPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        app.buttons["newProjectButton"].tap()
        app.buttons["useSampleImageButton"].tap()
        app.buttons["confirmCropButton"].tap()
        app.buttons["gridSizeOption_16"].tap()
        app.buttons["generatePatternButton"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))

        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launch()

        let projectCardPredicate = NSPredicate(format: "identifier BEGINSWITH 'projectCard_'")
        let anyProjectCard = relaunched.buttons.matching(projectCardPredicate).firstMatch
        XCTAssertTrue(anyProjectCard.waitForExistence(timeout: 5))
    }
}
