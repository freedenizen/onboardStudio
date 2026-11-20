import Foundation
import Testing

@testable import TelemetryKit

/// #558: the car's grip envelope, and how much of it a lap used.
@Suite("Grip use (#558)")
struct GripTests {
    /// Points round an ellipse: braking reach `braking`, accelerating `accelerating`, cornering `cornering`.
    static func ellipse(braking: Double, accelerating: Double, cornering: Double, count: Int = 3_200)
        -> [(lateral: Double, longitudinal: Double)]
    {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let longitudinal = cos(angle) < 0 ? cos(angle) * braking : cos(angle) * accelerating
            // Points inside the edge too, as a lap has.
            let scale = 0.6 + 0.4 * Double(index % 10) / 9
            return (sin(angle) * cornering * scale, longitudinal * scale)
        }
    }

    // MARK: - The envelope

    @Test func aCarBrakesHarderThanItAccelerates() throws {
        let envelope = try #require(
            GripEnvelope.measure(Self.ellipse(braking: 1.2, accelerating: 0.4, cornering: 1.0)))
        #expect(abs(envelope.braking - 1.2) < 0.05)
        #expect(abs(envelope.accelerating - 0.4) < 0.05)
        #expect(abs(envelope.cornering - 1.0) < 0.05)
        #expect(abs(envelope.used(lateral: 0, longitudinal: -0.6) - 0.5) < 0.05)
        #expect(abs(envelope.used(lateral: 0.0, longitudinal: 0.4) - 1) < 0.1)
    }

    @Test func oneSpikeDoesNotSetTheLimit() throws {
        var points = Self.ellipse(braking: 1, accelerating: 1, cornering: 1)
        points += Array(repeating: (lateral: 0.0, longitudinal: -3.0), count: 3)
        let envelope = try #require(GripEnvelope.measure(points))
        #expect(envelope.braking < 1.1)
    }

    @Test func tooFewPointsSayNothing() {
        #expect(GripEnvelope.measure(Array(Self.ellipse(braking: 1, accelerating: 1, cornering: 1).prefix(20))) == nil)
        // Straight-line runs have no cornering to measure.
        let straight = (0..<500).map { (lateral: 0.0, longitudinal: $0 % 2 == 0 ? -0.9 : 0.4) }
        #expect(GripEnvelope.measure(straight) == nil)
    }

    @Test func sessionsMakeARange() throws {
        let low = GripEnvelope(circle: 0.9)
        let mid = GripEnvelope(circle: 1.0)
        let high = GripEnvelope(circle: 1.2)
        let range = try #require(GripEnvelope.range(of: [high, low, mid]))
        #expect(range.typical == mid && range.best == high)
        #expect(GripEnvelope.range(of: []) == nil)
        #expect(mid.scaled(by: 1.1).peak == 1.1)
    }

    @Test func aDirectionBetweenSectorsIsBetweenTheirReaches() {
        var reach = Array(repeating: 1.0, count: GripEnvelope.directions)
        reach[0] = 1.4
        let envelope = GripEnvelope(reach: reach)
        #expect(abs(envelope.limit(lateral: 0, longitudinal: -1) - 1.4) < 1e-9)
        let between = envelope.limit(lateral: sin(.pi / 16), longitudinal: -cos(.pi / 16))
        #expect(between > 1.0 && between < 1.4)
    }

    // MARK: - A lap's use of it

    static let session = CoachingFixture.session(drivings: [.init(), CoachingFixture.slow, .init()], pedals: true)

    static func use(lap number: Int, in session: TelemetrySession = session) throws -> GripUse {
        let envelope = try #require(GripEnvelope.measure(session))
        let lap = try #require(session.laps.first { $0.number == number })
        let profile = try #require(LapProfile(lap: lap, in: session))
        return try #require(GripUse.measure(profile, corners: session.agreedCorners(of: lap), envelope: envelope))
    }

    @Test func theFastLapUsesMoreOfTheGripThanTheSlowOne() throws {
        let fast = try Self.use(lap: 1)
        let slow = try Self.use(lap: 2)
        #expect(fast.meanUsed > slow.meanUsed)
        #expect(fast.corners.count == 2)
        #expect((0...1).contains(fast.nearLimit))
        #expect(fast.corners.allSatisfy { $0.peakUsed > 0.5 && $0.peakUsed < 1.5 })
        #expect(fast.roughness > 0)
    }

    @Test func brakingFinishedLongBeforeTheTurnLeavesAGap() throws {
        // Slowest 70 m before the apex: off the brakes and barely accelerating as the car turns in.
        let early = CoachingFixture.Driving(minimumSpeed: 15, minimumOffset: -70, acceleration: 0.5)
        let session = CoachingFixture.session(drivings: [.init(), early, .init()], pedals: true)
        let trailed = try Self.use(lap: 1, in: session)
        let gapped = try Self.use(lap: 2, in: session)
        let trailedGap = try #require(trailed.corners.first?.gap)
        let gap = try #require(gapped.corners.first?.gap)
        #expect(gap.lowestUsed < trailedGap.lowestUsed)
        #expect(gap.seconds > trailedGap.seconds)
    }

    @Test func noGWithoutPositionOrSpeedIsNoReading() {
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, 2],
            columns: [RawColumn(name: "rpm", unit: .rpm, suggestedRole: .rpm, values: [1, 2, 3])])
        #expect(GripEnvelope.measure(SessionBuilder.build(table)) == nil)
    }
}
