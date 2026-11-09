import Foundation
import Testing

@testable import TelemetryKit

@Suite("Corner metrics")
struct CornerMetricsTests {
    static let g = CoachingFixture.geometry()

    static func measured(_ driving: CoachingFixture.Driving, pedals: Bool = false) throws -> [CornerMetrics] {
        let session = CoachingFixture.session(drivings: [driving], pedals: pedals)
        let lap = session.laps[0]
        let profile = try #require(LapProfile(lap: lap, in: session))
        let corners = CornerDetector.corners(of: lap, in: session)
        #expect(corners.count == 2)
        return CornerMetrics.measure(corners: corners, of: profile)
    }

    @Test func brakePointMinimumAndPickupFromTheSpeedTrace() throws {
        let metrics = try Self.measured(CoachingFixture.fast)
        #expect(metrics.count == 2)
        for corner in metrics {
            // Braking at 0.41 g from 40 to 15 m/s needs 172 m; the 25 m smoothing shifts the
            // threshold crossing by a few metres.
            #expect(corner.brakeSource == .speedTrace)
            let brake = try #require(corner.brakePointMeters)
            #expect(abs(brake - CoachingFixture.fast.brakePointBeforeApex) < 10, "brake point \(brake)")
            #expect(abs((corner.peakBrakingG ?? 0) - 4 / LapProfile.gravity) < 0.08)
            #expect(abs(corner.minimumSpeed - 15) < 0.3)
            #expect(abs(corner.minimumSpeedMeters) < 6, "minimum at \(corner.minimumSpeedMeters)")
            #expect(corner.entrySpeed > 15 && corner.entrySpeed < 40)
            #expect(corner.exitSpeed > 15 && corner.exitSpeed < 40)
            // The throttle, read from the speed trace, comes back at the slowest point.
            #expect(corner.throttleSource == .speedTrace)
            #expect(
                abs(corner.throttlePickupMeters ?? 99) < 15, "pickup \(String(describing: corner.throttlePickupMeters))"
            )
            #expect(corner.fullThrottleMeters == nil)
            #expect(corner.coastingSeconds == nil)
            #expect(corner.steeringSmoothness == nil)
            // Lateral G peaks where the car is still fast in the bend: well over v²/r at the
            // minimum (0.38 g) and under it at turn-in speed (1.7 g), after smoothing.
            #expect((corner.peakLateralG ?? 0) > 1 && (corner.peakLateralG ?? 0) < 1.8)
            // Trail braking: the brakes stay on into the bend, since the minimum is at the apex.
            #expect((corner.trailBrakingMeters ?? 0) > 20)
            #expect(corner.timeInCorner > 0)
            // The phases tile from the brake point through the corner.
            let phases = corner.phases
            #expect(phases[.braking]?.upperBound == phases[.entry]?.lowerBound)
            #expect(phases[.entry]?.upperBound == phases[.apex]?.lowerBound)
            #expect(phases[.apex]?.upperBound == phases[.exit]?.lowerBound)
            #expect(abs((phases[.braking]?.lowerBound ?? 0) - (corner.corner.apexDistance - brake)) < 1e-6)
        }
        // The straight after a corner is its exit: the first corner's exit runs to the second's
        // brake point, the last corner's to the end of the lap.
        #expect(metrics[0].phases[.exit]?.upperBound == metrics[1].phaseStart)
        #expect(abs((metrics[1].phases[.exit]?.upperBound ?? 0) - Self.g.lapLength) < 0.01)
    }

    @Test func brakingThatBeginsAfterACornerEndsIsNotThatCorners() throws {
        // Both bends flat out, then a gentle braking from 40 to 38 m/s that begins 15 m after each
        // bend has ended, the way Sonoma's turn 1 runs into the braking for turn 2 (#438).
        var flat = CoachingFixture.Driving(minimumSpeed: 38)
        flat.minimumOffset = Self.g.bendLength / 2 + 15 + flat.brakingDistance
        let metrics = try Self.measured(flat, pedals: true)
        for corner in metrics {
            let end = corner.corner.endDistance - corner.corner.apexDistance
            #expect(end < flat.minimumOffset - flat.brakingDistance, "the braking begins after the corner ends")
            #expect(corner.brakePointMeters == nil, "took braking at \(corner.brakePointMeters ?? 0) m as its own")
            #expect(corner.minimumSpeed > 39.5, "minimum \(corner.minimumSpeed) from the next braking zone")
        }
    }

    @Test func aSlowerLapReadsItsOwnNumbers() throws {
        let metrics = try Self.measured(CoachingFixture.slow)
        let corner = try #require(metrics.first)
        #expect(abs((corner.brakePointMeters ?? 0) - CoachingFixture.slow.brakePointBeforeApex) < 10)
        #expect(abs(corner.minimumSpeed - 13) < 0.3)
        #expect(abs(corner.minimumSpeedMeters - 20) < 6)
        #expect(abs((corner.throttlePickupMeters ?? 0) - 20) < 15)
    }

    @Test func recordedPedalsAreReadBeforeTheSpeedTrace() throws {
        let metrics = try Self.measured(CoachingFixture.fast, pedals: true)
        let corner = try #require(metrics.first)
        #expect(corner.brakeSource == .brakeChannel)
        #expect(corner.throttleSource == .throttleChannel)
        #expect(abs((corner.brakePointMeters ?? 0) - CoachingFixture.fast.brakePointBeforeApex) < 3)
        #expect(abs(corner.brakeReleaseMeters ?? 99) < 3)
        #expect(abs(corner.throttlePickupMeters ?? 99) < 3)
        #expect(abs(corner.fullThrottleMeters ?? 99) < 3)
        // Straight from the brakes to the throttle: no coasting.
        #expect(abs(corner.coastingSeconds ?? 1) < 0.2)
    }

    @Test func aCornerOnTheLineIsLeftOut() throws {
        let g = Self.g
        let apex = (g.firstBend.lowerBound + g.firstBend.upperBound) / 2
        let session = SyntheticTrack.session(laps: 1, startOffset: apex)
        let lap = session.laps[0]
        let profile = try #require(LapProfile(lap: lap, in: session))
        let corners = CornerDetector.corners(of: lap, in: session)
        #expect(corners.count == 2)
        #expect(corners.contains { $0.wrapsStartFinish })
        let metrics = CornerMetrics.measure(corners: corners, of: profile)
        #expect(metrics.count == 1)
        #expect(metrics.first?.index == corners.firstIndex { !$0.wrapsStartFinish })
    }

    @Test func pedalThresholdsAreFractionsOfTheChannelsRange() {
        #expect(CornerMetrics.Reader.above([0, 0, 0], fraction: 0.05) == nil)
        #expect(CornerMetrics.Reader.above([0, 50, 100], fraction: 0.05) == [false, true, true])
        #expect(CornerMetrics.Reader.above([0, 2, 100], fraction: 0.05) == [false, false, true])
        let runs = CornerMetrics.Reader.runs(
            [false, true, true, false, false, true, false, false, false, true], from: 0, to: 9, mergingGapsUnder: 2)
        #expect(runs == [1...2, 5...5, 9...9])
        let bridged = CornerMetrics.Reader.runs(
            [false, true, true, false, false, true, false, false, false, true], from: 0, to: 9, mergingGapsUnder: 3)
        #expect(bridged == [1...5, 9...9])
    }
}

@Suite("Corner comparison")
struct CornerComparisonTests {
    @Test func theLossIsAttributedToPhasesThatAddUp() throws {
        let session = CoachingFixture.session(drivings: [CoachingFixture.fast, CoachingFixture.slow])
        let fast = try #require(LapProfile(lap: session.laps[0], in: session))
        let slow = try #require(LapProfile(lap: session.laps[1], in: session))
        let corners = CornerDetector.corners(of: session.laps[0], in: session)
        let reference = CornerMetrics.measure(corners: corners, of: fast)
        let lap = CornerMetrics.measure(corners: corners, of: slow)
        let delta = try #require(LapDeltaTrace(lap: slow, reference: fast))
        let comparisons = CornerComparison.compare(lap: lap, reference: reference, delta: delta, labels: ["1", "2a"])
        #expect(comparisons.map(\.label) == ["1", "2a"])
        for comparison in comparisons {
            #expect(comparison.timeLost > 0.3, "lost \(comparison.timeLost)")
            let sum = CornerPhase.allCases.reduce(0) { $0 + (comparison.phaseLoss[$1] ?? 0) }
            #expect(abs(sum - comparison.timeLost) < 1e-6)
            // Braking earlier and softer loses time in braking; over-slowing loses it on entry.
            #expect((comparison.phaseLoss[.braking] ?? 0) > 0)
            #expect((comparison.phaseLoss[.entry] ?? 0) > 0)
            #expect(comparison.worstPhase != nil)
        }
        // The two corners account for everything from the first brake point to the line; what
        // is lost before it belongs to the previous lap's last corner, whose exit crosses the line.
        let inCorners = comparisons.reduce(0) { $0 + $1.timeLost }
        let firstBrake = min(
            reference[0].phaseStart, corners[0].apexDistance - (lap[0].brakePointMeters ?? 0))
        let fromFirstBrake = delta.loss(from: firstBrake, to: fast.lengthMeters)
        #expect(abs(inCorners - fromFirstBrake) < 1e-6, "\(inCorners) of \(fromFirstBrake)")
        #expect(inCorners > delta.total * 0.8)
        // Exit loss runs down the straight: the slow lap leaves the corner slower and stays slower.
        #expect((comparisons[0].phaseLoss[.exit] ?? 0) > 0.2)
        // A lap against itself loses nothing anywhere.
        let level = try #require(LapDeltaTrace(lap: fast, reference: fast))
        let same = CornerComparison.compare(lap: reference, reference: reference, delta: level)
        #expect(same.allSatisfy { abs($0.timeLost) < 1e-9 && $0.worstPhase == nil })
    }
}
