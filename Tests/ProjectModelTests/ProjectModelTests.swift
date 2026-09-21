import Foundation
import Testing

@testable import ProjectModel

@Test func schemaVersionIsPositive() {
    #expect(Project.currentSchemaVersion >= 1)
}

/// Nothing rewrites Version.swift — the release workflow only overrides MARKETING_VERSION for
/// the bundle — so the constant silently drifted to 0.18.1 while 0.19.0 shipped, and both
/// `onboard --version` and the launcher reported the wrong number. Tying the two together stops
/// that happening again.
@Test func marketingVersionMatchesTheProjectFile() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let yaml = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
    let line = try #require(yaml.split(separator: "\n").first { $0.contains("MARKETING_VERSION") })
    let quoted = line.split(separator: "\"")
    try #require(quoted.count >= 2)
    #expect(String(quoted[1]) == OnboardStudioVersion.marketing)
}

@Test func marketingVersionLooksSemantic() {
    let parts = OnboardStudioVersion.marketing.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}

@Suite("SyncSettings")
struct SyncSettingsTests {
    @Test func identityMapsTimeUnchanged() {
        #expect(SyncSettings.identity.inputTime(forProjectTime: 12.5) == 12.5)
        #expect(SyncSettings.identity.projectTime(forInputTime: 12.5) == 12.5)
    }

    @Test func offsetStartAndSpeedCompose() {
        let sync = SyncSettings(startPositionInInput: 10, offsetInProject: 2, playSpeed: 2)
        // Project t=2 → input 10; project t=3 → input 12 (double speed).
        #expect(sync.inputTime(forProjectTime: 2) == 10)
        #expect(sync.inputTime(forProjectTime: 3) == 12)
        #expect(sync.projectTime(forInputTime: 12) == 3)
    }

    @Test func anInputNudgedBeforeTheProjectStartsLosesItsHead() {
        // #131: nudging a video earlier is how you sync a camera that started before the logger,
        // and one press from zero goes negative. Nothing can be placed before the project starts —
        // AVFoundation fails the whole composition if asked — so that part is not used.
        let early = SyncSettings(offsetInProject: -0.1)
        #expect(early.startInProject == 0)
        #expect(abs(early.inputSecondsBeforeProjectStart - 0.1) < 1e-12)
        // In the file's own seconds: at double speed a tenth of the timeline is two tenths of it.
        let fast = SyncSettings(offsetInProject: -0.1, playSpeed: 2)
        #expect(abs(fast.inputSecondsBeforeProjectStart - 0.2) < 1e-12)
        // The stored offset is untouched, so a nudge the other way puts back what it took.
        #expect(early.offsetInProject == -0.1)
        // An ordinary offset keeps its place and loses nothing.
        let ordinary = SyncSettings(offsetInProject: 1.5)
        #expect(ordinary.startInProject == 1.5)
        #expect(ordinary.inputSecondsBeforeProjectStart == 0)
        #expect(SyncSettings.identity.startInProject == 0)
        #expect(SyncSettings.identity.inputSecondsBeforeProjectStart == 0)
    }

    @Test func roundTripsThroughJSON() throws {
        let sync = SyncSettings(startPositionInInput: 1.5, offsetInProject: 0.25, playSpeed: 0.5)
        let data = try JSONEncoder().encode(sync)
        #expect(try JSONDecoder().decode(SyncSettings.self, from: data) == sync)
    }
}

@Suite("ExportSettings")
struct ExportSettingsTests {
    @Test func presetsExist() {
        #expect(ExportSettings.presets["1080p"] == .hd1080)
        #expect(ExportSettings.presets["4k"]?.codec == .hevc)
        #expect(ExportSettings.hd720.width == 1280 && ExportSettings.hd720.height == 720)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = ExportSettings.uhd4k
        settings.audioBitrate = nil
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ExportSettings.self, from: data) == settings)
    }

    @Test func unitRectScales() {
        let rect = UnitRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25).scaled(toWidth: 1920, height: 1080)
        #expect(rect == CGRect(x: 480, y: 540, width: 960, height: 270))
    }
}
