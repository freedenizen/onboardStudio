import XCTest

/// #149 and #192: a file that imports badly explains itself, in the window that has room to.
final class ImportReportUITests: OnboardStudioUITestCase {
    /// Adds the noisy fixture, opens the attribute window and points it at that input.
    @MainActor
    func openWindowOnTheNoisyFixture() {
        testing("Add Fixture Data (Noisy CAN)")
        XCTAssertTrue(
            sidebarInput("racechrono-v3-noisy").waitForExistence(timeout: Self.timeout), "Data not listed")
        sidebarInput("racechrono-v3-noisy").click()
        let open = app.buttons["import.open"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.timeout), "No way to open the report")
        reveal(open)
        open.click()
        expectAttributeWindow()
        chooseScope("racechrono-v3-noisy")
    }

    /// The tab strip is a segmented control, whose segments are radio buttons rather than the
    /// pop-up menu `choosePopUpItem` drives.
    @MainActor
    func selectTab(_ name: String) {
        let segment = app.radioButtons[name].exists ? app.radioButtons[name] : app.buttons[name]
        XCTAssertTrue(segment.waitForExistence(timeout: Self.timeout), "No “\(name)” tab")
        segment.click()
    }

    @MainActor
    func testExplainsWhatBecameOfEachColumn() throws {
        launch()
        openWindowOnTheNoisyFixture()
        selectTab("Import")

        let summary = app.staticTexts["import.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout), "No import summary")
        let text = text(of: summary)
        XCTAssertTrue(text.contains("31 columns"), "Summary did not count the columns: \(text)")
        XCTAssertTrue(text.contains("worth a look"), "Summary did not flag anything: \(text)")

        // By default only the columns with something to say; the rest are simply fine.
        let showAll = app.descendants(matching: .any).matching(identifier: "import.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every column")
        let before = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'import.'")).count
        showAll.click()
        let after = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'import.'")).count
        XCTAssertGreaterThan(after, before, "Showing every column revealed nothing new")
    }

    /// The milestone's own example, end to end under the vocabulary of #191: the attribute is
    /// **Brake pressure (front)** and `brake_pressure_front` is the column it is mapped to.
    @MainActor
    func testAPressureAttributeIsMappedToAColumnAndShownInBar() throws {
        launch()
        openWindowOnTheNoisyFixture()
        selectTab("Attributes")

        // Nothing maps it yet and the file does not supply it by name, so its row waits until
        // every attribute is asked for.
        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every attribute")
        showAll.click()

        XCTAssertTrue(
            app.staticTexts["attribute.brakePressureFront"].waitForExistence(timeout: Self.timeout),
            "No Brake pressure (front) row")
        setSource(of: "brakePressureFront", to: "brake_pressure_front")

        // Once it is mapped, the unit the file declared for that column is what it reads in, and
        // bar is one of the units it can then be shown in.
        let shows = app.popUpButtons["attribute.brakePressureFront.displayUnit"]
        XCTAssertTrue(shows.waitForExistence(timeout: Self.timeout), "No display unit for the pressure")
        choosePopUpItem("bar", in: shows)

        let row = app.staticTexts["attribute.brakePressureFront"]
        XCTAssertTrue(
            text(of: row).contains("kPa → bar"), "The row does not report the conversion: \(text(of: row))")
    }

    /// A channel the file names itself is a source to map to, never a row of its own (#191).
    @MainActor
    func testASourceChannelIsNotListedAsAnAttribute() throws {
        launch()
        openWindowOnTheNoisyFixture()
        selectTab("Attributes")

        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout))
        showAll.click()
        XCTAssertFalse(
            app.staticTexts["attribute.canbus:analog_1"].exists,
            "One logger's wiring is listed as though it were part of the vocabulary")
        XCTAssertFalse(app.staticTexts["attribute.canbus:brake_pressure_front"].exists)
    }

    /// #200: ⌘2 shows the import report and ⌘1 the attributes again, from the View menu, while the
    /// attribute window is in front.
    @MainActor
    func testCommandDigitsSwitchTheWindowsView() throws {
        launch()
        openWindowOnTheNoisyFixture()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(
            app.textFields["attribute.speed.source"].waitForExistence(timeout: Self.timeout),
            "⌘1 did not show attributes")
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(
            app.staticTexts["import.summary"].waitForExistence(timeout: Self.timeout), "⌘2 did not show the report")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.textFields["attribute.speed.source"].waitForExistence(timeout: Self.timeout))
    }

    /// #200: *Show Import Report…* opens the window on the report, not on whatever it last showed.
    @MainActor
    func testShowImportReportOpensOnTheReport() throws {
        launch()
        openWindowOnTheNoisyFixture()
        XCTAssertTrue(
            app.staticTexts["import.summary"].waitForExistence(timeout: Self.timeout),
            "The window did not open on the report")
    }
}
