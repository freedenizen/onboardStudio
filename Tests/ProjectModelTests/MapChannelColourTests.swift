import Foundation
import Testing

@testable import ProjectModel

/// #561: a Track Map paints the lap being driven by a channel, on one ramp kept in Settings.
@Suite("Map channel colouring (#561)")
struct MapChannelColourTests {
    @Test func aMapSavedBeforeChannelColouringPaintsNoChannel() throws {
        let json = ##"{"lineColor": "#FFFFFF", "colorByDelta": true}"##
        let params = try JSONDecoder().decode(TrackMapParams.self, from: Data(json.utf8))
        #expect(params.colorChannel == nil)
        #expect(params.colorByDelta, "what it did choose is kept")
    }

    @Test func theChannelAndLegendSurviveSaving() throws {
        var params = TrackMapParams()
        params.colorChannel = "aux:Brake pressure"
        params.showChannelLegend = false
        let again = try JSONDecoder().decode(TrackMapParams.self, from: JSONEncoder().encode(params))
        #expect(again.colorChannel == "aux:Brake pressure")
        #expect(!again.showChannelLegend)
        #expect(TrackMapParams().showChannelLegend, "a new map shows the legend once a channel is chosen")
    }

    @Test func theRampIsKeptAsHexColours() {
        let ramp = ColorRamp(stops: [RGBAColor(red: 0, green: 0, blue: 1), RGBAColor(red: 1, green: 0, blue: 0)])
        #expect(ramp.preferenceText == "#0000FF #FF0000")
        #expect(ColorRamp(preferenceText: ramp.preferenceText) == ramp)
    }

    @Test func noSettingOrAnUnreadableOneIsTheStandardRamp() {
        #expect(ColorRamp(preferenceText: "") == .standard)
        #expect(ColorRamp(preferenceText: "not colours") == .standard)
        #expect(ColorRamp(preferenceText: "#FF0000") == .standard, "one colour cannot blend")
        #expect(ColorRamp.standard.stops.count == 4, "blue, green, yellow, red")
    }

    @Test func theRampHasItsOwnPreferenceKey() {
        #expect(Preferences.allKeys.contains(Preferences.mapColorRamp.key))
        #expect(Set(Preferences.allKeys).count == Preferences.allKeys.count)
    }
}
