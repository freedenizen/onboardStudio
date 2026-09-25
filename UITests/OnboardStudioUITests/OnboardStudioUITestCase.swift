import XCTest

/// Shared launch and navigation helpers for the journey tests. The app runs with the Testing menu
/// (fixture files instead of open panels) and with state restoration off, so every test starts
/// from a fresh Untitled document.
/// Base class for the XCUITest journeys.
///
/// CI shards these across three runners **by test class** (`.github/workflows/ci.yml`), balanced
/// by measured time, so a new class needs adding to one of the shards or it will never run there.
/// `Scripts/ui-tests.sh` runs the lot locally and is unaffected.
class OnboardStudioUITestCase: XCTestCase {
    private var launched: XCUIApplication?
    /// The app under test; `launch()` must have run.
    var app: XCUIApplication {
        guard let launched else { fatalError("launch() must run before the app is used") }
        return launched
    }

    /// Longer waits on CI runners, which are several times slower than a laptop.
    static let timeout: TimeInterval = ProcessInfo.processInfo.environment["CI"] == nil ? 10 : 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        launched?.terminate()
        launched = nil
    }

    /// Launches the app on an empty document. `tourSeen: false` shows the first-run tour.
    @discardableResult
    func launch(tourSeen: Bool = true, launcher: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES", "-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO",
            "-tourSeen", tourSeen ? "YES" : "NO", "-uiTesting", "YES", "-showGettingStarted", "YES",
            // Sparkle's first-launch "Check for updates automatically?" prompt would take key status.
            "-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES",
            // Most journeys start on a blank project; the launcher tests ask for the welcome window.
            "-skipLauncher", launcher ? "NO" : "YES", "-showLauncherAtLaunch", "YES",
            // A test that hid the inspector (#280) must not leave it hidden for the next one.
            "-showInspector", "YES",
        ]
        app.launchArguments += extraArguments
        app.launchEnvironment["ONBOARD_FIXTURES"] = Self.fixtures.path
        app.launchEnvironment["ONBOARD_TEST_EXPORT_DIR"] = Self.exportDirectory.path
        // A fresh, empty set of the user's own templates for every launch (#44).
        let templates = FileManager.default.temporaryDirectory.appending(
            path: "onboard-uitests-templates-\(UUID().uuidString)", directoryHint: .isDirectory)
        app.launchEnvironment["ONBOARD_TEST_TEMPLATES_DIR"] = templates.path
        app.launch()  // the app activates itself when the editor appears (UITestSupport.editorAppeared)
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: Self.timeout), "No window: \(app.debugDescription)")
        launched = app
        return app
    }

    /// `Tests/Fixtures` in the checkout the tests were built from.
    static let fixtures: URL = {
        if let path = ProcessInfo.processInfo.environment["ONBOARD_FIXTURES"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Tests/Fixtures", directoryHint: .isDirectory)
    }()

    /// Where the export sheet writes during tests (the runner's environment or a temp folder).
    static let exportDirectory: URL = {
        if let path = ProcessInfo.processInfo.environment["ONBOARD_TEST_EXPORT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let url = FileManager.default.temporaryDirectory.appending(
            path: "onboard-uitests", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Menus

    /// Clicks `item` in the top-level `menu` (e.g. `menu("Project", "Delete Selected Object")`).
    func menu(_ menu: String, _ item: String) {
        let bar = app.menuBars.menuBarItems[menu]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout), "No \(menu) menu")
        bar.click()
        let entry = bar.menus.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No \(menu) ▸ \(item)")
        entry.click()
    }

    /// Clicks `item` inside the `submenu` of the top-level `menu`.
    func menu(_ menu: String, _ submenu: String, _ item: String) {
        let bar = app.menuBars.menuBarItems[menu]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout), "No \(menu) menu")
        bar.click()
        let sub = bar.menus.menuItems[submenu]
        XCTAssertTrue(sub.waitForExistence(timeout: Self.timeout), "No \(menu) ▸ \(submenu)")
        sub.hover()
        let entry = sub.menus.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No \(menu) ▸ \(submenu) ▸ \(item)")
        entry.click()
    }

    func testing(_ item: String) { menu("Testing", item) }

    /// Clicks `item` in a toolbar menu button's menu (the menu bar holds items with the same
    /// titles, so the query is scoped to the button).
    func toolbarMenu(_ identifier: String, _ item: String) {
        let button = app.menuButtons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "No toolbar menu \(identifier)")
        button.click()
        let entry = button.menus.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No \(identifier) ▸ \(item)")
        entry.click()
    }

    /// Chooses an item in a pop-up found by identifier rather than by the value it happens to
    /// show, which `choose(_:inPopUpShowing:)` needs and a table of near-identical pop-ups cannot
    /// give.
    func choosePopUpItem(_ item: String, in popUp: XCUIElement) {
        XCTAssertTrue(popUp.waitForExistence(timeout: Self.timeout), "No pop-up to choose “\(item)” in")
        reveal(popUp)
        popUp.click()
        let entry = popUp.menus.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No pop-up item “\(item)”")
        entry.click()
    }

    /// Waits for the attribute window, whose sidebar is how its scope is chosen.
    func expectAttributeWindow() {
        let sidebar = app.descendants(matching: .any).matching(identifier: "attributes.scope").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: Self.timeout), "The attribute window did not open")
    }

    /// Points the attribute window at a level of the mapping chain: *All projects*, *This project*
    /// or a data file, by its label (#200). A sidebar row, found by identifier because the editor's
    /// own sidebar lists the same file under the same name.
    func chooseScope(_ label: String) {
        let identifier =
            switch label {
            case "All projects": "attributes.scope.global"
            case "This project": "attributes.scope.project"
            default: "attributes.scope.input.\(label)"
            }
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No scope “\(label)” in the attribute window")
        row.click()
    }

    /// Types the column an attribute is read from. A field rather than a pop-up because a list of
    /// forty columns is not something to hunt through, and because a menu that long scrolls its
    /// items out of the accessibility tree (#195).
    func setSource(of attribute: String, to column: String) {
        let field = app.textFields["attribute.\(attribute).source"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "No source field for \(attribute)")
        reveal(field)
        field.click()
        app.typeKey("a", modifierFlags: .command)
        field.typeText(column + "\n")
    }

    /// Chooses `item` in the pop-up button whose current value is `value`.
    func choose(_ item: String, inPopUpShowing value: String) {
        let popUp = app.popUpButtons.matching(NSPredicate(format: "value == %@", value)).firstMatch
        XCTAssertTrue(popUp.waitForExistence(timeout: Self.timeout), "No pop-up showing “\(value)”")
        reveal(popUp)
        popUp.click()
        let format = "title BEGINSWITH %@ OR label BEGINSWITH %@"
        var entry = popUp.menus.menuItems.matching(NSPredicate(format: format, item, item)).firstMatch
        if !entry.waitForExistence(timeout: 2) {
            // Pop-ups inside sheets open their menu as a separate window.
            entry = app.menuItems.matching(NSPredicate(format: format, item, item)).firstMatch
        }
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No pop-up item “\(item)”")
        entry.click()
    }

    /// The first two items of the Edit menu — Undo and Redo — as they read with the menu open.
    @MainActor
    func undoRedoTitles() -> (undo: String, redo: String) {
        let edit = app.menuBarItems["Edit"]
        edit.click()
        let items = edit.menus.firstMatch.menuItems
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: Self.timeout), "The Edit menu did not open")
        let titles = (items.element(boundBy: 0).title, items.element(boundBy: 1).title)
        app.typeKey(.escape, modifierFlags: [])
        return titles
    }

    // MARK: - Fixtures through the Testing menu

    func addFixtureVideo() {
        testing("Add Fixture Video")
        XCTAssertTrue(sidebarInput("test-3s").waitForExistence(timeout: Self.timeout), "Video not listed")
    }

    func addFixtureData() {
        testing("Add Fixture Data (RaceRender)")
        XCTAssertTrue(sidebarInput("racerender-basic").waitForExistence(timeout: Self.timeout), "Data not listed")
    }

    // MARK: - Elements

    func sidebarInput(_ label: String) -> XCUIElement { app.staticTexts["input.\(label)"] }
    func sidebarObject(_ label: String) -> XCUIElement { app.staticTexts["object.\(label)"] }
    var statusLine: XCUIElement { app.staticTexts["status.message"] }
    var transportTime: XCUIElement { app.staticTexts["transport.time"] }

    /// Waits until the status line contains `text`.
    func expectStatus(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: statusLine)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(
            result, .completed, "Status line never said “\(text)”; last: \(statusLine.value ?? "nil")",
            file: file, line: line)
    }

    /// Waits until the element's value or label equals `text`.
    func expect(_ element: XCUIElement, toRead text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@ OR label == %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(result, .completed, "Expected “\(text)”, got \(element.value ?? "nil")", file: file, line: line)
    }

    /// Waits until the element's value or label contains `text`, for readouts that carry a number
    /// alongside their wording.
    func expect(_ element: XCUIElement, toContain text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: Self.timeout)
        XCTAssertEqual(
            result, .completed, "Expected something containing “\(text)”, got \(element.value ?? "nil")",
            file: file, line: line)
    }

    /// Scrolls until `element` can be clicked (forms in sheets and the inspector are longer than
    /// their window).
    ///
    /// The nearest scroll view first, which is what most callers need. Failing that, every scroll
    /// view in the app: an element in a *different window* — the attribute table has its own —
    /// is not in the first window's scroll view at all, and a lazy list leaves an off-screen row
    /// with no frame to compare against, so `isHittable` is the only honest test.
    func reveal(_ element: XCUIElement) {
        let sheet = app.sheets.firstMatch
        let nearest = (sheet.exists ? sheet : app.windows.firstMatch).scrollViews.firstMatch
        if nearest.exists {
            var attempts = 0
            while attempts < 8, !nearest.frame.contains(element.frame) {
                let delta = element.frame.midY < nearest.frame.midY ? 120.0 : -120.0
                nearest.scroll(byDeltaX: 0, deltaY: delta)
                attempts += 1
            }
        }
        guard !element.isHittable else { return }
        for scrollView in app.scrollViews.allElementsBoundByIndex {
            for _ in 0..<12 {
                if element.isHittable { return }
                scrollView.scroll(byDeltaX: 0, deltaY: -80)
            }
            for _ in 0..<12 {
                if element.isHittable { return }
                scrollView.scroll(byDeltaX: 0, deltaY: 80)
            }
        }
    }

    func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
}
