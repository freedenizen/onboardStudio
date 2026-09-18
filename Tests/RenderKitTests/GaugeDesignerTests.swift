import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

extension SyntheticSession {
    /// The synthetic session plus a GPS-derived distance channel and a recorded start time.
    static let withDistance: TelemetrySession = {
        var session = SyntheticSession.session
        if let lat = session[.latitude], let lon = session[.longitude],
            let distance = DerivedChannels.distance(latitude: lat, longitude: lon)
        {
            session.add(distance)
        }
        session.info.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return session
    }()
}

/// Goldens for the M7 designer options and objects. Each configuration exercises a different
/// code path; the images are reviewed by eye when (re)generated with `UPDATE_GOLDENS=1`.
@Suite("Gauge designer goldens")
struct GaugeDesignerGoldenTests {
    let size = CGSize(width: 400, height: 400)

    func render(
        _ kind: DisplayObjectKind, frame: UnitRect = UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
        time: Double, session: TelemetrySession = SyntheticSession.withDistance, image: LoadedImage? = nil
    ) throws -> CVPixelBuffer {
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()), frame: frame,
            opacity: 1, sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache())
        let renderer = try #require(RenderPlanner.renderer(for: kind, context: context, image: image))
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    @Test func arcStyleCounterClockwiseWithGradientZones() throws {
        var params = GaugeParams.speedometer(unit: .kph, max: 120)
        params.style = .arc
        params.counterClockwise = true
        params.zones = [GaugeZone(from: 60, to: 90, color: .accent), GaugeZone(from: 90, to: nil, color: .red)]
        params.zoneTargets = ZoneTargets(face: true, marks: true, needle: true, gradient: true)
        try GoldenImage.assertMatches(try render(.gauge(params), time: 7), named: "gauge-arc-ccw-gradient-7s")
    }

    @Test func dualNeedleFullSweepUntaperedNoFace() throws {
        var params = GaugeParams.tachometer(max: 8000, redline: 6500)
        params.style = .dualNeedle
        params.secondChannel = "speed"
        params.sweep = 360
        params.showFace = false
        params.showValue = false
        params.needle = NeedleStyle(length: 0.7, tailLength: 0.3, width: 0.12, hubRadius: 0.15, tapered: false)
        params.ticks.labelRadius = 0.72
        params.ticks.majorLength = 0.08
        params.ticks.showMinor = false
        try GoldenImage.assertMatches(try render(.gauge(params), time: 6), named: "gauge-dual-360-6s")
    }

    @Test func crowdedLabelsAreDecluttered() throws {
        var params = GaugeParams(
            channel: "rpm", title: "RPM", minValue: 0, maxValue: 8000, unitLabel: "rpm", majorTick: 250, minorTick: 125)
        params.ticks.labelDecimals = 0
        try GoldenImage.assertMatches(try render(.gauge(params), time: 8), named: "gauge-declutter-8s")
        params.ticks.declutter = false
        let cluttered = try render(.gauge(params), time: 8)
        // Without decluttering far more label ink lands on the face.
        #expect(
            try GoldenImage.inkCount(cluttered) > GoldenImage.inkCount(try render(.gauge(params).declutterOn, time: 8)))
    }

    @Test func faceImageAndSmoothedNeedle() throws {
        let fixture = GoldenImage.goldensDirectory.deletingLastPathComponent().appending(path: "arrow.png")
        let image = try LoadedImage.load(fixture)
        var params = GaugeParams.speedometer(max: 120)
        params.faceImageInputID = InputID()
        params.needle.smoothingSeconds = 1
        params.ticks.showLabels = false
        try GoldenImage.assertMatches(
            try render(.gauge(params), time: 5, image: image), named: "gauge-face-image-5s")
    }

    @Test func bars() throws {
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.12)
        var horizontal = BarParams(channel: "rpm", label: "RPM", minValue: 0, maxValue: 8000, unitLabel: "rpm")
        horizontal.segments = 16
        horizontal.zones = [GaugeZone(from: 6000, to: nil, color: .red)]
        try GoldenImage.assertMatches(try render(.bar(horizontal), frame: frame, time: 8), named: "bar-segments-8s")
        var vertical = BarParams(channel: "speed", label: "SPD", minValue: 0, maxValue: 130, orientation: .vertical)
        vertical.speedUnit = .kph
        vertical.zoneColorsFill = false
        vertical.zones = [GaugeZone(from: 100, to: nil, color: .red)]
        try GoldenImage.assertMatches(
            try render(.bar(vertical), frame: UnitRect(x: 0.35, y: 0.05, width: 0.3, height: 0.9), time: 5),
            named: "bar-vertical-5s")
    }

    @Test func graphs() throws {
        let frame = UnitRect(x: 0.05, y: 0.2, width: 0.9, height: 0.6)
        let time = GraphParams(series: [GraphSeries(channel: "speed")], axis: .time, window: 5, label: "SPEED")
        try GoldenImage.assertMatches(try render(.graph(time), frame: frame, time: 7), named: "graph-time-7s")
        let twoSeries = GraphParams(
            series: [
                GraphSeries(channel: "lateralG"), GraphSeries(channel: "longitudinalG", color: .white, lineWidth: 2),
            ],
            axis: .time, window: 10, label: "LAT / LONG G", fillUnderLine: false)
        try GoldenImage.assertMatches(
            try render(.graph(twoSeries), frame: frame, time: 9), named: "graph-two-series-9s")
        let lap = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap, label: "LAP vs BEST")
        try GoldenImage.assertMatches(try render(.graph(lap), frame: frame, time: 6), named: "graph-lap-ghost-6s")
        let distance = GraphParams(
            series: [GraphSeries(channel: "lateralG")], axis: .distance, window: 150, minValue: -1, maxValue: 1,
            label: "LAT G", fillUnderLine: false)
        try GoldenImage.assertMatches(
            try render(.graph(distance), frame: frame, time: 8), named: "graph-distance-8s")
    }

    @Test func gearAndLapCounter() throws {
        try GoldenImage.assertMatches(
            try render(.gear(GearParams()), frame: UnitRect(x: 0.3, y: 0.15, width: 0.4, height: 0.7), time: 7),
            named: "gear-7s")
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        try GoldenImage.assertMatches(
            try render(.lapCounter(LapCounterParams(showTotal: true, numberOffset: 1)), frame: frame, time: 6),
            named: "lapcounter-6s")
    }

    @Test func timerDeltaAndVideoTime() throws {
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        try GoldenImage.assertMatches(
            try render(.timer(TimerParams(mode: .deltaToBest, decimals: 3)), frame: frame, time: 6),
            named: "timer-delta-6s")
        try GoldenImage.assertMatches(
            try render(
                .timer(TimerParams(mode: .projectTime, showLapNumber: false, decimals: 1)), frame: frame, time: 6),
            named: "timer-video-6s")
    }

    @Test func textDataFormatting() throws {
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        let params = TextDataParams(
            channel: "rpm", label: "RPM", decimals: 1, alignment: .trailing, multiplier: 10, prefix: "≈",
            thousandsSeparator: true, showPlusSign: true, minimumIntegerDigits: 6, fontScale: 0.45)
        try GoldenImage.assertMatches(try render(.textData(params), frame: frame, time: 4), named: "textdata-format-4s")
    }
}

extension DisplayObjectKind {
    fileprivate var declutterOn: DisplayObjectKind {
        guard case .gauge(var p) = self else { return self }
        p.ticks.declutter = true
        return .gauge(p)
    }
}

extension GoldenImage {
    /// Number of near-white pixels: a crude measure of how much text and tick ink was drawn.
    static func inkCount(_ buffer: CVPixelBuffer) throws -> Int {
        let cgImage = try #require(GoldenImage.image(from: buffer))
        let bytes = try #require(rgba(cgImage))
        var count = 0
        for index in stride(from: 0, to: bytes.count, by: 4)
        where bytes[index] > 200 && bytes[index + 1] > 200 && bytes[index + 2] > 200 {
            count += 1
        }
        return count
    }
}

@Suite("Designer behaviour")
struct DesignerBehaviourTests {
    func context(session: TelemetrySession = SyntheticSession.withDistance) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: session),
            sync: .identity, cache: RenderCache())
    }

    @Test func counterClockwiseReversesTheSweep() {
        var params = GaugeParams.speedometer(max: 100)
        params.counterClockwise = true
        let gauge = GaugeRenderer(context: context(), params: params)
        #expect(abs((gauge.angle(for: 0) - gauge.angle(for: 100)) - 270 * Double.pi / 180) < 1e-9)
        #expect(abs(gauge.angle(for: 50) - (-Double.pi / 2)) < 1e-9)
    }

    @Test func zoneColoursStepOrBlend() {
        var params = GaugeParams.tachometer(max: 8000, redline: 6000)
        params.zoneTargets.needle = true
        let stepped = GaugeRenderer(context: context(), params: params)
        #expect(stepped.zoneColor(at: 5999) == nil)
        #expect(stepped.zoneColor(at: 6000) == .red)
        #expect(stepped.needleColor(for: 3000) == params.needleColor)
        #expect(stepped.needleColor(for: 7000) == .red)
        params.zoneTargets.gradient = true
        let blended = GaugeRenderer(context: context(), params: params)
        // 8% of an 8000 scale = 640 before the threshold the blend starts.
        #expect(blended.zoneColor(at: 5000) == nil)
        let partial = blended.zoneColor(at: 5680)
        #expect(partial != nil && partial != .red && (partial?.alpha ?? 0) > 0.4 && (partial?.alpha ?? 1) < 0.6)
        #expect(blended.zoneColor(at: 6500) == .red)
    }

    @Test func needleSmoothingAveragesTheTrailingWindow() {
        var params = GaugeParams.tachometer(max: 8000)
        let raw = GaugeRenderer(context: context(), params: params).displayValue(of: "rpm", at: 6)
        params.needle.smoothingSeconds = 2
        let smoothed = GaugeRenderer(context: context(), params: params).displayValue(of: "rpm", at: 6)
        // rpm ramps 500/s, so the 2 s trailing mean lags by 1 s = 500 rpm.
        #expect(abs((raw ?? 0) - 5000) < 1e-6)
        #expect(abs((smoothed ?? 0) - 4500) < 1e-6)
    }

    @Test func graphDistanceAxisMapsMetres() throws {
        let params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .distance, window: 100)
        let layout = GraphRenderer(context: context(), params: params).layout(at: 5, pointBudget: 50)
        #expect(layout.xRange == 0...100)
        let points = try #require(layout.traces.first?.points)
        #expect(points.count == 50)
        #expect(abs(points[0].x) < 1)
        #expect(abs((points.last?.x ?? 0) - 100) < 1)
        // x is distance, so it must be monotonic even though it was sampled in time.
        for pair in zip(points, points.dropFirst()) { #expect(pair.1.x >= pair.0.x) }
    }

    @Test func graphLapAxisHasGhostAndLiveTraces() throws {
        let params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        let layout = GraphRenderer(context: context(), params: params).layout(at: 6, pointBudget: 40)
        #expect(layout.traces.count == 2)
        let ghost = try #require(layout.traces.first { $0.isGhost })
        let live = try #require(layout.traces.first { !$0.isGhost })
        // Lap 0 (0–4 s) is the best lap; lap 1 started at 4 s, so the live trace covers 2 s of travel.
        #expect(abs(ghost.points[0].x) < 1e-6)
        #expect((live.points.last?.x ?? 0) > 0)
        #expect(layout.xRange.upperBound >= (ghost.points.last?.x ?? 0))
        #expect(ghost.color == params.ghostColor)
    }

    @Test func graphWithoutDistanceFallsBackToTime() throws {
        let params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        let layout = GraphRenderer(context: context(session: SyntheticSession.session), params: params)
            .layout(at: 6, pointBudget: 10)
        #expect(layout.traces.count == 1)
        #expect(abs((layout.traces[0].points.last?.x ?? 0) - 2) < 1e-6)
    }

    @Test func timerNewModes() {
        let ctx = context()
        let sample = ctx.sample(at: 6)
        let delta = TimerRenderer(context: ctx, params: TimerParams(mode: .deltaToBest)).readout(
            sample: sample, projectTime: 6)
        // Constant speed around the square: no time lost or gained versus the best lap.
        #expect(delta.text == "0.00")
        let video = TimerRenderer(context: ctx, params: TimerParams(mode: .projectTime, decimals: 1)).readout(
            sample: sample, projectTime: 65.26)
        #expect(video.text == "1:05.3")
        let clock = TimerRenderer(context: ctx, params: TimerParams(mode: .timeOfDay))
        let expected = Date(timeIntervalSince1970: 1_700_000_006).formatted(TimerRenderer.clockFormat)
        #expect(clock.readout(sample: sample, projectTime: 6).text == expected)
        #expect(clock.labelText(sample: sample) == "CLOCK 1")
        let noClock = TimerRenderer(
            context: context(session: SyntheticSession.session), params: TimerParams(mode: .timeOfDay))
        #expect(noClock.readout(sample: sample, projectTime: 6).text == "--:--:--")
    }

    @Test func textDataValueFormatting() {
        let ctx = context()
        func text(_ params: TextDataParams, _ value: Double?) -> String {
            TextDataRenderer(context: ctx, params: params).valueText(for: value)
        }
        #expect(text(TextDataParams(channel: "rpm", label: ""), 1234.56) == "1235")
        #expect(
            text(TextDataParams(channel: "rpm", label: "", decimals: 2, thousandsSeparator: true), 1234.567)
                == "1,234.57")
        #expect(text(TextDataParams(channel: "rpm", label: "", showPlusSign: true), 12) == "+12")
        #expect(text(TextDataParams(channel: "rpm", label: "", showPlusSign: true), 0) == "0")
        #expect(text(TextDataParams(channel: "rpm", label: "", minimumIntegerDigits: 4), -7) == "-0007")
        #expect(text(TextDataParams(channel: "rpm", label: "", multiplier: 2, offset: 1, prefix: "#"), 10) == "#21")
        #expect(text(TextDataParams(channel: "rpm", label: "", absoluteValue: true), -3) == "3")
        #expect(text(TextDataParams(channel: "rpm", label: "", decimals: 1), -0.04) == "0.0")
        #expect(text(TextDataParams(channel: "rpm", label: ""), nil) == "--")
    }

    @Test func gearText() {
        let params = GearParams()
        #expect(params.text(for: 3) == "3")
        #expect(params.text(for: 0) == "N")
        #expect(params.text(for: -1) == "R")
        #expect(params.text(for: -99) == "P")
        #expect(params.text(for: nil) == "-")
    }

    @Test func plannerCoversEveryKind() {
        let data = Input(label: "d", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let objects = DisplayObject.templates.map {
            DisplayObject(label: $0.name, inputID: data.id, frame: .full, kind: $0.kind)
        }
        let project = Project(inputs: [data], displayObjects: objects)
        let overlays = RenderPlanner.overlays(for: project, sessions: [data.id: SyntheticSession.withDistance])
        // Scripted objects need the Scripting module's factory; without it they are skipped.
        let scripted = objects.filter { if case .scripted = $0.kind { return true } else { return false } }.count
        #expect(overlays.count == objects.count - scripted && scripted == 1)
        let plan = RenderPlan(outputWidth: 320, outputHeight: 180, frameRate: 30, videoLayers: [], overlays: overlays)
        #expect((try? FrameCompositor(plan: plan).renderFrame(sources: [:], time: 5)) != nil)
    }
}
