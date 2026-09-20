import Foundation
import Testing

@testable import TelemetryKit

/// Loggers disagree on which way is positive, so the direction is measured rather than assumed.
/// The reference is yaw rate from the GPS heading, which owes nothing to any logger's convention.
@Suite("Turn direction")
struct TurnDirectionTests {
    /// A right-hand turn — heading climbing 20°/s — logged by a car that reports steering and
    /// lateral acceleration positive-for-LEFT, as RaceChrono does under ISO 8855 axes.
    static func session(turningFor seconds: Double = 12, straightFor lead: Double = 3, yawRate: Double = 20)
        -> TelemetrySession
    {
        var times: [Double] = []
        var heading: [Double] = []
        var steering: [Double] = []
        var lateral: [Double] = []
        var angle = 0.0
        var t = 0.0
        while t < lead + seconds {
            let turning = t >= lead
            if turning { angle = (angle + yawRate * 0.1).truncatingRemainder(dividingBy: 360) }
            times.append(t)
            heading.append(angle)
            steering.append(turning ? -90 : 0)
            lateral.append(turning ? -0.85 : 0)
            t += 0.1
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .heading, name: "bearing", unit: .degrees, times: times, values: heading),
                Channel(role: .canbus("steering_angle"), name: "steer", unit: .degrees, times: times, values: steering),
                Channel(role: .lateralG, name: "lat", unit: .gForce, times: times, values: lateral),
            ])
    }

    @Test func yawRateIsPositiveForARightTurn() throws {
        let yaw = try #require(TurnDirection.yawRate(of: Self.session()))
        let middle = yaw.values[(yaw.count / 2 - 10)...(yaw.count / 2 + 10)]
        #expect(middle.allSatisfy { abs($0 - 20) < 0.5 }, "about +20 deg/s through the corner")
        // The moving average's window is truncated at the ends of the series, which halves the
        // rate over the last half-second. Harmless for correlation over a whole session, but do
        // not read a single value off either end and trust it.
        #expect(yaw.values.last ?? 0 < 20)
    }

    /// Crossing 360° must read as a small step the same way round, not a 358° lurch backwards.
    @Test func yawRateSurvivesTheHeadingWrap() throws {
        let yaw = try #require(TurnDirection.yawRate(of: Self.session(turningFor: 40)))
        #expect(yaw.values.allSatisfy { abs($0) < 60 }, "no spike where the heading wraps past 360")
    }

    @Test func aLeftPositiveSteeringChannelWantsInverting() throws {
        let session = Self.session()
        let steering = try #require(session[.canbus("steering_angle")])
        let reading = try #require(TurnDirection.reading(for: steering, in: session))
        #expect(reading.correlation < 0, "positive steering went with a left turn: \(reading.correlation)")
        #expect(reading.invert)
        #expect(reading.reference == .gpsHeading)
    }

    /// The same channel under the other convention must come out the other way, or the detector
    /// is just reporting its own assumption back.
    @Test func aRightPositiveSteeringChannelIsLeftAlone() throws {
        let session = Self.session()
        let flipped = try #require(session[.canbus("steering_angle")])
        let reading = try #require(
            TurnDirection.reading(
                for: Channel(
                    role: flipped.role, name: flipped.name, unit: flipped.unit, times: flipped.times,
                    values: flipped.values.map { -$0 }),
                in: session))
        #expect(reading.correlation > 0)
        #expect(reading.invert == false)
    }

    @Test func fallsBackToLateralAccelerationWithoutAHeading() throws {
        let full = Self.session()
        let steering = try #require(full[.canbus("steering_angle")])
        var withoutHeading = full
        withoutHeading.remove(.heading)
        #expect(TurnDirection.yawRate(of: withoutHeading) == nil)
        let reading = try #require(TurnDirection.reading(for: steering, in: withoutHeading))
        #expect(reading.reference == .lateralG)
        // Steering and lateral agree with each other here, so the documented positive-is-right
        // convention makes this look uninverted even though it is not. That is the cost of the
        // fallback, and why GPS yaw is preferred whenever it exists.
        #expect(reading.correlation > 0)
    }

    @Test func aCarThatBarelyTurnsSaysNothing() throws {
        let session = Self.session(turningFor: 12, straightFor: 3, yawRate: 0)
        let steering = try #require(session[.canbus("steering_angle")])
        #expect(TurnDirection.reading(for: steering, in: session) == nil, "no turning, no opinion")
    }

    @Test func tooShortASessionSaysNothing() throws {
        let session = Self.session(turningFor: 1, straightFor: 0.2)
        let steering = try #require(session[.canbus("steering_angle")])
        #expect(TurnDirection.reading(for: steering, in: session) == nil)
    }
}
