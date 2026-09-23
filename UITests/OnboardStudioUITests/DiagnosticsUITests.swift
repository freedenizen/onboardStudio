import XCTest

// ci-shard: 2
/// J22: everything a bug report needs, in one file the user sends themselves (#152).
final class DiagnosticsUITests: OnboardStudioUITestCase {
    @MainActor
    func testExportDiagnosticsWritesOneZipWithTheProjectAndItsData() throws {
        launch()
        addFixtureData()
        let folder = Self.exportDirectory
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        menu("Help", "Export Diagnostics…")
        expectStatus(containing: "Attach it to your bug report")
        let written = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .subtracting(before).filter { $0.hasPrefix("Onboard Studio Diagnostics") && $0.hasSuffix(".zip") }
        let name = try XCTUnwrap(written.first, "No diagnostics zip in \(folder.path)")
        let zip = try Data(contentsOf: folder.appending(path: name))
        defer { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
        // A zip's directory names its members in plain text.
        for member in ["about.txt", "log.txt", "activity.txt", "project.json", "data/racerender-basic.json"] {
            XCTAssertNotNil(zip.range(of: Data(member.utf8)), "The bundle has no \(member)")
        }
    }
}
