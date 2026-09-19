import Foundation
import Testing

@testable import ProjectModel

@Suite("Indicator channel suggestions")
struct IndicatorParamsTests {
    static let raceChronoLike = [
        ChannelSummary(identifier: "speed", name: "speed", minValue: 0, maxValue: 60),
        ChannelSummary(identifier: "brake", name: "brake_pos", minValue: 0, maxValue: 76),
        ChannelSummary(identifier: "obd:analog_1", name: "analog_1", minValue: 512, maxValue: 2800),
        ChannelSummary(identifier: "obd:analog_2", name: "analog_2", minValue: 512, maxValue: 2804),
    ]
    static let namedFlags = [
        ChannelSummary(identifier: "aux:ABS_Active", name: "ABS Active", minValue: 0, maxValue: 1),
        ChannelSummary(identifier: "obd:DSC", name: "Stability control", minValue: 0, maxValue: 1),
        ChannelSummary(identifier: "aux:Traction Control", name: "TC intervention", minValue: 0, maxValue: 100),
        ChannelSummary(identifier: "obd:brake_switch", name: "Brake switch", minValue: 0, maxValue: 1),
    ]

    @Test func presetsCarryNoLoggerSpecificChannel() {
        #expect(IndicatorParams.abs.channel.isEmpty)
        #expect(IndicatorParams.traction.channel.isEmpty)
        #expect(IndicatorParams.brake.channel == "brake")
    }

    @Test func picksChannelsByKeywordOrLabel() {
        #expect(IndicatorParams.abs.suggestedChannel(among: Self.namedFlags) == "aux:ABS_Active")
        #expect(IndicatorParams.traction.suggestedChannel(among: Self.namedFlags) == "obd:DSC")
        var tc = IndicatorParams.traction
        tc.label = "TC"
        #expect(tc.suggestedChannel(among: Array(Self.namedFlags.dropFirst(2))) == "aux:Traction Control")
        // The exact role identifier wins over a name that merely contains the word.
        #expect(IndicatorParams.brake.suggestedChannel(among: Self.namedFlags + Self.raceChronoLike) == "brake")
        // Anonymous analog columns give nothing to go on: the user has to choose.
        #expect(IndicatorParams.abs.suggestedChannel(among: Self.raceChronoLike) == nil)
        #expect(IndicatorParams.traction.suggestedChannel(among: Self.raceChronoLike) == nil)
    }

    @Test func thresholdsComeFromTheObservedRange() {
        let flag = ChannelSummary(identifier: "x", name: "x", minValue: 0, maxValue: 1)
        #expect(IndicatorParams.abs.suggestedThreshold(for: flag) == 0.5)
        #expect(IndicatorParams.abs.suggestedThreshold(for: Self.raceChronoLike[2]) == 1700)
        #expect(abs((IndicatorParams.brake.suggestedThreshold(for: Self.raceChronoLike[1]) ?? 0) - 7.6) < 1e-9)
        #expect(IndicatorParams.abs.suggestedThreshold(for: ChannelSummary(identifier: "y", name: "y")) == nil)
        #expect(
            IndicatorParams.abs.suggestedThreshold(
                for: ChannelSummary(identifier: "z", name: "z", minValue: 3, maxValue: 3))
                == nil)
    }

    @Test func adaptingBindsTemplatesToTheInput() {
        let abs = IndicatorParams.abs.adapted(to: Self.namedFlags)
        #expect(abs.channel == "aux:ABS_Active" && abs.threshold == 0.5)
        let tc = IndicatorParams.traction.adapted(to: Self.namedFlags)
        #expect(tc.channel == "obd:DSC")
        // A channel that exists is kept as configured, threshold included.
        var custom = IndicatorParams.abs
        custom.channel = "obd:analog_1"
        custom.threshold = 600
        #expect(custom.adapted(to: Self.raceChronoLike) == custom)
        // Nothing matching: the channel stays empty for the inspector to prompt.
        #expect(IndicatorParams.abs.adapted(to: Self.raceChronoLike).channel.isEmpty)
    }

    @Test func lapPanelDefaultsFillMissingKeys() throws {
        let decoded = try JSONDecoder().decode(LapPanelParams.self, from: Data("{}".utf8))
        #expect(decoded == LapPanelParams())
        #expect(decoded.bestLabel == "Best" && decoded.reference == .bestLap && decoded.showLapNumbers)
        let custom = try JSONDecoder().decode(
            LapPanelParams.self, from: Data(#"{"reference":"previousLap","currentLabel":"Now"}"#.utf8))
        #expect(custom.reference == .previousLap && custom.currentLabel == "Now")
    }
}
