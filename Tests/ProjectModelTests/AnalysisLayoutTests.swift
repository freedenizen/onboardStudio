import Foundation
import TelemetryKit
import Testing

@testable import ProjectModel

/// #556: the Analysis view's panels, remembered for next time.
@Suite("Analysis layout (#556)")
struct AnalysisLayoutTests {
    @Test func aLayoutComesBackAsItWasLeft() {
        var layout = AnalysisLayout()
        layout.showsMap = false
        layout.add(.rpm)
        layout.add(.rpm)
        layout.add(.speed)
        layout.remove(.brake)
        layout.traceHeight = 200
        let again = AnalysisLayout(preferenceText: layout.preferenceText)
        #expect(again == layout)
        #expect(again.channels == [.throttle, .rpm], "speed has its own panel; a channel is traced once")
    }

    @Test func nothingOrNonsenseIsTheStandardLayout() {
        #expect(AnalysisLayout(preferenceText: "") == .standard)
        #expect(AnalysisLayout(preferenceText: "{not json") == .standard)
        #expect(AnalysisLayout.standard.showsDelta && AnalysisLayout.standard.showsFrictionCircle)
    }

    @Test func aHeightOutOfRangeIsBroughtIntoIt() {
        let layout = AnalysisLayout(preferenceText: #"{"traceHeight":5000,"showsMap":false}"#)
        #expect(layout.traceHeight == AnalysisLayout.traceHeights.upperBound)
        #expect(!layout.showsMap && layout.showsSpeed)
        #expect(layout.showsPicture, "a layout from before the picture shows it")
    }

    @Test func anAuxChannelIsRemembered() {
        var layout = AnalysisLayout(channels: [])
        layout.add(.aux("oil_pressure_bar"))
        #expect(AnalysisLayout(preferenceText: layout.preferenceText).channels == [.aux("oil_pressure_bar")])
    }
}
