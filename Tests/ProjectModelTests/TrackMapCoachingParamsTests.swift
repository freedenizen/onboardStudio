import Foundation
import Testing

@testable import ProjectModel

@Suite("Track map coaching params")
struct TrackMapCoachingParamsTests {
    @Test func theCoachingOptionsAreOffUnlessAFileSaysOtherwise() throws {
        let older = try JSONDecoder().decode(TrackMapParams.self, from: Data(#"{"lineWidth": 3}"#.utf8))
        #expect(!older.showReferenceLine && !older.colorByDelta && !older.showBrakeMarks && !older.followCorner)
        #expect(!older.usesCoaching)
        let follow = try JSONDecoder().decode(TrackMapParams.self, from: Data(#"{"followCorner": true}"#.utf8))
        #expect(follow.followCorner)
        #expect(follow.usesCoaching)
        var params = TrackMapParams()
        params.colorByDelta = true
        let back = try JSONDecoder().decode(TrackMapParams.self, from: try JSONEncoder().encode(params))
        #expect(back == params)
        // A map with a coaching option on asks for the coaching read at compile; a plain one does not.
        let map = DisplayObject(label: "Map", inputID: nil, frame: .full, kind: .trackMap(params))
        #expect(Project(displayObjects: [map]).needsCoaching)
        let plain = DisplayObject(label: "Map", inputID: nil, frame: .full, kind: .trackMap(TrackMapParams()))
        #expect(!Project(displayObjects: [plain]).needsCoaching)
    }
}
