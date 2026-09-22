import XCTest

/// #111, #89 and #192: telling the app where an attribute comes from and what it is read and
/// shown in, from the window that does it.
final class AttributeMappingUITests: OnboardStudioUITestCase {
    /// Opens the attribute window on the data input that was added, which is the scope every one
    /// of these tests works in.
    @MainActor
    func openWindowOnTheFixtureInput(_ label: String = "racerender-basic") {
        sidebarInput(label).click()
        let open = app.buttons["attributes.open"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.timeout), "No way to open the attribute window")
        reveal(open)
        open.click()
        let scope = app.popUpButtons["attributes.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: Self.timeout), "The attribute window did not open")
        choosePopUpItem(label, in: scope)
    }

    @MainActor
    func testMapsAnAttributeToAColumnAndUnits() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        // Reading the column as mph and showing it in km/h are two separate choices; making the
        // first must not make the second.
        let reads = app.popUpButtons["attribute.speed.sourceUnit"]
        XCTAssertTrue(reads.waitForExistence(timeout: Self.timeout), "No Speed row in the attribute table")
        choosePopUpItem("mph", in: reads)
        XCTAssertTrue(
            text(of: app.staticTexts["attribute.speed"]).contains("mph"),
            "The row does not report the unit it now reads")

        choosePopUpItem("km/h", in: app.popUpButtons["attribute.speed.displayUnit"])
        XCTAssertTrue(
            text(of: app.staticTexts["attribute.speed"]).contains("mph → km/h"),
            "The row does not report reading one unit and showing another")
    }

    /// An attribute the file does not supply is still mappable — that is the point of asking the
    /// question attribute-first — but it stays out of the way until asked for.
    @MainActor
    func testHidesAttributesTheFileDoesNotSupplyUntilAsked() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every attribute")
        let pressure = app.staticTexts["attribute.brakePressureFront"]
        XCTAssertFalse(pressure.exists, "An attribute the file does not supply is shown unasked")

        showAll.click()
        XCTAssertTrue(
            pressure.waitForExistence(timeout: Self.timeout), "Showing every attribute left one out")
    }

    /// The window edits whichever level is chosen, and the global mapping is reachable without a
    /// project being open at all.
    @MainActor
    func testTheWindowEditsTheLevelItIsPointedAt() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        let scope = app.popUpButtons["attributes.scope"]
        choosePopUpItem("All projects", in: scope)
        // The global mapping is still editable: a column can be typed even for a file that is
        // not open, which is what a mapping meant to apply to every later import needs.
        XCTAssertTrue(app.textFields["attribute.speed.source"].waitForExistence(timeout: Self.timeout))
        choosePopUpItem("This project", in: scope)
        XCTAssertTrue(app.popUpButtons["attribute.speed.sourceUnit"].waitForExistence(timeout: Self.timeout))
    }

    /// #196: a row nobody has pinned is still being fed by a column, and the table has to say
    /// which. The fixture's Speed comes from a column called `Speed`, and nothing is mapped.
    @MainActor
    func testARowSaysWhichColumnItIsFedBy() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        let row = app.staticTexts["attribute.speed"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No Speed row")
        XCTAssertTrue(
            text(of: row).lowercased().contains("speed"),
            "The row does not name the column it comes from: \(text(of: row))")

        // And the field's placeholder names it, rather than a bare "Automatic".
        let source = app.textFields["attribute.speed.source"]
        XCTAssertTrue(source.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(
            (source.placeholderValue ?? "").contains("Automatic ("),
            "Automatic does not say what it resolves to: \(source.placeholderValue ?? "nil")")
    }
}
