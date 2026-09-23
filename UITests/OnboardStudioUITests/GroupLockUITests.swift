import XCTest

// ci-shard: 1
/// J20: lock a finished object, and group objects that belong together (#90).
final class GroupLockUITests: OnboardStudioUITestCase {
    @MainActor
    func testGroupLockUngroupDeleteUndo() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        toolbarMenu("toolbar.addObject", "Lap Timer")
        XCTAssertTrue(sidebarObject("Timer").waitForExistence(timeout: Self.timeout))

        // ⌘-click builds a selection, as in the Finder.
        sidebarObject("Speedometer").click()
        XCUIElement.perform(withKeyModifiers: .command) { sidebarObject("Timer").click() }
        XCTAssertTrue(app.staticTexts["2 Objects"].waitForExistence(timeout: Self.timeout), "No multiple selection")

        menu("Project", "Group")
        XCTAssertTrue(app.staticTexts["Group of 2"].waitForExistence(timeout: Self.timeout), "Not grouped")

        // A group locks as a whole, and a lock keeps the delete key off it too.
        menu("Project", "Lock")
        XCTAssertTrue(app.buttons["object.Speedometer.lock"].waitForExistence(timeout: Self.timeout))
        expect(app.buttons["object.Speedometer.lock"], toRead: "Unlock Speedometer")
        expect(app.buttons["object.Timer.lock"], toRead: "Unlock Timer")
        menu("Project", "Delete Selected Object")
        expectStatus(containing: "Locked objects are not deleted")
        XCTAssertTrue(sidebarObject("Speedometer").exists)

        // Unlock and ungroup: still both selected, now as separate objects.
        menu("Project", "Unlock")
        expect(app.buttons["object.Speedometer.lock"], toRead: "Lock Speedometer")
        menu("Project", "Ungroup")
        XCTAssertTrue(
            app.staticTexts["2 Objects"].waitForExistence(timeout: Self.timeout), "Ungroup lost the selection")

        // One delete for both, and one undo brings both back.
        menu("Project", "Delete Selected Object")
        XCTAssertTrue(sidebarObject("Speedometer").waitForNonExistence(timeout: Self.timeout))
        XCTAssertFalse(sidebarObject("Timer").exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(sidebarObject("Speedometer").waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(sidebarObject("Timer").exists)
    }

    /// Dragging one member of a group on the preview moves the whole group.
    @MainActor
    func testDraggingAGroupMemberMovesTheGroup() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        toolbarMenu("toolbar.addObject", "Lap Timer")
        let before = (speedometer: frame(of: "Speedometer"), timer: frame(of: "Timer"))

        sidebarObject("Speedometer").click()
        XCUIElement.perform(withKeyModifiers: .command) { sidebarObject("Timer").click() }
        menu("Project", "Group")
        XCTAssertTrue(app.staticTexts["Group of 2"].waitForExistence(timeout: Self.timeout))

        // Grab the speedometer in the middle and drag it left.
        let preview = app.descendants(matching: .any)["preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.timeout))
        let area = preview.frame
        let video = fitted(aspect: 16.0 / 9.0, in: area)
        let centre = CGPoint(
            x: video.minX + (before.speedometer.minX + before.speedometer.width / 2) / 100 * video.width,
            y: video.minY + (before.speedometer.minY + before.speedometer.height / 2) / 100 * video.height)
        let origin = preview.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: centre.x - area.minX, dy: centre.y - area.minY))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: -video.width / 10, dy: 0)))

        // Both moved about a tenth of the frame to the left.
        let after = (speedometer: frame(of: "Speedometer"), timer: frame(of: "Timer"))
        XCTAssertEqual(after.speedometer.minX, before.speedometer.minX - 10, accuracy: 2)
        XCTAssertEqual(after.timer.minX, before.timer.minX - 10, accuracy: 2)
    }

    /// An object's X, Y, width and height in percent, read from its inspector.
    @MainActor
    func frame(of label: String) -> CGRect {
        sidebarObject(label).click()
        let read = { (id: String) -> Double in
            let field = self.app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
            return Double(field.value as? String ?? "") ?? .nan
        }
        return CGRect(
            x: read("object.x"), y: read("object.y"), width: read("object.width"), height: read("object.height"))
    }

    func fitted(aspect: Double, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / aspect, rect.height)
        return CGRect(
            x: rect.midX - scale * aspect / 2, y: rect.midY - scale / 2, width: scale * aspect, height: scale)
    }
}
