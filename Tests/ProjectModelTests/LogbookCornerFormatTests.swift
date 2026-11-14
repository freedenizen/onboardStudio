import Foundation
import TelemetryKit
import Testing

@testable import ProjectModel

/// The corner table under Trends says the units it shows (#544): its note said km/h over a column
/// in mph, and its brake points stayed in metres where Coaching gives feet.
@Suite("Logbook corner table units (#544)")
struct LogbookCornerFormatTests {
    static let american = Locale(identifier: "en_US")
    static let german = Locale(identifier: "de_DE")

    @Test func mphShowsFeetAndSaysSo() {
        let format = LogbookTrends.CornerFormat(setting: .mph, locale: Self.german)
        #expect(format.brakePoint(100) == "328 ft")
        #expect(format.brakePointChange(3) == "+10 ft")
        #expect(format.brakePointChange(-3) == "-10 ft")
        #expect(format.brakePointChange(0.1) == "same")
        #expect(format.minimumSpeed(20) == "45 mph")
        #expect(format.minimumSpeedChange(2) == "+4 mph")
        #expect(format.note.contains("Brake point in feet"))
        #expect(format.note.contains("Minimum speed in mph."))
        #expect(!format.note.contains("km/h"))
    }

    @Test func kphShowsMetresAndSaysSo() {
        let format = LogbookTrends.CornerFormat(setting: .kph, locale: Self.american)
        #expect(format.brakePoint(100) == "100 m")
        #expect(format.brakePointChange(3) == "+3 m")
        #expect(format.brakePointChange(-0.4) == "same")
        #expect(format.minimumSpeed(20) == "72 km/h")
        #expect(format.minimumSpeedChange(-2) == "-7 km/h")
        #expect(format.note.contains("Brake point in metres"))
        #expect(format.note.contains("Minimum speed in km/h."))
    }

    @Test func automaticFollowsTheRegionAsCoachingDoes() {
        let us = LogbookTrends.CornerFormat(setting: .automatic, locale: Self.american)
        #expect(us.speed == .mph)
        #expect(us.distance == CoachingUnits.following(.automatic, locale: Self.american).distance)
        #expect(us.brakePoint(10) == "33 ft")
        let de = LogbookTrends.CornerFormat(setting: .automatic, locale: Self.german)
        #expect(de.speed == .kph)
        #expect(de.brakePoint(10) == "10 m")
    }

    /// m/s is shown as it is chosen, and the brake points stay metric as Coaching's notes do.
    @Test func metersPerSecondKeepsMetres() {
        let format = LogbookTrends.CornerFormat(setting: .metersPerSecond, locale: Self.american)
        #expect(format.minimumSpeed(20) == "20 m/s")
        #expect(format.brakePoint(42) == "42 m")
        #expect(format.note.contains("Minimum speed in m/s."))
    }

    @Test func missingValuesAreDashes() {
        let format = LogbookTrends.CornerFormat(setting: .mph)
        #expect(format.brakePoint(nil) == "—")
        #expect(format.brakePointChange(nil) == "—")
        #expect(format.minimumSpeed(nil) == "—")
        #expect(format.minimumSpeedChange(nil) == "—")
    }
}
