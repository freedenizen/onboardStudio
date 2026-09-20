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
