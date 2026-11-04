import Foundation
import Testing

@testable import ProjectModel

@Suite("Coaching settings")
struct CoachingSettingsTests {
    @Test func theSettingsRoundTripAndAreAbsentInOlderProjects() throws {
        let data = Input(label: "Data", source: MediaReference(path: "/tmp/s.csv"), kind: .data(DataInputSettings()))
        let other = Input(label: "Other", source: MediaReference(path: "/tmp/o.csv"), kind: .data(DataInputSettings()))
        var project = Project(inputs: [data, other])
        #expect(project.coaching == nil)
        project.coaching = CoachingSettings(
            dataInputID: data.id, lap: 5, reference: .otherInput(dataInputID: other.id, lap: 2))
        let reopened = try Project.decode(try project.encoded())
        #expect(reopened.coaching == project.coaching)
        for reference in [
            CoachingSettings.Reference.sessionBest, .lap(3), .fastestRolling, .compositeOptimal,
            .logbook(entryID: UUID(), lap: 4), .logbook(entryID: UUID(), lap: nil),
        ] {
            project.coaching = CoachingSettings(dataInputID: data.id, reference: reference)
            #expect(try Project.decode(try project.encoded()).coaching?.reference == reference)
        }
        // A project saved before the window existed has no key, and opens with none.
        var json = try #require(try JSONSerialization.jsonObject(with: try project.encoded()) as? [String: Any])
        json["coaching"] = nil
        let older = try Project.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(older.coaching == nil)
    }

    @Test func liningUpByPositionIsOffUnlessAskedAndAbsentInOlderSettings() throws {
        let data = Input(label: "Data", source: MediaReference(path: "/tmp/s.csv"), kind: .data(DataInputSettings()))
        var project = Project(inputs: [data])
        project.coaching = CoachingSettings(dataInputID: data.id, lap: 2, alignByPosition: true)
        let reopened = try Project.decode(try project.encoded())
        #expect(reopened.coaching?.alignByPosition == true)
        // Settings saved before the option existed have no key and read as off.
        var json = try #require(try JSONSerialization.jsonObject(with: try project.encoded()) as? [String: Any])
        var coaching = try #require(json["coaching"] as? [String: Any])
        coaching["alignByPosition"] = nil
        json["coaching"] = coaching
        let older = try Project.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(older.coaching?.alignByPosition == false)
        #expect(older.coaching?.lap == 2)
    }
}
