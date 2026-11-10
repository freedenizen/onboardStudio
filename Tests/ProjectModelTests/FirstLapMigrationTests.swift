import Foundation
import Testing

@testable import ProjectModel

/// #477 changed how a RaceChrono file's first lap is read. A project saved before keeps the old
/// reading on every data input it has, so its lap numbers, counts and deltas stay as they were.
@Suite("First lap migration (#477)")
struct FirstLapMigrationTests {
    var project: Project {
        Project(inputs: [
            Input(label: "data", source: MediaReference(path: "session.rcz"), kind: .data(DataInputSettings())),
            Input(label: "video", source: MediaReference(path: "clip.mp4"), kind: .video(VideoInputSettings())),
        ])
    }

    /// `data` as a build at `version` wrote it: without the key schema 4 added, wherever it is.
    func saved(before data: Data, version: Int) throws -> Data {
        func strip(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                dictionary["legacyFirstLap"] = nil
                return dictionary.mapValues(strip)
            }
            if let array = value as? [Any] { return array.map(strip) }
            return value
        }
        var root = try #require(strip(try JSONSerialization.jsonObject(with: data)) as? [String: Any])
        root["schemaVersion"] = version
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func aProjectSavedBeforeKeepsItsFirstLap() throws {
        let opened = try Project.decode(try saved(before: try project.encoded(), version: 3))
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        #expect(opened.dataInputs.count == 1)
        #expect(opened.dataInputs.allSatisfy { $0.dataSettings?.legacyFirstLap == true })
        #expect(opened.videoInputs.count == 1, "nothing else about the inputs is touched")
        // Stated once, it stays stated when the project is saved again.
        let again = try Project.decode(try opened.encoded())
        #expect(again.dataInputs.first?.dataSettings?.legacyFirstLap == true)
    }

    @Test func aProjectMadeSinceReadsTheLapWhereItBegins() throws {
        #expect(project.dataInputs.first?.dataSettings?.legacyFirstLap == false)
        // Always written, so absence can only mean "saved before the field existed".
        let json = try #require(String(data: try project.encoded(), encoding: .utf8))
        #expect(json.contains("\"legacyFirstLap\" : false"))
        #expect(try Project.decode(try project.encoded()).dataInputs.first?.dataSettings?.legacyFirstLap == false)
    }

    /// Older still: each step pins what its own build did, so both apply.
    @Test func aProjectFromTwoSchemasAgoKeepsBoth() throws {
        var old = try #require(
            try JSONSerialization.jsonObject(with: try saved(before: try project.encoded(), version: 2))
                as? [String: Any])
        var settings = try #require(old["settings"] as? [String: Any])
        settings["legacyAutomaticUnits"] = nil
        old["settings"] = settings
        let opened = try Project.decode(try JSONSerialization.data(withJSONObject: old))
        #expect(opened.settings.legacyAutomaticUnits)
        #expect(opened.dataInputs.first?.dataSettings?.legacyFirstLap == true)
    }
}
