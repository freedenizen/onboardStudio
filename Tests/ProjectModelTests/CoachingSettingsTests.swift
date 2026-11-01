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
}
