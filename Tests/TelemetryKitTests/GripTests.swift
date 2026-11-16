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

    // MARK: - In coaching

    static func profile(_ number: Int, in session: TelemetrySession) throws -> LapProfile {
        let lap = try #require(session.laps.first { $0.number == number })
        return try #require(LapProfile(lap: lap, in: session))
    }

    @Test func coachingSaysWhereBrakingStoppedBeforeTurningWhenTheReferenceDidNot() throws {
        let session = Self.session
        let analysis = try #require(
            CoachingAnalysis.analyse(
                lap: try Self.profile(2, in: session), in: session, reference: try Self.profile(1, in: session),
                referencePhrase: "your best lap", sameSession: true))
        var corner = try #require(analysis.corners.first)
        #expect(corner.lapGrip != nil && corner.referenceGrip != nil, "both laps read")
        func grip(_ lowest: Double, mean: Double) -> GripUse.Corner {
            GripUse.Corner(
                index: corner.index, label: corner.label, meanUsed: mean, peakUsed: 1, nearLimit: 0.2,
                gap: GripUse.Gap(lowestUsed: lowest, lowestG: lowest, seconds: 0.6, at: 100))
        }
        corner.lapGrip = grip(0.25, mean: 0.6)
        corner.referenceGrip = grip(0.8, mean: 0.8)
        let context = CoachingNotes.Context(
            comparison: corner, phase: .entry, kind: .coasting, spread: nil, referencePhrase: "your best lap",
            units: .metric, options: CoachingOptions())
        let note = CoachingNotes.note(context)
        #expect(
            note.evidence.contains(
                "Braking stopped before turning: combined G fell to 0.25 g (your best lap kept 0.80 g)"),
            "\(note.evidence)")
        #expect(note.evidence.contains("Used 60% of the grip through it against 80%"))
        #expect(
            note.suggestion.hasSuffix(
                "Keep a little brake on as you turn in, so the braking runs into the "
                    + "cornering rather than stopping before it."))
        // The reference stopped braking before turning as much: nothing to say.
        corner.referenceGrip = grip(0.3, mean: 0.62)
        let same = CoachingNotes.note(
            .init(
                comparison: corner, phase: .entry, kind: .coasting, spread: nil, referencePhrase: "your best lap",
                units: .metric, options: CoachingOptions()))
        #expect(!same.evidence.contains { $0.hasPrefix("Braking stopped") || $0.hasPrefix("Used ") })
        #expect(!same.suggestion.contains("Keep a little brake on"))
    }

    @Test func theCarsGripIsUsedWhenGiven() throws {
        let session = Self.session
        let reference = try Self.profile(1, in: session)
        let lap = try Self.profile(2, in: session)
        var options = CoachingOptions()
        options.gripEnvelope = GripEnvelope(circle: 4)
        let analysis = try #require(
            CoachingAnalysis.analyse(
                lap: lap, in: session, reference: reference, referencePhrase: "lap 1", sameSession: true,
                options: options))
        // Against four g, nothing comes near the limit.
        #expect(analysis.corners.allSatisfy { ($0.lapGrip?.peakUsed ?? 1) < 0.5 })
    }

    @Test func aSessionFromAnOlderProjectIsCoachedWithoutGrip() throws {
        var session = Self.session
        session.legacyNoGripNotes = true
        let analysis = try #require(
            CoachingAnalysis.analyse(
                lap: try Self.profile(2, in: session), in: session, reference: try Self.profile(1, in: session),
                referencePhrase: "lap 1", sameSession: true))
        #expect(analysis.corners.allSatisfy { $0.lapGrip == nil && $0.referenceGrip == nil })
    }

    // MARK: - The overlay channel

    @Test func recordedGMakesAGripUsedChannelAgainstTheSessionsOwnGrip() throws {
        let points = Self.ellipse(braking: 1.0, accelerating: 0.5, cornering: 1.0, count: 2_000)
        let times = points.indices.map { Double($0) * 0.1 }
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: times,
            columns: [
                RawColumn(name: "lat g", unit: .gForce, suggestedRole: .lateralG, values: points.map(\.lateral)),
                RawColumn(
                    name: "long g", unit: .gForce, suggestedRole: .longitudinalG, values: points.map(\.longitudinal)),
            ])
        let session = SessionBuilder.build(table)
        let channel = try #require(session[.gripUsed])
        #expect(channel.unit == .percent)
        #expect((channel.values.max() ?? 0) > 95 && (channel.values.max() ?? 0) <= 150)
        let finite = channel.values.allSatisfy { $0.isFinite }
        #expect(finite)
    }

    @Test func noRecordedGNoGripUsedChannel() {
        #expect(Self.session[.gripUsed] == nil, "the fixture's G is only derived")
    }
}
