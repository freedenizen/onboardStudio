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
        #expect(decoded.bestLabel == "Best" && decoded.reference == .sessionBest && decoded.showLapNumbers)
        // Everything except the speed unit is the memberwise default. That one deliberately is
        // not: a panel saved before #75 drew mph, so an absent key keeps mph, while a panel made
        // today defers to the project. Asserted rather than assumed, because the two being equal
        // is the normal case and this is the exception to it.
        var expected = LapPanelParams()
        expected.speedUnit = .mph
        #expect(decoded == expected)
        #expect(decoded.speedUnit == .mph)
        #expect(LapPanelParams().speedUnit == .automatic)
        let custom = try JSONDecoder().decode(
            LapPanelParams.self, from: Data(#"{"reference":"previousLap","currentLabel":"Now"}"#.utf8))
        #expect(custom.reference == .previousLap && custom.currentLabel == "Now")
    }

    @Test func aTrackMapSavedBeforeTheOptionStillDrawsTheWholeSession() throws {
        // A new map draws the circuit and leaves out the pit lane. A map saved before `trace`
        // existed has no key and goes on drawing every position in the file, which is what it drew
        // when it was saved — the rule in `docs/project-format.md`.
        #expect(TrackMapParams().trace == .trackOnly)
        let old = try JSONDecoder().decode(TrackMapParams.self, from: Data(#"{"lineWidth":3}"#.utf8))
        #expect(old.trace == .wholeSession)
        // The fallback is not the memberwise default and must not be rewritten to follow it: it is
        // the record of how the app drew before the field existed, and it is all there is.
        #expect(old.trace != TrackMapParams().trace)
        // Every build that has the field writes the key, so a file saved by one keeps what it
        // chose — including the choice that is no longer the default.
        for trace in TrackMapTrace.allCases {
            let saved = try JSONEncoder().encode(TrackMapParams(trace: trace))
            #expect(try JSONDecoder().decode(TrackMapParams.self, from: saved).trace == trace)
            #expect(String(data: saved, encoding: .utf8)?.contains("trace") == true)
        }
        // Templates and object styles embed these params and have no migration seam of their own
        // (#124); this fallback is what protects one saved before the field existed.
        #expect(TrackMapTrace.allCases.count == 3)
    }

    @Test func deltaSettingsKeepOldFilesUnchanged() throws {
        // New delta timers compare with the session's best lap; files saved before 0.17 have no
        // key and keep comparing with the best lap so far.
        #expect(TimerParams(mode: .deltaToBest).deltaReference == .sessionBest)
        let old = try JSONDecoder().decode(TimerParams.self, from: Data(#"{"mode":"deltaToBest"}"#.utf8))
        #expect(old.deltaReference == .bestLap)
        let round = try JSONDecoder().decode(
            TimerParams.self, from: JSONEncoder().encode(TimerParams(mode: .deltaToBest, deltaReference: .previousLap)))
        #expect(round.deltaReference == .previousLap)
        // Bars fill from the minimum unless asked otherwise; the delta bar templates ask.
        let bar = try JSONDecoder().decode(BarParams.self, from: Data(#"{"channel":"rpm"}"#.utf8))
        #expect(!bar.fillFromZero)
        let templates = DisplayObject.templates.filter { $0.name.hasPrefix("Delta Bar") }
        #expect(templates.count == 2)
        for template in templates {
            guard case .bar(let params) = template.kind else {
                Issue.record("\(template.name) is not a bar")
                continue
            }
            #expect(params.fillFromZero && params.minValue < 0 && params.maxValue > 0)
            #expect(["lapDelta", "speedDelta"].contains(params.channel))
        }
    }
}
