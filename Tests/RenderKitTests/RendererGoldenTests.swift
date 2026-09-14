import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

/// A small synthetic session: 10 s, one square lap, speed ramp, g-force sweep, rpm.
enum SyntheticSession {
    static let session: TelemetrySession = {
        let times = Array(stride(from: 0.0, through: 10.0, by: 0.1))
        func channel(_ role: ChannelRole, _ unit: TelemetryUnit, _ f: (Double) -> Double, step: Bool = false) -> Channel
        {
            Channel(
                role: role, name: role.identifier, unit: unit, times: times, values: times.map(f),
                interpolation: step ? .step : .linear)
        }
        // Square track ~100 m per side, north-up, starting at the SW corner.
        func position(_ t: Double) -> (lat: Double, lon: Double) {
            let side = 0.0009
            let phase = (t / 10).truncatingRemainder(dividingBy: 1) * 4
            switch phase {
            case ..<1: return (45 + side * phase, -122)
            case ..<2: return (45 + side, -122 + side * (phase - 1) / cos(45 * Double.pi / 180))
            case ..<3: return (45 + side * (3 - phase), -122 + side / cos(45 * Double.pi / 180))
            default: return (45, -122 + side * (4 - phase) / cos(45 * Double.pi / 180))
            }
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                channel(.latitude, .degrees) { position($0).lat },
                channel(.longitude, .degrees) { position($0).lon },
                channel(.speed, .metersPerSecond) { 10 + 2.5 * $0 },  // 10…35 m/s
                channel(.rpm, .rpm) { 2000 + 500 * $0 },
                channel(.lateralG, .gForce) { 0.8 * sin($0 / 10 * 2 * .pi) },
                channel(.longitudinalG, .gForce) { 0.5 * cos($0 / 10 * 2 * .pi) },
                channel(.gear, .count, { min(6, 1 + ($0 / 2).rounded(.down)) }, step: true),
            ],
            laps: [
                Lap(number: 0, start: 0, end: 4, isComplete: true),
                Lap(number: 1, start: 4, end: 8.5, isComplete: true),
                Lap(number: 2, start: 8.5, end: 10, isComplete: false),
            ]
        )
    }()
}

@Suite("Renderer goldens")
struct RendererGoldenTests {
    let size = CGSize(width: 400, height: 400)

    func render(
        _ kind: DisplayObjectKind, frame: UnitRect = UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), time: Double,
        sync: SyncSettings = .identity
    ) throws -> CVPixelBuffer {
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()), frame: frame,
            opacity: 1,
            sampler: TelemetrySampler(session: SyntheticSession.session), sync: sync, cache: RenderCache())
        let renderer = try #require(RenderPlanner.renderer(for: kind, context: context))
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    @Test func speedometer() throws {
        let frame = try render(.speedometer(.speedometer(unit: .mph, max: 120)), time: 5)
        try GoldenImage.assertMatches(frame, named: "speedometer-mph-5s")
    }

    @Test func tachometerWithRedline() throws {
        let frame = try render(.tachometer(.tachometer(max: 8000, redline: 6500)), time: 8)
        try GoldenImage.assertMatches(frame, named: "tachometer-8s")
    }

    @Test func gaugeCustomSweepAndDivisor() throws {
        var params = GaugeParams.tachometer(max: 8, redline: 6.5)
        params.valueDivisor = 1000
        params.sweep = 180
        params.rotation = 0
        params.title = "x1000"
        params.majorTick = 1
        params.minorTick = 0.5
        let frame = try render(.gauge(params), time: 4)
        try GoldenImage.assertMatches(frame, named: "gauge-half-sweep-4s")
    }

    @Test func trackMap() throws {
        let frame = try render(.trackMap(TrackMapParams(backgroundColor: .faceDark)), time: 2.5)
        try GoldenImage.assertMatches(frame, named: "trackmap-2.5s")
    }

    @Test func gForce() throws {
        let frame = try render(.gForce(GForceParams(maxG: 1.5)), time: 2.5)
        try GoldenImage.assertMatches(frame, named: "gforce-2.5s")
    }

    @Test func timerModes() throws {
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        try GoldenImage.assertMatches(
            try render(.timer(TimerParams(mode: .currentLap)), frame: frame, time: 6), named: "timer-current-6s")
        try GoldenImage.assertMatches(
            try render(.timer(TimerParams(mode: .bestLap)), frame: frame, time: 9), named: "timer-best-9s")
    }

    @Test func textData() throws {
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        let params = TextDataParams(channel: "speed", label: "SPEED", speedUnit: .kph, alignment: .trailing)
        try GoldenImage.assertMatches(
            try render(.textData(params), frame: frame, time: 4), named: "textdata-speed-kph-4s")
    }

    @Test func syncOffsetShiftsSampledTime() throws {
        // With a 4 s start position, project time 1 s samples input time 5 s → same as the speedometer golden.
        let sync = SyncSettings(startPositionInInput: 4)
        let frame = try render(.speedometer(.speedometer(unit: .mph, max: 120)), time: 1, sync: sync)
        try GoldenImage.assertMatches(frame, named: "speedometer-mph-5s")
    }
}

@Suite("Renderer behaviour")
struct RendererBehaviourTests {
    @Test func gaugeAngleMapsRange() {
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: nil, sync: .identity, cache: RenderCache())
        let gauge = GaugeRenderer(context: context, params: .speedometer(max: 100))
        let start = gauge.angle(for: 0)
        let end = gauge.angle(for: 100)
        #expect(abs((end - start) - 270 * Double.pi / 180) < 1e-9)
        #expect(gauge.angle(for: -50) == start)  // clamped
        #expect(abs(gauge.angle(for: 50) - (-Double.pi / 2)) < 1e-9)  // mid-scale points straight up
    }

    @Test func timerTextsFollowMode() {
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1,
            sampler: TelemetrySampler(session: SyntheticSession.session),
            sync: .identity, cache: RenderCache())
        let sample = context.sample(at: 6)
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .currentLap)).timeText(
                sample: sample, projectTime: 6) == "0:02.00")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .lastLap)).timeText(
                sample: sample, projectTime: 6) == "0:04.00")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .bestLap)).labelText(sample: sample) == "BEST 0")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .currentLap)).labelText(sample: sample) == "LAP 1"
        )
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .session)).timeText(
                sample: sample, projectTime: 6) == "0:06.00")
    }

    @Test func plannerBuildsOneRendererPerVisibleDataObject() {
        let data = Input(label: "d", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let video = Input(label: "v", source: MediaReference(path: "x.mp4"), kind: .video(VideoInputSettings()))
        let project = Project(
            inputs: [video, data],
            displayObjects: [
                DisplayObject(label: "v", inputID: video.id, frame: .full, kind: .video(VideoObjectParams())),
                DisplayObject(label: "s", inputID: data.id, frame: .full, kind: .speedometer(.speedometer())),
                DisplayObject(
                    label: "hidden", inputID: data.id, frame: .full, isVisible: false, kind: .gForce(GForceParams())),
                DisplayObject(label: "t", inputID: data.id, frame: .full, kind: .timer(TimerParams())),
            ])
        let overlays = RenderPlanner.overlays(for: project, sessions: [data.id: SyntheticSession.session])
        #expect(overlays.count == 2)
        #expect(overlays[0] is GaugeRenderer && overlays[1] is TimerRenderer)
        let layers = RenderPlanner.videoLayers(for: project, trackIDs: [video.id: 42])
        #expect(layers == [VideoLayer(trackID: 42, frame: .full, opacity: 1)])
    }

    @Test func renderersToleratMissingData() throws {
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: nil, sync: .identity, cache: RenderCache())
        let kinds: [DisplayObjectKind] = [
            .speedometer(.speedometer()), .trackMap(TrackMapParams()), .gForce(GForceParams()), .timer(TimerParams()),
            .textData(TextDataParams(channel: "rpm", label: "RPM")),
        ]
        for kind in kinds {
            let renderer = try #require(RenderPlanner.renderer(for: kind, context: context))
            let plan = RenderPlan(
                outputWidth: 64, outputHeight: 64, frameRate: 30, videoLayers: [], overlays: [renderer])
            _ = try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 0)
        }
    }
}
