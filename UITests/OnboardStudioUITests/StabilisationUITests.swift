import XCTest

// ci-shard: 2
/// J26, J27 and J28: steady a shaky video (#262, #263, #264). The fixture video has no motion record and CI has
/// no Gyroflow, so this drives what each choice says when what it needs is missing.
final class StabilisationUITests: OnboardStudioUITestCase {
    @MainActor
    func testEachWayToSteadySaysWhatItNeeds() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()
        let steady = app.popUpButtons["stabilisation.method"]
        XCTAssertTrue(steady.waitForExistence(timeout: Self.timeout), "No Stabilisation control in the inspector")
        reveal(steady)

        choosePopUpItem("From camera motion data", in: steady)
        XCTAssertTrue(text(containing: "no camera motion record").waitForExistence(timeout: Self.timeout))

        choosePopUpItem("With Gyroflow", in: steady)
        // Either Gyroflow is here to run, or the inspector says how to install it.
        let start = app.buttons["stabilisation.gyroflowStart"]
        let install = text(containing: "Gyroflow is not installed")
        XCTAssertTrue(
            start.waitForExistence(timeout: Self.timeout) || install.exists,
            "Neither a way to run Gyroflow nor how to install it")

        // One undo step per choice.
        menu("Edit", "Undo Stabilise Video")
        XCTAssertTrue(text(containing: "no camera motion record").waitForExistence(timeout: Self.timeout))
    }

    @MainActor
    func testAVideoIsSteadiedFromItsOwnPicture() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()
        let steady = app.popUpButtons["stabilisation.method"]
        XCTAssertTrue(steady.waitForExistence(timeout: Self.timeout), "No Stabilisation control in the inspector")
        choosePopUpItem("From the picture", in: steady)
        let measure = app.buttons["stabilisation.measure"]
        XCTAssertTrue(measure.waitForExistence(timeout: Self.timeout), "No Measure Motion button")
        reveal(measure)
        measure.click()
        // Three seconds of video are measured in moments; then the inspector says it is steadied.
        XCTAssertTrue(
            text(containing: "Steadied from the picture").waitForExistence(timeout: 60), "It was not steadied")
    }

    func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", fragment)).firstMatch
    }
}
