import Foundation
import Testing

@testable import ProjectModel

/// #555 says coaching distances only as closely as the GPS allows. A project saved before keeps
/// them to the metre, so its Corner Callouts read as they did.
@Suite("Exact distances migration (#555)")
struct ExactDistancesMigrationTests {
    var project: Project {
        Project(inputs: [
            Input(label: "data", source: MediaReference(path: "session.csv"), kind: .data(DataInputSettings()))
        ])
    }

    @Test func aProjectSavedAtSchema6KeepsExactDistances() throws {
        var root = try #require(try JSONSerialization.jsonObject(with: try project.encoded()) as? [String: Any])
        root["schemaVersion"] = 6
        let opened = try Project.decode(try JSONSerialization.data(withJSONObject: root))
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        #expect(opened.dataInputs.first?.dataSettings?.legacyExactDistances == true)
        #expect(opened.dataInputs.first?.dataSettings?.legacyCornersOnlyDropped == false, "schema 6 already had it")
        let again = try Project.decode(try opened.encoded())
        #expect(again.dataInputs.first?.dataSettings?.legacyExactDistances == true)
    }

    @Test func aProjectMadeSinceRoundsToTheGPS() throws {
        #expect(project.dataInputs.first?.dataSettings?.legacyExactDistances == false)
        let opened = try Project.decode(try project.encoded())
        #expect(opened.dataInputs.first?.dataSettings?.legacyExactDistances == false)
    }
}
