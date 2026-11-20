import Foundation
import Testing

@testable import ProjectModel

/// #558 adds grip to coaching's notes, which Corner Callouts draw into the video. A project saved
/// before keeps its notes without it.
@Suite("No grip notes migration (#558)")
struct NoGripNotesMigrationTests {
    var project: Project {
        Project(inputs: [
            Input(label: "data", source: MediaReference(path: "session.csv"), kind: .data(DataInputSettings()))
        ])
    }

    @Test func aProjectSavedAtSchema7KeepsItsNotesWithoutGrip() throws {
        var root = try #require(try JSONSerialization.jsonObject(with: try project.encoded()) as? [String: Any])
        root["schemaVersion"] = 7
        let opened = try Project.decode(try JSONSerialization.data(withJSONObject: root))
        #expect(opened.schemaVersion == Project.currentSchemaVersion)
        #expect(opened.dataInputs.first?.dataSettings?.legacyNoGripNotes == true)
        #expect(opened.dataInputs.first?.dataSettings?.legacyExactDistances == false, "schema 7 already had it")
        let again = try Project.decode(try opened.encoded())
        #expect(again.dataInputs.first?.dataSettings?.legacyNoGripNotes == true)
    }

    @Test func aProjectMadeSinceSaysHowMuchGripWasUsed() throws {
        let opened = try Project.decode(try project.encoded())
        #expect(opened.dataInputs.first?.dataSettings?.legacyNoGripNotes == false)
    }
}
