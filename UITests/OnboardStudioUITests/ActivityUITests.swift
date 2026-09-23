import XCTest

// ci-shard: 3
/// J19: what the status line said stays readable after the next message replaces it (#112).
final class ActivityUITests: OnboardStudioUITestCase {
    @MainActor
    func testEveryStatusMessageIsKeptAndCanBeCopied() throws {
        launch()
        addFixtureVideo()
        menu("Marker", "Add Marker")
        menu("Playback", "Step Forward")
        menu("Marker", "Add Marker")
        // Three messages, each replacing the last in the status line.
        menu("Marker", "Previous Marker")
        expectStatus(containing: "Marker 1")
        menu("Marker", "Next Marker")
        expectStatus(containing: "Marker 2")
        menu("Marker", "Next Marker")
        expectStatus(containing: "No marker that way")

        // Dismissed, the line goes; the history does not.
        app.buttons["status.dismiss"].click()
        XCTAssertTrue(statusLine.waitForNonExistence(timeout: Self.timeout))
        app.typeKey("l", modifierFlags: [.command, .option])
        let entries = app.descendants(matching: .any).matching(identifier: "activity.entry")
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: Self.timeout), "No activity popover")
        let all = entries.allElementsBoundByIndex.map { "\($0.label) \($0.value as? String ?? "")" }
            .joined(separator: "|")
        for said in ["Marker 1", "Marker 2", "No marker that way"] {
            XCTAssertTrue(all.contains(said), "The activity lost “\(said)”: \(all)")
        }
        // Newest first.
        XCTAssertTrue(entries.element(boundBy: 0).label.contains("No marker that way"))

        app.buttons["activity.copy"].click()
        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertTrue(copied.contains("Marker 1") && copied.contains("No marker that way"), copied)
    }
}
