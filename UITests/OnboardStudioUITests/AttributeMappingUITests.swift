import XCTest

// ci-shard: 1
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
        expectAttributeWindow()
        chooseScope(label)
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

        chooseScope("All projects")
        // The global mapping is still editable: a column can be typed even for a file that is
        // not open, which is what a mapping meant to apply to every later import needs.
        XCTAssertTrue(app.textFields["attribute.speed.source"].waitForExistence(timeout: Self.timeout))
        chooseScope("This project")
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

    /// Whether keyboard focus is in `element`: the field editor that takes the typing is the
    /// field's child, so the field itself may not report focus while it is being edited.
    @MainActor
    func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
        return element.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch.exists
    }

    /// The text fields of the table, top to bottom, which is the order Tab has to visit them in.
    @MainActor
    func tableTextFields() -> [XCUIElement] {
        let field = "identifier ENDSWITH '.source' OR identifier ENDSWITH '.threshold'"
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'attribute.' AND (\(field))")
        return app.textFields.matching(predicate).allElementsBoundByIndex
            .filter { $0.isHittable }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// #200: Tab walks the table in reading order — down the rows, one text field after the next —
    /// whether or not the Mac's Keyboard navigation setting sends it through the pop-ups too.
    @MainActor
    func testTabWalksTheTableInReadingOrder() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        let fields = tableTextFields()
        XCTAssertGreaterThanOrEqual(fields.count, 3, "Too few rows to walk")
        fields[0].click()
        XCTAssertTrue(hasKeyboardFocus(fields[0]), "Clicking the first field did not focus it")
        for next in fields.dropFirst().prefix(2) {
            // Up to four stops per row: the field, its column menu and the two unit pop-ups.
            var arrived = false
            for _ in 0..<4 where !arrived {
                app.typeKey(.tab, modifierFlags: [])
                arrived = hasKeyboardFocus(next)
            }
            XCTAssertTrue(arrived, "Tab did not reach \(next.identifier) in reading order")
        }
    }

    /// #200: the whole of mapping an attribute, without the mouse — ⌘F to the filter, a word,
    /// Return to the first row it leaves, a column name, Return.
    @MainActor
    func testFilterAndReturnMapAnAttributeWithoutTheMouse() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        app.typeKey("f", modifierFlags: .command)
        app.typeText("pressure (front)")
        // Filtering searches every attribute, not only the ones this file supplies.
        let row = app.staticTexts["attribute.brakePressureFront"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The filter did not find the attribute")
        XCTAssertFalse(app.staticTexts["attribute.speed"].exists, "The filter left other attributes in")

        app.typeText("\n")
        let source = app.textFields["attribute.brakePressureFront.source"]
        XCTAssertTrue(hasKeyboardFocus(source), "Return in the filter did not go to the row")
        app.typeText("brake_pressure_front\n")
        expect(row, toContain: "brake_pressure_front")
    }

    /// #200: Escape abandons a column name half typed, and the row is as it was.
    @MainActor
    func testEscapeAbandonsATypedColumn() throws {
        launch()
        addFixtureData()
        openWindowOnTheFixtureInput()

        let source = app.textFields["attribute.speed.source"]
        XCTAssertTrue(source.waitForExistence(timeout: Self.timeout))
        source.click()
        source.typeText("nonsense")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(source.value as? String ?? "", "", "Escape left the typing in the field")
        XCTAssertFalse(
            text(of: app.staticTexts["attribute.speed"]).contains("nonsense"), "The abandoned column was mapped")
    }

    /// #200: Project ▸ Map Attributes… (⌥⌘A) opens the window on the data file that is selected,
    /// which is the file the user was looking at when they asked.
    @MainActor
    func testTheShortcutOpensTheWindowOnTheSelectedFile() throws {
        launch()
        addFixtureData()
        sidebarInput("racerender-basic").click()
        app.typeKey("a", modifierFlags: [.command, .option])
        expectAttributeWindow()
        expect(app.staticTexts["attributes.explanation"], toContain: "This file only")
    }
}
