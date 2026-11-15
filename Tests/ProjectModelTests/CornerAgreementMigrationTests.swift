import Foundation
import Testing

@testable import ProjectModel

/// #585 numbers only the corners most of a session's laps agree on. A project saved before keeps
/// every corner its reference lap finds, on every data input it has, so its map, corner-aware
/// sectors and coaching number the corners they always did.
@Suite("Corner agreement migration (#585)")
struct CornerAgreementMigrationTests {
    var project: Project {
        Project(inputs: [
            Input(label: "data", source: MediaReference(path: "session.rcz"), kind: .data(DataInputSettings())),
            Input(label: "video", source: MediaReference(path: "clip.mp4"), kind: .video(VideoInputSettings())),
        ])
    }

    /// `data` as a build at schema 4 wrote it: without the key schema 5 added.
    func savedAtSchema4(_ data: Data) throws -> Data {
        func strip(_ value: Any) -> Any {
            if var dictionary = value as? [String: Any] {
                dictionary["legacyCornersPerLap"] = nil
                return dictionary.mapValues(strip)
            }
            if let array = value as? [Any] { return array.map(strip) }
            return value
        }
        var root = try #require(strip(try JSONSerialization.jsonObject(with: data)) as? [String: Any])
        root["schemaVersion"] = 4
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func aProjectSavedBeforeKeepsEveryCorner() throws {
        let opened = try Project.decode(try savedAtSchema4(try project.encoded()))
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        #expect(opened.dataInputs.allSatisfy { $0.dataSettings?.legacyCornersPerLap == true })
        // Only that: the step before it (#477) is not taken again on a schema-4 project.
        #expect(opened.dataInputs.first?.dataSettings?.legacyFirstLap == false)
        #expect(opened.videoInputs.count == 1, "nothing else about the inputs is touched")
        let again = try Project.decode(try opened.encoded())
        #expect(again.dataInputs.first?.dataSettings?.legacyCornersPerLap == true)
    }

    @Test func aProjectMadeSinceNumbersTheCornersTheLapsAgreeOn() throws {
        #expect(project.dataInputs.first?.dataSettings?.legacyCornersPerLap == false)
        // Always written, so absence can only mean "saved before the field existed".
        let json = try #require(String(data: try project.encoded(), encoding: .utf8))
        #expect(json.contains("\"legacyCornersPerLap\" : false"))
        #expect(try Project.decode(try project.encoded()).dataInputs.first?.dataSettings?.legacyCornersPerLap == false)
    }
}
