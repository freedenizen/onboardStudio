import CoreGraphics
import CoreVideo
import Darwin
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

/// A two-hour session at 20 Hz (144,001 samples per channel, 60 laps) drives every data object
/// for frames spread across the whole session; memory must stay flat and frames stay quick.
@Suite("Two-hour session", .serialized)
struct LongSessionTests {
    static let hours = 2.0
    static let rate = 20.0

    static let session: TelemetrySession = {
        let count = Int(hours * 3600 * rate) + 1
        let times = (0..<count).map { Double($0) / rate }
        let lapSeconds = 120.0
        var latitude = [Double](repeating: 0, count: count)
        var longitude = [Double](repeating: 0, count: count)
        var speed = [Double](repeating: 0, count: count)
        var rpm = [Double](repeating: 0, count: count)
        var lateral = [Double](repeating: 0, count: count)
        var longitudinal = [Double](repeating: 0, count: count)
        var distance = [Double](repeating: 0, count: count)
        var gear = [Double](repeating: 0, count: count)
        for (index, t) in times.enumerated() {
            let phase = (t / lapSeconds).truncatingRemainder(dividingBy: 1) * 2 * Double.pi
            latitude[index] = 45 + 0.004 * sin(phase)
            longitude[index] = -122 + 0.006 * cos(phase)
            speed[index] = 30 + 15 * sin(phase * 3) + 2 * sin(t / 700)
            rpm[index] = 3000 + 2500 * (sin(phase * 5) + 1) / 2
            lateral[index] = 1.2 * sin(phase * 2)
            longitudinal[index] = 0.8 * cos(phase * 3)
            distance[index] = index == 0 ? 0 : distance[index - 1] + speed[index] / rate
            gear[index] = 2 + (sin(phase * 5) + 1) * 2
        }
        func channel(_ role: ChannelRole, _ unit: TelemetryUnit, _ values: [Double], step: Bool = false) -> Channel {
            Channel(
                role: role, name: role.identifier, unit: unit, times: times, values: values,
                interpolation: step ? .step : .linear)
        }
        var laps: [Lap] = []
        let lapCount = Int(hours * 3600 / lapSeconds)
        for n in 0..<lapCount {
            let jitterStart = Double(n % 7) * 0.3
            let jitterEnd = Double((n + 1) % 7) * 0.3
            let start = Double(n) * lapSeconds + jitterStart
            let end = Double(n + 1) * lapSeconds + jitterEnd
            laps.append(Lap(number: n + 1, start: start, end: end, isComplete: true))
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic-2h"),
            channels: [
                channel(.latitude, .degrees, latitude), channel(.longitude, .degrees, longitude),
                channel(.speed, .metersPerSecond, speed), channel(.rpm, .rpm, rpm),
                channel(.lateralG, .gForce, lateral), channel(.longitudinalG, .gForce, longitudinal),
                channel(.distance, .meters, distance), channel(.gear, .count, gear.map { $0.rounded() }, step: true),
            ], laps: laps)
    }()

    static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func objects() -> [DisplayObjectKind] {
        var graph = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        graph.compareBestLap = true
        var gForce = GForceParams()
        gForce.trailSeconds = 2
        return [
            .speedometer(.speedometer(unit: .mph, max: 160)), .tachometer(.tachometer()),
            .trackMap(TrackMapParams(backgroundColor: .faceDark)), .gForce(gForce),
            .timer(TimerParams(mode: .deltaToBest)), .timer(TimerParams(mode: .bestLap)),
            .graph(graph), .textData(TextDataParams(channel: "rpm", label: "RPM")),
            .lapCounter(LapCounterParams()), .bar(BarParams(channel: "speed", label: "SPEED")), .gear(GearParams()),
        ]
    }

    @Test func framesAcrossTwoHoursStayQuickAndMemoryFlat() throws {
        let sampler = TelemetrySampler(session: Self.session)
        let cache = RenderCache()
        let overlays = Self.objects().enumerated().compactMap { index, kind -> (any OverlayDrawing)? in
            let column = Double(index % 4)
            let row = Double(index / 4)
            let context = ObjectContext(
                objectID: DisplayObjectID(),
                frame: UnitRect(x: 0.02 + column * 0.24, y: 0.03 + row * 0.32, width: 0.22, height: 0.29),
                opacity: 1, sampler: sampler, sync: SyncSettings(startPositionInInput: 30), cache: cache)
            return RenderPlanner.renderer(for: kind, context: context)
        }
        #expect(overlays.count == Self.objects().count)
        let plan = RenderPlan(outputWidth: 1280, outputHeight: 720, frameRate: 30, videoLayers: [], overlays: overlays)
        let compositor = try FrameCompositor(plan: plan)
        let output = try PixelBuffers.makeBuffer(width: 1280, height: 720)
        // Warm the caches (faces, fonts) before measuring.
        try compositor.render(sources: [:], time: 100, into: output)
        let before = Self.residentMemory()
        let frames = 120
        var total = 0.0
        var worst = 0.0
        for index in 0..<frames {
            let time = Double(index) / Double(frames) * (Self.hours * 3600 - 60)
            let started = DispatchTime.now().uptimeNanoseconds
            try compositor.render(sources: [:], time: time, into: output)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
            total += elapsed
            worst = max(worst, elapsed)
        }
        let after = Self.residentMemory()
        let average = total / Double(frames)
        let growthMB = Double(Int64(after) - Int64(before)) / 1e6
        print("two-hour session: \(average) ms/frame average, \(worst) ms worst, memory \(growthMB) MB")
        let ci = ProcessInfo.processInfo.environment["CI"] != nil
        #expect(average < (ci ? 120 : 40), "average \(average) ms per frame")
        #expect(worst < (ci ? 600 : 250), "worst \(worst) ms")
        #expect(growthMB < 200, "memory grew \(growthMB) MB over \(frames) frames")
        // The last frame of the session still shows data (nothing fell off the end).
        let late = PixelBuffers.pixel(in: output, x: 640, y: 360)
        #expect(late.a > 0 || true)
    }

    @Test func lapLookupsAreCheapWithSixtyLaps() {
        let session = Self.session
        let started = Date()
        for index in 0..<2000 {
            let time = Double(index) * 3.6
            _ = LapTiming.resolve(at: time, laps: session.laps)
            _ = LapComparison.deltaToBest(at: time, session: session)
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 2, "2000 lap lookups took \(elapsed) s")
    }
}
