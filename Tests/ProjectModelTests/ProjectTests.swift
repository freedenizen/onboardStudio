import Foundation
import Testing

@testable import ProjectModel

@Suite("Project document")
struct ProjectTests {
    static func sampleProject() -> Project {
        let video = Input(label: "Cam", source: MediaReference(path: "clip.mp4"), kind: .video(VideoInputSettings()))
        let data = Input(
            label: "Data", source: MediaReference(path: "data/session.csv"),
            kind: .data(DataInputSettings(roleOverrides: ["Coolant": "obd:Coolant"])),
            sync: SyncSettings(startPositionInInput: 12.5))
        let objects = [
            DisplayObject(label: "Cam", inputID: video.id, frame: .full, kind: .video(VideoObjectParams())),
            DisplayObject(
                label: "Speed", inputID: data.id, frame: UnitRect(x: 0.7, y: 0.6, width: 0.25, height: 0.35),
                kind: .speedometer(.speedometer(unit: .kph, max: 250))),
            DisplayObject(
                label: "Map", inputID: data.id, frame: UnitRect(x: 0, y: 0, width: 0.2, height: 0.3),
                kind: .trackMap(TrackMapParams())),
            DisplayObject(
                label: "G", inputID: data.id, frame: UnitRect(x: 0, y: 0.5, width: 0.2, height: 0.3),
                kind: .gForce(GForceParams())),
            DisplayObject(
                label: "Lap", inputID: data.id, frame: UnitRect(x: 0.3, y: 0, width: 0.4, height: 0.1),
                kind: .timer(TimerParams(mode: .bestLap))),
            DisplayObject(
                label: "RPM", inputID: data.id, frame: UnitRect(x: 0.3, y: 0.9, width: 0.4, height: 0.1),
                kind: .textData(TextDataParams(channel: "rpm", label: "RPM", alignment: .center))),
        ]
        return Project(inputs: [video, data], displayObjects: objects)
    }

    @Test func roundTripsThroughJSON() throws {
        let project = Self.sampleProject()
        let data = try project.encoded()
        let decoded = try Project.decode(data)
        #expect(decoded == project)
        #expect(decoded.videoInputs.count == 1 && decoded.dataInputs.count == 1)
        #expect(
            decoded.displayObjects.map(\.kind.typeName) == [
                "Video", "Speedometer", "Track Map", "G-Force", "Timer", "Text Data",
            ])
    }

    @Test func jsonUsesReadableEnumAndColourEncoding() throws {
        let text = String(bytes: try Self.sampleProject().encoded(), encoding: .utf8) ?? ""
        #expect(text.contains("\"speedometer\""))
        #expect(text.contains("\"needleColor\" : \"#FF9E1A\""))
        #expect(text.contains("\"speedUnit\" : \"kph\""))
        #expect(text.contains("\"obd:Coolant\""))
    }

    @Test func rejectsNewerSchema() {
        var project = Self.sampleProject()
        project.schemaVersion = 99
        #expect(throws: ProjectError.unsupportedSchemaVersion(99)) { try project.migrateIfNeeded() }
    }

    @Test func locationHandlesPackagesAndBareFiles() throws {
        let package = ProjectLocation(URL(fileURLWithPath: "/tmp/Race.overlayproj"))
        #expect(package.jsonURL.lastPathComponent == "project.json")
        #expect(package.baseDirectory.path == "/tmp/Race.overlayproj")
        #expect(package.resolve(MediaReference(path: "../clip.mp4")).standardizedFileURL.path == "/tmp/clip.mp4")
        #expect(package.resolve(MediaReference(path: "/abs/clip.mp4")).path == "/abs/clip.mp4")
        let bare = ProjectLocation(URL(fileURLWithPath: "/tmp/x/project.json"))
        #expect(bare.baseDirectory.path == "/tmp/x")
    }

    @Test func savesAndLoadsAPackage() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "og-\(UUID().uuidString).overlayproj")
        defer { try? FileManager.default.removeItem(at: dir) }
        let location = ProjectLocation(dir)
        let project = Self.sampleProject()
        try location.save(project)
        #expect(try location.load() == project)
        #expect(throws: ProjectError.self) {
            try ProjectLocation(URL(fileURLWithPath: "/nonexistent.overlayproj")).load()
        }
    }

    @Test func colourHexParsing() {
        #expect(RGBAColor(hex: "#FF8000")?.hex == "#FF8000")
        #expect(RGBAColor(hex: "FF800080")?.alpha == Double(0x80) / 255)
        #expect(RGBAColor(hex: "#F80") == RGBAColor(hex: "#FF8800"))
        #expect(RGBAColor(hex: "nope") == nil)
        #expect(RGBAColor.white.hex == "#FFFFFF")
    }

    @Test func speedUnitFactors() {
        #expect(abs(SpeedDisplayUnit.mph.factorFromMetersPerSecond * 0.44704 - 1) < 1e-6)
        #expect(SpeedDisplayUnit.kph.factorFromMetersPerSecond == 3.6)
    }
}
