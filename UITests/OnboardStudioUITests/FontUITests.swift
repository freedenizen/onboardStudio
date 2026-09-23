import XCTest

// ci-shard: 2
/// J15: choose the font a project's text is drawn in, then give one object its own (#118).
final class FontUITests: OnboardStudioUITestCase {
    @MainActor
    func testProjectFontThenAnObjectsOwnAndUndo() throws {
        launch()
        // With nothing selected the inspector is the project's: its font is every object's.
        let projectFamily = app.popUpButtons["project.font.family"]
        chooseFamily("Futura", in: projectFamily)
        expect(app.popUpButtons["project.font.face"], toRead: "Bold")

        addFixtureData()
        toolbarMenu("toolbar.addObject", "Lap Timer")
        XCTAssertTrue(sidebarObject("Timer").waitForExistence(timeout: Self.timeout))
        // A new object follows the project, and says which font that is.
        let family = app.popUpButtons["object.font.family"]
        expect(family, toRead: "Project Font (Futura Bold)")
        XCTAssertTrue(app.sliders["object.font.size"].exists, "No text size for a timer")

        // Its own font keeps the face it had where the family has it; then a lighter face.
        chooseFamily("Helvetica Neue", in: family)
        let face = app.popUpButtons["object.font.face"]
        expect(face, toRead: "Bold")
        choosePopUpItem("Light", in: face)
        expect(face, toRead: "Light")

        // One undo step per choice, each named for what it takes back.
        app.typeKey("z", modifierFlags: .command)
        expect(face, toRead: "Bold")
        app.typeKey("z", modifierFlags: .command)
        expect(family, toRead: "Project Font (Futura Bold)")
        XCTAssertFalse(face.exists, "The typeface belongs to a chosen font")
    }

    /// Picks a family by typing its name: the list is every font on the Mac, far longer than a
    /// menu shows, and the rows scrolled out of sight are not in the accessibility tree (#195).
    @MainActor
    func chooseFamily(_ name: String, in popUp: XCUIElement) {
        XCTAssertTrue(popUp.waitForExistence(timeout: Self.timeout), "No font pop-up")
        reveal(popUp)
        popUp.click()
        XCTAssertTrue(popUp.menus.firstMatch.waitForExistence(timeout: Self.timeout), "The font menu did not open")
        app.typeText(name)
        app.typeKey(.return, modifierFlags: [])
        expect(popUp, toRead: name)
    }
}
