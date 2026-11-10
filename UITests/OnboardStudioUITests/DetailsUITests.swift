import XCTest

// ci-shard: 3
/// J16: the project's details fill in from the data, and a title card shows them (#74).
final class DetailsUITests: OnboardStudioUITestCase {
    @MainActor
    func testDetailsFillFromTheDataAndATitleCardShowsThem() throws {
        launch()
        testing("Add Fixture Data (RaceChrono)")
        XCTAssertTrue(sidebarInput("racechrono-v3").waitForExistence(timeout: Self.timeout), "Data not listed")

        // The file counts seconds since 1970. The inspector says when it ran rather than showing
        // the count, and says what the start position means (#457).
        let note = app.staticTexts["sync.startPosition.clock"]
        XCTAssertTrue(note.waitForExistence(timeout: Self.timeout), "No word on the file's clock times")
        expect(note, toContain: "Its first sample is at 1767150797 s")
        let raw = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '1767150797 –'")).firstMatch
        XCTAssertFalse(raw.exists, "The time range is a count of seconds since 1970")

        // The file named its track and driver; adding it filled them in.
        menu("Project", "Show Project Details")
        let track = app.textFields["details.track"]
        XCTAssertTrue(track.waitForExistence(timeout: Self.timeout), "No Details section")
        expect(track, toRead: "Test Circuit")
        expect(app.textFields["details.driver"], toRead: "OnboardStudio")

        // What the file cannot know, the driver types.
        let car = app.textFields["details.car"]
        reveal(car)
        car.click()
        car.typeText("M2 Competition\n")
        expect(car, toRead: "M2 Competition")

        // A detail of the owner's own.
        let addDetail = app.buttons["Add Detail…"]
        reveal(addDetail)
        addDetail.click()
        let name = app.popovers.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "No name field for a new detail")
        name.click()
        name.typeText("Tyres\n")
        XCTAssertTrue(app.textFields["details.extra.Tyres"].waitForExistence(timeout: Self.timeout))

        // A title card names the details; the menu says what each currently stands for.
        toolbarMenu("toolbar.addObject", "Title Card")
        let text = app.textFields["text.content"]
        expect(text, toRead: "{track} · {date}")
        let insert = app.menuButtons["text.insertDetail"]
        reveal(insert)
        insert.click()
        let carItem = insert.menus.menuItems["Car (M2 Competition)"]
        XCTAssertTrue(carItem.waitForExistence(timeout: Self.timeout), "The menu does not say what Car is")
        carItem.click()
        expect(text, toRead: "{track} · {date} {car}")
        app.typeKey("z", modifierFlags: .command)
        expect(text, toRead: "{track} · {date}")
        // The logbook's keys are offered too, under their own heading (#433).
        insert.click()
        let trackDays = insert.menus.menuItems["Track Days Here"]
        XCTAssertTrue(trackDays.waitForExistence(timeout: Self.timeout), "No logbook keys in Insert Detail")
        trackDays.click()
        expect(text, toRead: "{track} · {date} {trackDays}")
    }
}
