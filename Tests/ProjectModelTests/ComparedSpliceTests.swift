import Foundation
import Testing

@testable import ProjectModel

@Suite("Compared splice")
struct ComparedSpliceTests {
    let video = Input(label: "Cam", source: MediaReference(path: "/tmp/c.mp4"), kind: .video(VideoInputSettings()))
    let data = Input(label: "Log", source: MediaReference(path: "/tmp/l.csv"), kind: .data(DataInputSettings()))

    @Test func aSplicedComparisonRoundTripsAndOlderFilesHaveNone() throws {
        let side = LapComparisonSettings.Side(dataInputID: data.id, videoInputID: video.id, lap: 2)
        let settings = LapComparisonSettings(lap: side, comparedLap: side, comparedSplice: .compositeOptimal)
        let back = try JSONDecoder().decode(LapComparisonSettings.self, from: try JSONEncoder().encode(settings))
        #expect(back == settings)
        #expect(back.comparedName == "Optimal Lap")
        let encoded = try JSONEncoder().encode(settings)
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["comparedSplice"] = nil
        let olderData = try JSONSerialization.data(withJSONObject: json)
        let older = try JSONDecoder().decode(LapComparisonSettings.self, from: olderData)
        #expect(older.comparedSplice == nil)
        #expect(older.comparedName == "Compared Lap")
        // The layout names the compared side for what it is.
        var project = Project(inputs: [video, data])
        project.compareLaps(settings, lapRange: nil)
        #expect(project.displayObjects.contains { $0.label == "Optimal Lap Picture" })
        #expect(project.displayObjects.contains { $0.label == "Optimal Lap Timer" })
    }
}
