import Foundation
import Testing

@testable import TelemetryKit

/// A point-to-point course driven by script: straight legs at a speed, and stops. Positions are
/// metres east and north of a fixed origin, sampled ten times a second.
enum ScriptedDrive {
    enum Step {
        case drive(toX: Double, y: Double, speed: Double)
        case stop(seconds: Double)
    }

    static let origin = (latitude: 47.0, longitude: 8.0)
    static let metersPerDegreeEast = 111_320 * cos(origin.latitude * .pi / 180)

    static func session(from start: (x: Double, y: Double), _ steps: [Step], hertz: Double = 10) -> TelemetrySession {
        var times: [Double] = []
        var lats: [Double] = []
        var lons: [Double] = []
        var speeds: [Double] = []
        var distances: [Double] = []
        var now = 0.0
        var position = start
        var travelled = 0.0
        let dt = 1 / hertz
        func emit(_ speed: Double) {
            times.append(now)
            lats.append(origin.latitude + position.y / 110_540)
            lons.append(origin.longitude + position.x / metersPerDegreeEast)
            speeds.append(speed)
            distances.append(travelled)
            now += dt
        }
        for step in steps {
            switch step {
            case .stop(let seconds):
                for _ in 0..<Int(seconds * hertz) { emit(0) }
            case .drive(let x, let y, let speed):
                let dx = x - position.x
                let dy = y - position.y
                let length = (dx * dx + dy * dy).squareRoot()
                let count = max(1, Int((length / (speed * dt)).rounded()))
                for _ in 0..<count {
                    position = (position.x + dx / Double(count), position.y + dy / Double(count))
                    travelled += length / Double(count)
                    emit(speed)
                }
            }
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "scripted"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: lats),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: lons),
                Channel(role: .speed, name: "speed", unit: .metersPerSecond, times: times, values: speeds),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
            ])
    }

    /// A line across the course at (`x`, `y`), crossed going `heading` degrees.
    static func line(x: Double, y: Double, heading: Double) -> FinishLine {
        FinishLine(
            latitude: origin.latitude + y / 110_540, longitude: origin.longitude + x / metersPerDegreeEast,
            headingDegrees: heading, halfWidthMeters: 15)
    }
}

@Suite struct RunDetectorTests {
    /// Start at (0, 0) going east; finish at (100, 100) going west. The course passes the finish
    /// once mid-run, going the same way, and crosses the start again too.
    static let start = ScriptedDrive.line(x: 0, y: 0, heading: 90)
    static let finish = ScriptedDrive.line(x: 100, y: 100, heading: 270)

    /// 1,040 m from the start line to the finish line.
    static func course(speed: Double) -> [ScriptedDrive.Step] {
        [
            .drive(toX: 200, y: 0, speed: speed), .drive(toX: 200, y: 100, speed: speed),
            .drive(toX: -20, y: 100, speed: speed),  // through the finish, mid-run
            .drive(toX: -20, y: 0, speed: speed), .drive(toX: 200, y: 0, speed: speed),  // past the start again
            .drive(toX: 200, y: 100, speed: speed), .drive(toX: 50, y: 100, speed: speed),  // the finish
            .stop(seconds: 5),
        ]
    }

    /// Back round the outside to the grid, crossing neither line, and staged.
    static let backToGrid: [ScriptedDrive.Step] = [
        .drive(toX: 50, y: 150, speed: 8), .drive(toX: -60, y: 150, speed: 8), .drive(toX: -60, y: 0, speed: 8),
        .drive(toX: -10, y: 0, speed: 5), .stop(seconds: 10),
    ]

    static func autocross() -> TelemetrySession {
        var steps: [ScriptedDrive.Step] = [.stop(seconds: 10)]
        steps += course(speed: 20) + backToGrid
        steps += course(speed: 16) + backToGrid
        // Off course: the third run turns away before the finish and stops.
        steps += [
            .drive(toX: 200, y: 0, speed: 20), .drive(toX: 200, y: 100, speed: 20),
            .drive(toX: 150, y: 100, speed: 20), .stop(seconds: 5),
        ]
        return ScriptedDrive.session(from: (-10, 0), steps)
    }

    @Test func autocrossRunsEndAtTheLastFinishCrossingNotTheFirst() throws {
        let laps = RunDetector.detect(in: Self.autocross(), start: Self.start, finish: Self.finish)
        let runs = laps.listed
        #expect(runs.map(\.number) == [1, 2, 3])
        #expect(runs.map(\.kind) == [.run, .run, .run])
        #expect(runs.map(\.isComplete) == [true, true, false])
        // 1,040 m at 20 and at 16 m/s, to a sample.
        #expect(abs(try #require(runs[0].duration) - 52) < 0.2)
        #expect(abs(try #require(runs[1].duration) - 65) < 0.2)
    }

    @Test func theDrivingBetweenRunsIsTransitAndTheLapsCoverTheSession() throws {
        let session = Self.autocross()
        let laps = RunDetector.detect(in: session, start: Self.start, finish: Self.finish)
        let range = try #require(session.timeRange)
        #expect(laps.first?.start == range.lowerBound)
        #expect(laps.last?.end == range.upperBound)
        for (earlier, later) in zip(laps, laps.dropFirst()) { #expect(earlier.end == later.start) }
        let transit = laps.filter { $0.kind == .transit }
        #expect(transit.map(\.number) == [-1, -2, -3, -4])
        #expect(transit.allSatisfy { !$0.isComplete && !$0.isListed })
    }

    @Test func lapTimingBetweenRunsHasNoCurrentLap() throws {
        let laps = RunDetector.detect(in: Self.autocross(), start: Self.start, finish: Self.finish)
        let between = try #require(laps.first { $0.kind == .transit && $0.number == -2 })
        let timing = LapTiming.resolve(at: between.start + 1, laps: laps)
        #expect(timing.currentLap == nil)
        #expect(timing.lastLapTime != nil)
        #expect(laps.lap(startingAfter: between.start)?.number == 2)
    }

    @Test func aHillClimbsDriveBackDownCrossesNeitherLine() {
        let start = ScriptedDrive.line(x: 0, y: 0, heading: 0)
        let finish = ScriptedDrive.line(x: 0, y: 900, heading: 0)
        let up: [ScriptedDrive.Step] = [.drive(toX: 0, y: 1000, speed: 30), .stop(seconds: 30)]
        let down: [ScriptedDrive.Step] = [.drive(toX: 0, y: -10, speed: 10), .stop(seconds: 60)]
        let session = ScriptedDrive.session(from: (0, -10), [.stop(seconds: 5)] + up + down + up)
        let runs = RunDetector.detect(in: session, start: start, finish: finish).listed
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.isComplete })
        #expect(runs.allSatisfy { abs(($0.duration ?? 0) - 30) < 0.2 })
    }

    @Test func aLineWithNoDirectionTakesTheOneItWasFirstCrossedIn() {
        // A VBO gate says where a line is, not which way it is crossed.
        var start = ScriptedDrive.line(x: 0, y: 0, heading: 0)
        var finish = ScriptedDrive.line(x: 0, y: 900, heading: 0)
        start.headingDegrees = nil
        finish.headingDegrees = nil
        let up: [ScriptedDrive.Step] = [.drive(toX: 0, y: 1000, speed: 30), .stop(seconds: 30)]
        let down: [ScriptedDrive.Step] = [.drive(toX: 0, y: -10, speed: 10), .stop(seconds: 60)]
        let session = ScriptedDrive.session(from: (0, -10), [.stop(seconds: 5)] + up + down + up)
        let runs = RunDetector.detect(in: session, start: start, finish: finish).listed
        #expect(runs.count == 2, "the drive back down is not a run")
        #expect(runs.allSatisfy { $0.isComplete })
    }

    @Test func oneLineCanBeBothTheStartAndTheFinishOfALoop() throws {
        let line = ScriptedDrive.line(x: 0, y: 0, heading: 90)
        let loop: [ScriptedDrive.Step] = [
            .drive(toX: 100, y: 0, speed: 20), .drive(toX: 100, y: 100, speed: 20),
            .drive(toX: -50, y: 100, speed: 20), .drive(toX: -50, y: 0, speed: 20),
            .drive(toX: 50, y: 0, speed: 20), .stop(seconds: 5),
        ]
        let session = ScriptedDrive.session(from: (-10, 0), [.stop(seconds: 5)] + loop)
        let runs = RunDetector.detect(in: session, start: line, finish: line).listed
        #expect(runs.count == 1)
        // 500 m round the loop at 20 m/s.
        #expect(abs(try #require(runs.first?.duration) - 25) < 0.2)
    }

    @Test func noStartCrossingMeansNoRuns() {
        let session = ScriptedDrive.session(from: (500, 500), [.drive(toX: 600, y: 500, speed: 10)])
        #expect(RunDetector.detect(in: session, start: Self.start, finish: Self.finish).isEmpty)
    }

    @Test func aLapDecodedFromBeforeRunsIsALap() throws {
        let json = Data(#"{"number":3,"start":1,"end":2,"isComplete":true}"#.utf8)
        let lap = try JSONDecoder().decode(Lap.self, from: json)
        #expect(lap.kind == .lap)
        #expect(lap.isListed)
    }
}
