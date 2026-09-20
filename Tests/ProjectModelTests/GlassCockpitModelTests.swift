import Foundation
import Testing

@testable import ProjectModel

@Suite("Steering wheel, gradients and overlay opacity")
struct GlassCockpitModelTests {
    static let degrees = ChannelSummary(
        identifier: "obd:steering_angle", name: "steering_angle", minValue: -173, maxValue: 160)
    static let radians = ChannelSummary(identifier: "aux:SWA", name: "SWA", minValue: -2.9, maxValue: 3.0)
    static let normalised = ChannelSummary(identifier: "aux:Steering", name: "Steering", minValue: -1, maxValue: 1)
    static let speed = ChannelSummary(identifier: "speed", name: "speed", minValue: 0, maxValue: 60)

    @Test func rotationFollowsScaleSignAndLimit() {
        var wheel = SteeringWheelParams(channel: "x")
        #expect(wheel.rotation(for: 90) == 90)
        wheel.invert = true
        #expect(wheel.rotation(for: 90) == -90)
        wheel.degreesPerUnit = 2
        wheel.maxDegrees = 120
        #expect(wheel.rotation(for: 90) == -120)
        #expect(wheel.rotation(for: .nan) == 0)
    }

    @Test func bindsToTheLoggersSteeringChannelWithAFittingScale() {
        let wheel = SteeringWheelParams()
        #expect(wheel.channel.isEmpty, "templates name no channel")
        let inDegrees = wheel.adapted(to: [Self.speed, Self.degrees])
        #expect(inDegrees.channel == "obd:steering_angle" && inDegrees.degreesPerUnit == 1)
        let inRadians = wheel.adapted(to: [Self.speed, Self.radians])
        #expect(inRadians.channel == "aux:SWA" && abs(inRadians.degreesPerUnit - 57.2958) < 0.001)
        #expect(wheel.adapted(to: [Self.normalised]).degreesPerUnit == 450)
        #expect(wheel.adapted(to: [Self.speed]).channel.isEmpty, "nothing to guess from")
        // A channel the user chose is kept, scale included.
        var custom = SteeringWheelParams(channel: "speed", degreesPerUnit: 3)
        custom.invert = true
        #expect(custom.adapted(to: [Self.speed, Self.degrees]) == custom)
    }

    @Test func templateObjectsBindWhenTheDataArrives() {
        var project = ProjectTemplate.glassCockpit.makeProject()
        let data = Input(label: "log", source: MediaReference(path: "/log.csv"), kind: .data(DataInputSettings()))
        project.inputs.append(data)
        project.bindOrphanObjects()
        let bound = project.bindEmptyChannels([data.id: [Self.speed, Self.degrees]])
        #expect(bound == ["Wheel"])
        let wheel = project.displayObjects.first { $0.label == "Wheel" }
        guard case .steeringWheel(let params)? = wheel?.kind else {
            Issue.record("no wheel in the template")
            return
        }
        #expect(params.channel == "obd:steering_angle")
        // A second pass has nothing left to do.
        #expect(project.bindEmptyChannels([data.id: [Self.speed, Self.degrees]]).isEmpty)
        // The band behind the gauges fades from clear to dark, and the wheel hangs below the frame.
        guard case .shape(let fade)? = project.displayObjects.first(where: { $0.label == "Fade" })?.kind else {
            Issue.record("no fade band")
            return
        }
        #expect(fade.fillColor.alpha == 0 && (fade.gradientEndColor?.alpha ?? 0) > 0.5)
        #expect((wheel?.frame.y ?? 0) + (wheel?.frame.height ?? 0) > 1)
    }

    @Test func oldFilesDecodeWithPlainFillsAndFullOpacity() throws {
        let json = ##"{"shape":"rectangle","fillColor":"#00000080","strokeColor":"#FFFFFFFF","strokeWidth":0}"##
        let shape = try JSONDecoder().decode(ShapeParams.self, from: Data(json.utf8))
        #expect(shape.gradientEndColor == nil && !shape.gradientHorizontal && shape.cornerRadius == 0.15)
        let settings = try JSONDecoder().decode(ProjectSettings.self, from: Data("{}".utf8))
        #expect(settings.overlayOpacity == 1)
        // The overlay opacity only needs a replan, like the camera framing.
        var faded = settings
        faded.overlayOpacity = 0.5
        #expect(faded.withoutFraming == settings.withoutFraming)
        let wheel = try JSONDecoder().decode(SteeringWheelParams.self, from: Data("{}".utf8))
        #expect(wheel == SteeringWheelParams())
    }
}

@Suite("G-force axes")
struct GForceParamsTests {
    @Test func axisChannelsAndSignsRoundTrip() throws {
        var params = GForceParams()
        params.lateralChannel = "canbus:lateral_acc"
        params.longitudinalChannel = "canbus:long_acc"
        params.invertLateral = true
        let data = try JSONEncoder().encode(params)
        #expect(try JSONDecoder().decode(GForceParams.self, from: data) == params)
    }

    /// Projects saved before the axes were configurable carry none of these keys, and must still
    /// load with the plot behaving exactly as it did.
    @Test func projectsSavedBeforeTheAxesExistedStillDecode() throws {
        let legacy = Data(#"{"maxG":1.5,"ringStep":0.5,"trailSeconds":3,"showValues":false}"#.utf8)
        let params = try JSONDecoder().decode(GForceParams.self, from: legacy)
        #expect(params.maxG == 1.5 && params.trailSeconds == 3 && params.showValues == false)
        #expect(params.lateralChannel.isEmpty && params.longitudinalChannel.isEmpty)
        #expect(params.invertLateral == false && params.invertLongitudinal == false)
        #expect(try JSONDecoder().decode(GForceParams.self, from: Data("{}".utf8)) == GForceParams())
    }

    @Test func invertingNegatesAndNonFiniteValuesReadZero() {
        let params = GForceParams()
        #expect(params.axisValue(0.8, invert: false) == 0.8)
        #expect(params.axisValue(0.8, invert: true) == -0.8)
        #expect(params.axisValue(nil, invert: false) == 0)
        #expect(params.axisValue(.nan, invert: true) == 0)
    }
}

@Suite("Turn direction binding")
struct TurnDirectionBindingTests {
    static func steering(_ correlation: Double?) -> ChannelSummary {
        ChannelSummary(
            identifier: "canbus:steering_angle", name: "steering_angle", minValue: -173, maxValue: 160,
            rightTurnCorrelation: correlation)
    }

    @Test func aLeftPositiveLoggerBindsInverted() {
        let wheel = SteeringWheelParams().adapted(to: [Self.steering(-0.72)])
        #expect(wheel.channel == "canbus:steering_angle")
        #expect(wheel.invert, "the session measured positive-steering-goes-left")
        #expect(wheel.degreesPerUnit == 1, "the scale inference is untouched")
    }

    @Test func aRightPositiveLoggerBindsUninverted() {
        #expect(SteeringWheelParams().adapted(to: [Self.steering(0.72)]).invert == false)
    }

    /// No measurement, no opinion: whatever the user set stays set.
    @Test func anUnmeasuredChannelLeavesInvertAlone() {
        #expect(SteeringWheelParams().adapted(to: [Self.steering(nil)]).invert == false)
        var manual = SteeringWheelParams()
        manual.invert = true
        #expect(manual.adapted(to: [Self.steering(nil)]).invert, "a manual choice is not overwritten")
    }

    @Test func theGForceLateralAxisFollowsTheSameMeasurement() {
        let lateral = ChannelSummary(
            identifier: "lateralG", name: "lat", minValue: -1.3, maxValue: 1.4, rightTurnCorrelation: -0.69)
        #expect(GForceParams().adapted(to: [lateral]).invertLateral)
        // An object bound to its own channel is judged on that channel, not on the standard role.
        var custom = GForceParams()
        custom.lateralChannel = "canbus:lat_iso"
        let own = ChannelSummary(identifier: "canbus:lat_iso", name: "iso", rightTurnCorrelation: -0.8)
        #expect(custom.adapted(to: [lateral, own]).invertLateral)
        #expect(custom.adapted(to: [lateral]).invertLateral == false, "its own channel was not measured")
    }
}
