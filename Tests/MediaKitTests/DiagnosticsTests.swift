import Foundation
import Testing

@testable import Importers
@testable import MediaKit

@Suite("Diagnostics (#152)")
struct DiagnosticsTests {
    @Test func aBundleIsAZipOfTheFilesInAFolderNamedForIt() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Diag \(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try Diagnostics.writeBundle(
            ["about.txt": Data("Onboard Studio".utf8), "data/session.json": Data("{}".utf8)], to: url)
        let zip = try ZipArchive(contentsOf: url)
        let folder = url.deletingPathExtension().lastPathComponent
        #expect(try zip.contents(of: "\(folder)/about.txt") == Data("Onboard Studio".utf8))
        #expect(try zip.contents(of: "\(folder)/data/session.json") == Data("{}".utf8))
        // Written again, it replaces the old one rather than failing.
        try Diagnostics.writeBundle(["about.txt": Data("again".utf8)], to: url)
        #expect(try ZipArchive(contentsOf: url).contents(of: "\(folder)/about.txt") == Data("again".utf8))
    }

    @Test func theLogOfThisLaunchCanBeReadBack() {
        let start = Date().addingTimeInterval(-1)
        let marker = "diagnostics-test-\(UUID().uuidString)"
        Diagnostics.activity.info("\(marker, privacy: .public)")
        #expect(Diagnostics.logText(since: start).contains(marker))
    }

    @Test func crashReportsAreThisAppsAndRecent() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recent = folder.appending(path: "OnboardStudio-2026-09-23-101010.ips")
        let old = folder.appending(path: "OnboardStudio-2026-01-01-101010.ips")
        let other = folder.appending(path: "Safari-2026-09-23-101010.ips")
        for file in [recent, old, other] { try Data("{}".utf8).write(to: file) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60 * 86_400)], ofItemAtPath: old.path)
        #expect(Diagnostics.crashReports(within: 14, in: folder).map(\.lastPathComponent) == [recent.lastPathComponent])
    }
}
