import XCTest

// ci-shard: 2
/// J18: the editor can be used without seeing its icons — every control and status glyph is
/// named for VoiceOver, and the objects on the preview can be found, selected and moved (#79,
/// #153).
final class AccessibilityUITests: OnboardStudioUITestCase {
    /// Apple's own audit, narrowed to what this app controls: a button, menu button or image with
    /// no name a person can understand. The rest of what the audit reports is SwiftUI's own
    /// containers, which have nothing to say.
    @MainActor
    func testEveryControlHasAName() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        var unnamed: [String] = []
        try app.performAccessibilityAudit(for: .sufficientElementDescription) { issue in
            guard let element = issue.element,
                [.button, .menuButton, .image, .popUpButton, .checkBox].contains(element.elementType)
            else { return true }
            unnamed.append("\(issue.compactDescription): \(element.identifier) \(element.label)")
            return true
        }
        XCTAssertEqual(unnamed, [], "Controls VoiceOver cannot name")
        // The toolbar's menus in particular were read by their symbols' names.
        XCTAssertEqual(app.menuButtons["toolbar.addObject"].label, "Add Object")
        XCTAssertEqual(app.menuButtons["toolbar.layout"].label, "Layout")
    }

    /// Text reads against what is behind it in the light appearance, which is what CI runners and
    /// most users have, as well as in the appearance the Mac is set to. An element reaching past
    /// the window — a data lane longer than the visible timeline — is measured partly against
    /// whatever is outside it, so only elements inside the window are held to it.
    @MainActor
    func testTextHasContrastInBothAppearances() throws {
        for arguments in [["-NSRequiresAquaSystemAppearance", "YES"], []] {
            launch(extraArguments: arguments)
            addFixtureVideo()
            addFixtureData()
            toolbarMenu("toolbar.addObject", "Speedometer")
            let window = app.windows.firstMatch.frame
            var failed: [String] = []
            try app.performAccessibilityAudit(for: .contrast) { issue in
                guard let element = issue.element, window.contains(element.frame),
                    issue.compactDescription.localizedCaseInsensitiveContains("failed")
                else { return true }
                failed.append("\(element.identifier) \(element.label) \(element.frame)")
                return true
            }
            XCTAssertEqual(failed, [], "Text that fails contrast with \(arguments)")
            app.terminate()
        }
    }

    /// The preview is drawn rather than built from controls; its objects are exposed one by one.
    @MainActor
    func testTheObjectsOnThePreviewCanBeFoundAndSelected() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        let speedometer = app.buttons["preview.object.Speedometer"]
        XCTAssertTrue(speedometer.waitForExistence(timeout: Self.timeout), "The preview does not list its objects")
        XCTAssertEqual(speedometer.value as? String, "Selected")
        XCTAssertGreaterThan(speedometer.frame.width, 10, "The element is not where the object is")
        // Selecting something else says so on the element too.
        sidebarInput("test-3s").click()
        let deselected = NSPredicate(format: "value == nil OR value == ''")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: deselected, object: speedometer)], timeout: 10),
            .completed)
    }
}
