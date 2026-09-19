import XCTest

/// Shared launch and navigation helpers for the journey tests. The app runs with the Testing menu
/// (fixture files instead of open panels) and with state restoration off, so every test starts
/// from a fresh Untitled document.
class OverlayGenUITestCase: XCTestCase {
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
    func launch(tourSeen: Bool = true, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES", "-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO",
            "-tourSeen", tourSeen ? "YES" : "NO", "-uiTesting", "YES", "-showGettingStarted", "YES",
        ]
        app.launchArguments += extraArguments
        app.launchEnvironment["OVERLAYGEN_FIXTURES"] = Self.fixtures.path
        app.launchEnvironment["OVERLAYGEN_TEST_EXPORT_DIR"] = Self.exportDirectory.path
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: Self.timeout), "No window: \(app.debugDescription)")
        launched = app
        return app
    }

    /// `Tests/Fixtures` in the checkout the tests were built from.
    static let fixtures: URL = {
        if let path = ProcessInfo.processInfo.environment["OVERLAYGEN_FIXTURES"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Tests/Fixtures", directoryHint: .isDirectory)
    }()

    /// Where the export sheet writes during tests (the runner's environment or a temp folder).
    static let exportDirectory: URL = {
        if let path = ProcessInfo.processInfo.environment["OVERLAYGEN_TEST_EXPORT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let url = FileManager.default.temporaryDirectory.appending(
            path: "overlaygen-uitests", directoryHint: .isDirectory)
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

    /// Scrolls the nearest scroll view until `element` is inside it (forms in sheets and the
    /// inspector are longer than their window).
    func reveal(_ element: XCUIElement) {
        let sheet = app.sheets.firstMatch
        let scrollView = (sheet.exists ? sheet : app.windows.firstMatch).scrollViews.firstMatch
        guard scrollView.exists else { return }
        var attempts = 0
        while attempts < 8, !scrollView.frame.contains(element.frame) {
            let delta = element.frame.midY < scrollView.frame.midY ? 120.0 : -120.0
            scrollView.scroll(byDeltaX: 0, deltaY: delta)
            attempts += 1
        }
    }

    func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }
}
