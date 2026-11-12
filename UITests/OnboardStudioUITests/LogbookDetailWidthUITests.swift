import XCTest

// ci-shard: 4
/// #483: a session's detail in the Logbook forgot the width it was dragged to — after a visit to
/// Trends, after the session went out of the table and came back, and the next time the app
/// opened. It stays as wide as it was left.
final class LogbookDetailWidthUITests: OnboardStudioUITestCase {
    /// Something only a session's detail has.
    private var detail: XCUIElement { app.staticTexts["logbook.detail.laps"] }

    /// The detail's left edge: the split view's divider furthest to the right.
    private var divider: XCUIElement {
        let splitters = app.windows["Logbook"].splitters.allElementsBoundByIndex
        return splitters.max { $0.frame.midX < $1.frame.midX } ?? app.windows["Logbook"].splitters.firstMatch
    }

    /// How wide the detail is: from its left edge to the window's right edge.
    private var detailWidth: CGFloat { app.windows["Logbook"].frame.maxX - divider.frame.maxX }

    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    @MainActor
    private func showASessionsDetail() {
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "No detail for the selected session")
    }

    @MainActor
    private func choose(_ view: String) {
        (app.radioButtons[view].exists ? app.radioButtons[view] : app.buttons[view]).click()
    }

    /// The widths are read off the window rather than assumed: how far the detail can be dragged
    /// depends on the window, which on a small screen (CI's is 1,024 points wide) has room for
    /// less than the detail's own 420-point limit, because the sessions keep their minimum.
    @MainActor
    func testTheDetailStaysAsWideAsItWasDragged() throws {
        launch(logbook: true)
        showASessionsDetail()
        XCTAssertEqual(detailWidth, 320, accuracy: 2, "It starts at its narrowest")

        // Its left edge, dragged 60 points to the left: wider, by no more than it was dragged.
        let grab = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.click(forDuration: 0.3, thenDragTo: grab.withOffset(CGVector(dx: -60, dy: 0)))
        let dragged = detailWidth
        XCTAssertGreaterThan(dragged, 335, "Dragging its edge did not widen it")
        XCTAssertLessThanOrEqual(dragged, 383, "It went further than it was dragged")

        // Trends keeps the session beside it, as wide as it was left, and so do the sessions after.
        choose("Trends")
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "The session went when Trends came")
        XCTAssertEqual(detailWidth, dragged, accuracy: 1, "Trends changed the width")
        choose("Sessions")
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(detailWidth, dragged, accuracy: 1, "A visit to Trends lost the width")

        // Searched out of the table, the session has no detail; it comes back at that width too.
        let search = app.searchFields.firstMatch
        search.click()
        search.typeText("zzzz")
        XCTAssertTrue(detail.waitForNonExistence(timeout: Self.timeout))
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        XCTAssertEqual(detailWidth, dragged, accuracy: 1, "Losing and regaining the selection lost the width")

        // Dragged as far as it goes it stops: at its widest, or sooner where the window is small.
        let far = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        far.click(forDuration: 0.3, thenDragTo: far.withOffset(CGVector(dx: -300, dy: 0)))
        let widest = detailWidth
        XCTAssertGreaterThanOrEqual(widest, dragged - 1, "Dragging further left made it narrower")
        XCTAssertLessThanOrEqual(widest, 422, "It can be dragged past its widest")

        // Then a little narrower, to a width that is neither where it starts nor where it stops.
        let back = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        back.click(forDuration: 0.3, thenDragTo: back.withOffset(CGVector(dx: 20, dy: 0)))
        let left = detailWidth
        XCTAssertEqual(left, widest - 20, accuracy: 4, "Dragging its edge right did not narrow it")

        // And the next time the app opens, it is as wide as it was left.
        app.terminate()
        launch(logbook: true, extraArguments: ["-keepPaneWidths", "YES"])
        showASessionsDetail()
        XCTAssertEqual(detailWidth, left, accuracy: 2, "The next launch lost the width")
    }
}
