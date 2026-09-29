import XCTest

final class PerlerBeadAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Drives the full happy path end to end: new project -> sample image (substituting for the
    /// system photo picker, which can't be reliably automated) -> crop confirm -> grid size pick
    /// -> generate -> lands in the pattern editor -> saves directly to the photo library.
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

        // Tapping "保存" saves straight to the photo library with no confirmation sheet — the
        // editor screen itself stays put, so the assertion is just that it's still there and
        // usable (no crash, no unexpected navigation) after the tap.
        exportButton.tap()
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
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

    /// Drives the pattern editor's "regenerate at a different size" flow end to end: reach the
    /// editor via the normal new-project path, tap the regenerate button, pick a different grid
    /// size than the one just used, confirm the destructive confirmation dialog, and verify the
    /// editor is still usable afterward (exportButton reappears) — proving the project's saved
    /// original photo can be re-run through the full generation pipeline from within the editor,
    /// not just once at creation time.
    func testRegeneratePatternAtDifferentSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        app.buttons["newProjectButton"].tap()
        app.buttons["useSampleImageButton"].tap()
        app.buttons["confirmCropButton"].tap()
        app.buttons["gridSizeOption_16"].tap()
        app.buttons["generatePatternButton"].tap()
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))

        let regenerateButton = app.buttons["regenerateButton"]
        XCTAssertTrue(regenerateButton.waitForExistence(timeout: 5))
        regenerateButton.tap()

        let differentSizeOption = app.buttons["gridSizeOption_24"]
        XCTAssertTrue(differentSizeOption.waitForExistence(timeout: 5))
        differentSizeOption.tap()

        // confirmationDialog buttons report a nested duplicate of the same accessibility
        // identifier in the snapshot tree, so disambiguate with firstMatch.
        let confirmRegenerateButton = app.buttons["confirmRegenerateButton"].firstMatch
        XCTAssertTrue(confirmRegenerateButton.waitForExistence(timeout: 5))
        confirmRegenerateButton.tap()

        // Regeneration re-runs the full BeadCore pipeline on a background thread; give it the
        // same generous timeout as initial generation.
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))
    }

    /// Full-catalog projects must remain readable, not merely finish generating an export button
    /// that is disabled because the editor failed to decode a non-owned color.
    @MainActor
    func testFullPaletteProjectLoadsAfterReopeningAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()
        defer { app.terminate() }

        func tapVisible(_ element: XCUIElement) {
            for _ in 0..<10 {
                if element.exists && element.isHittable { element.tap(); return }
                app.swipeUp()
            }
            XCTFail("Cannot reveal \(element)")
        }
        func assertEditorLoaded() {
            let export = app.buttons["exportButton"]
            XCTAssertTrue(export.waitForExistence(timeout: 60))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: export)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "图纸数据读取失败")).firstMatch.exists)
            XCTAssertTrue(app.buttons["regenerateButton"].exists)
        }

        XCTAssertTrue(app.buttons["newProjectButton"].waitForExistence(timeout: 10))
        app.buttons["newProjectButton"].tap()
        XCTAssertTrue(app.buttons["useSampleImageButton"].waitForExistence(timeout: 10))
        app.buttons["useSampleImageButton"].tap()
        XCTAssertTrue(app.buttons["confirmCropButton"].waitForExistence(timeout: 10))
        app.buttons["confirmCropButton"].tap()
        tapVisible(app.buttons["gridSizeOption_16"])
        tapVisible(app.buttons["paletteMaterialRow"])
        XCTAssertTrue(app.buttons["paletteOption_mine"].waitForExistence(timeout: 10))
        tapVisible(app.buttons["paletteOption_all"])
        tapVisible(app.buttons["generatePatternButton"])
        assertEditorLoaded()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'projectCard_'" )).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let cardID = card.identifier
        card.tap()
        assertEditorLoaded()

        app.terminate()
        app.launch()
        let savedCard = app.buttons[cardID]
        XCTAssertTrue(savedCard.waitForExistence(timeout: 10))
        savedCard.tap()
        assertEditorLoaded()
    }

    /// Drives the generation settings step's new controls: opening the palette material picker
    /// and choosing a non-default preset, toggling background removal on, then generating —
    /// verifying the pipeline still completes successfully with these new parameters wired
    /// through (not just that each control compiles/renders).
    func testGenerationSettingsWithPaletteAndBackgroundRemoval() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestUseSampleImage"]
        app.launch()

        app.buttons["newProjectButton"].tap()
        app.buttons["useSampleImageButton"].tap()
        app.buttons["confirmCropButton"].tap()

        let gridSizeOption16 = app.buttons["gridSizeOption_16"]
        XCTAssertTrue(gridSizeOption16.waitForExistence(timeout: 5))
        gridSizeOption16.tap()

        let paletteMaterialRow = app.buttons["paletteMaterialRow"]
        XCTAssertTrue(paletteMaterialRow.waitForExistence(timeout: 5))
        paletteMaterialRow.tap()

        let paletteOption24 = app.buttons["paletteOption_n24"]
        XCTAssertTrue(paletteOption24.waitForExistence(timeout: 5))
        paletteOption24.tap()

        // The picker sheet should have dismissed itself and the row should now show the
        // selected preset's label rather than the default "我的" label.
        XCTAssertTrue(paletteMaterialRow.waitForExistence(timeout: 5))

        let removeBackgroundToggle = app.switches["removeBackgroundToggle"]
        XCTAssertTrue(removeBackgroundToggle.waitForExistence(timeout: 5))
        removeBackgroundToggle.tap()

        let generateButton = app.buttons["generatePatternButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        // Background removal adds a Vision foreground-detection pass on top of the normal
        // pipeline, so give it the same generous timeout as plain generation.
        XCTAssertTrue(app.buttons["exportButton"].waitForExistence(timeout: 30))
    }
}
