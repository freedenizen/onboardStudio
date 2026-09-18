// swiftlint:disable force_unwrapping
import Foundation
import Testing

@testable import TelemetryKit

@Suite("Resampler and smoothing")
struct ResamplerTests {
    @Test func resampleProducesUniformRate() {
        let channel = Channel(
            role: .speed, name: "S", unit: .metersPerSecond, times: [0, 0.3, 1.0, 2.0], values: [0, 3, 10, 20])
        let out = Resampler.resample(channel, hertz: 10)
        #expect(out.count == 21)
        #expect(out.times[10] == 1.0 && out.values[10] == 10)
        #expect(abs(out.values[5] - 5) < 1e-9)
        #expect(abs((out.sampleRate ?? 0) - 10) < 1e-9)
    }

    @Test func smoothingAveragesButLeavesStepChannels() {
        let times = (0..<10).map { Double($0) }
        let noisy = Channel(
            role: .speed, name: "S", unit: .metersPerSecond, times: times, values: [0, 10, 0, 10, 0, 10, 0, 10, 0, 10])
        let smoothed = Resampler.smooth(noisy, windowSeconds: 2)
        #expect(smoothed.count == 10)
        #expect(abs(smoothed.values[4] - (10 + 0 + 10) / 3.0) < 1e-9)
        let gear = Channel(
            role: .gear, name: "G", unit: .count, times: times, values: [1, 2, 1, 2, 1, 2, 1, 2, 1, 2],
            interpolation: .step)
        #expect(Resampler.smooth(gear, windowSeconds: 2).values == gear.values)
    }

    @Test func headingSmoothingWrapsAroundNorth() {
        let heading = Channel(role: .heading, name: "H", unit: .degrees, times: [0, 1, 2], values: [359, 1, 359])
        let smoothed = Resampler.smoothHeading(heading, windowSeconds: 2)
        let mid = smoothed.values[1]
        #expect(mid < 2 || mid > 358, "expected ~0°, got \(mid)")
    }
}

@Suite("Expressions")
struct ExpressionTests {
    func eval(_ source: String, _ values: [String: Double] = ["speed": 10, "rpm": 3000]) throws -> Double? {
        try Expression(source).evaluate { values[$0] }
    }

    @Test func arithmeticAndPrecedence() throws {
        #expect(try eval("1 + 2 * 3") == 7)
        #expect(try eval("(1 + 2) * 3") == 9)
        #expect(try eval("-speed + 12") == 2)
        #expect(try eval("10 % 4") == 2)
        #expect(try eval("speed * 3.6") == 36)
    }

    @Test func comparisonsLogicAndFunctions() throws {
        #expect(try eval("rpm > 2500 && speed < 20") == 1)
        #expect(try eval("rpm > 2500 && speed > 20") == 0)
        #expect(try eval("!(speed == 10)") == 0)
        #expect(try eval("if(rpm >= 3000, 1, 0)") == 1)
        #expect(try eval("max(speed, rpm)") == 3000)
        #expect(try eval("clamp(speed, 0, 5)") == 5)
        #expect(try eval("sqrt(16) + abs(-2) + floor(2.7) + ceil(2.1) + round(2.5)") == 4 + 2 + 2 + 3 + 3)
        #expect(try eval("pow(2, 10)") == 1024)
    }

    @Test func bracketedNamesAndReferences() throws {
        let expression = try Expression("[aux:Oil temp] - obd:Coolant")
        #expect(expression.references == ["aux:Oil temp", "obd:Coolant"])
        #expect(expression.evaluate { ["aux:Oil temp": 110, "obd:Coolant": 90][$0] } == 20)
    }

    @Test func missingChannelsAndDivisionByZeroYieldNil() throws {
        #expect(try eval("speed / 0") == nil)
        #expect(try eval("missing * 2") == nil)
    }

    @Test func syntaxErrorsThrow() {
        #expect(throws: ExpressionError.self) { try Expression("1 +") }
        #expect(throws: ExpressionError.self) { try Expression("(1 + 2") }
        #expect(throws: ExpressionError.self) { try Expression("1 $ 2") }
        #expect(throws: ExpressionError.self) { try Expression("[unterminated") }
    }

    @Test func calculatedFieldJoinsASession() throws {
        var session = TelemetrySession(
            info: SessionInfo(sourceFormat: "t"),
            channels: [
                Channel(role: .speed, name: "S", unit: .metersPerSecond, times: [0, 1, 2], values: [10, 20, 30]),
                Channel(role: .rpm, name: "R", unit: .rpm, times: [0, 2], values: [1000, 3000]),
            ])
        try session.addCalculatedField(CalculatedField(name: "kph", expression: "speed * 3.6", unit: "km/h"))
        let kph = try #require(session[.aux("kph")])
        #expect(kph.values == [36, 72, 108] && kph.unit == .kilometersPerHour)
        try session.addCalculatedField(CalculatedField(name: "ratio", expression: "rpm / speed"))
        #expect(session[.aux("ratio")]?.value(at: 1) == 100)  // rpm interpolated to 2000 at t=1
    }
}

@Suite("Lap detector")
struct LapDetectorTests {
    /// Three laps around a 400 m square at 20 m/s, sampled at 10 Hz, starting mid-way along the
    /// south edge and heading east. The finish line is on the south edge.
    static func squareSession(laps: Int = 3, startFraction: Double = 0.5) -> TelemetrySession {
        let side = 100.0  // meters
        let speed = 20.0
        let hz = 10.0
        let lapTime = 4 * side / speed  // 20 s
        var times: [Double] = []
        var lat: [Double] = []
        var lon: [Double] = []
        let metersPerDegLat = 110_540.0
        let metersPerDegLon = 111_320.0 * cos(45 * Double.pi / 180)
        let total = lapTime * Double(laps)
        var t = 0.0
        while t <= total + 1e-9 {
            let d = (speed * t + startFraction * side).truncatingRemainder(dividingBy: 4 * side)
            let (x, y): (Double, Double)
            switch d {
            case ..<side: (x, y) = (d, 0)  // south edge, heading east
            case ..<(2 * side): (x, y) = (side, d - side)  // east edge, heading north
            case ..<(3 * side): (x, y) = (side - (d - 2 * side), side)  // north edge, heading west
            default: (x, y) = (0, side - (d - 3 * side))  // west edge, heading south
            }
            times.append(t)
            lat.append(45 + y / metersPerDegLat)
            lon.append(-122 + x / metersPerDegLon)
            t += 1 / hz
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: lat),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: lon),
            ])
    }

    @Test func detectsCrossingsWithSubSampleTiming() {
        let session = Self.squareSession()
        // Finish line 80 m along the south edge (x=80, y=0), crossed heading east (90°).
        let line = FinishLine(
            latitude: 45, longitude: -122 + 80 / (111_320 * cos(45 * Double.pi / 180)), headingDegrees: 90,
            halfWidthMeters: 20)
        let crossings = LapDetector.crossings(
            latitude: session[.latitude]!, longitude: session[.longitude]!, line: line)
        // Start at x=50 heading east: first crossing after 30 m = 1.5 s, then every 20 s.
        #expect(crossings.count == 3)
        #expect(abs(crossings[0].time - 1.5) < 0.02)
        #expect(abs(crossings[1].time - 21.5) < 0.02)
        #expect(abs(crossings[2].time - 41.5) < 0.02)
        #expect(abs(crossings[0].headingDegrees - 90) < 1)
    }

    @Test func headingFilterRejectsOppositeDirection() {
        let session = Self.squareSession()
        let line = FinishLine(
            latitude: 45, longitude: -122 + 80 / (111_320 * cos(45 * Double.pi / 180)), headingDegrees: 270,
            halfWidthMeters: 20)
        #expect(
            LapDetector.crossings(latitude: session[.latitude]!, longitude: session[.longitude]!, line: line).isEmpty)
    }

    @Test func halfWidthRejectsFarPasses() {
        let session = Self.squareSession()
        // Line point 60 m north of the south edge with a 20 m half-width: the car never comes near.
        let line = FinishLine(
            latitude: 45 + 60 / 110_540, longitude: -122 + 80 / (111_320 * cos(45 * Double.pi / 180)),
            headingDegrees: 90, halfWidthMeters: 20)
        #expect(
            LapDetector.crossings(latitude: session[.latitude]!, longitude: session[.longitude]!, line: line).isEmpty)
    }

    @Test func buildsLapsWithWarmupAndIgnoreFirst() {
        let session = Self.squareSession()
        let line = FinishLine(
            latitude: 45, longitude: -122 + 80 / (111_320 * cos(45 * Double.pi / 180)), headingDegrees: 90,
            halfWidthMeters: 20)
        let laps = LapDetector.detect(in: session, line: line)
        #expect(laps.map(\.number) == [0, 1, 2, 3])
        #expect(laps[0].isComplete == false && laps[0].start == 0)
        #expect(abs((laps[1].duration ?? 0) - 20) < 0.03)
        #expect(laps[1].isComplete && laps[2].isComplete && !laps[3].isComplete)
        let skipped = LapDetector.detect(in: session, line: line, ignoreFirst: 1)
        #expect(skipped.map(\.number) == [0, 1, 2])
        #expect(abs(skipped[1].start - 21.5) < 0.02)
    }

    @Test func finishLineFromCurrentPosition() {
        let session = Self.squareSession()
        let line = LapDetector.finishLine(at: 1.5, in: session)
        #expect(line != nil)
        #expect(abs((line?.latitude ?? 0) - 45) < 1e-6)
    }

    @Test func builderUsesFinishLineWhenGiven() {
        let session = Self.squareSession()
        let table = RawTable(
            info: session.info, times: session[.latitude]!.times,
            columns: [
                RawColumn(
                    name: "lat", unit: .degrees, suggestedRole: .latitude,
                    values: session[.latitude]!.values as [Double?]),
                RawColumn(
                    name: "lon", unit: .degrees, suggestedRole: .longitude,
                    values: session[.longitude]!.values as [Double?]),
            ])
        let line = FinishLine(
            latitude: 45, longitude: -122 + 80 / (111_320 * cos(45 * Double.pi / 180)), headingDegrees: 90,
            halfWidthMeters: 20)
        let built = SessionBuilder.build(table, options: .init(finishLine: line, ignoreFirstCrossings: 0))
        #expect(built.laps.count == 4)
        let smoothed = SessionBuilder.build(table, options: .init(resampleHertz: 20, smoothingSeconds: 0.5))
        #expect(abs((smoothed[.speed]?.sampleRate ?? 0) - 20) < 0.5)
    }
}
// swiftlint:enable force_unwrapping
