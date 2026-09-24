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
        // Resolve the object's own setting the way `RenderPlanner` does, so a params value of
        // `.kph` reaches the renderer and an `.automatic` one falls through to the same default
        // every object used to assert.
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()), frame: frame,
            opacity: 1, sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache(),
            speedUnit: UnitResolver().speed(kind.speedUnit))
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

    @Test func deltaBarGrowsEitherSideOfZero() throws {
        // −1 s at 2 s (ahead), +1 s at 8 s (behind), on a ±2 s bar with no caption.
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .lapDelta, name: "d", unit: .seconds, times: [0, 2, 8, 10], values: [-1, -1, 1, 1]),
                Channel(role: .speedDelta, name: "s", unit: .metersPerSecond, times: [0, 10], values: [10, 10]),
            ])
        let green = RGBAColor(red: 0, green: 1, blue: 0)
        let red = RGBAColor(red: 1, green: 0, blue: 0)
        let params = BarParams(
            channel: "lapDelta", minValue: -2, maxValue: 2, trackColor: .black,
            zones: [GaugeZone(from: -2, to: 0, color: green), GaugeZone(from: 0, to: nil, color: red)],
            showValue: false, cornerRadius: 0, fillFromZero: true)
        let frame = UnitRect(x: 0, y: 0.4, width: 1, height: 0.2)
        let ahead = try render(.bar(params), frame: frame, time: 2, session: session)
        let behind = try render(.bar(params), frame: frame, time: 8, session: session)
        // Ahead: green between 25 % and 50 % of the width, nothing right of the centre.
        let aheadFill = PixelBuffers.pixel(in: ahead, x: 150, y: 200)
        #expect(aheadFill.g > 200 && aheadFill.r < 60, "green left of centre: \(aheadFill)")
        #expect(PixelBuffers.pixel(in: ahead, x: 50, y: 200).g < 60, "empty beyond the value")
        #expect(PixelBuffers.pixel(in: ahead, x: 300, y: 200).r < 60, "empty right of centre")
        // Behind: red between 50 % and 75 %.
        let behindFill = PixelBuffers.pixel(in: behind, x: 250, y: 200)
        #expect(behindFill.r > 200 && behindFill.g < 60, "red right of centre: \(behindFill)")
        #expect(PixelBuffers.pixel(in: behind, x: 100, y: 200).g < 60, "empty left of centre")
        #expect(PixelBuffers.pixel(in: behind, x: 350, y: 200).r < 60, "empty beyond the value")
        // A speed difference is shown in the object's speed unit like a speed.
        let sample = TelemetrySampler(session: session).sample(at: 5)
        let units = DisplayUnits([
            "speedDelta": DisplayUnits.Conversion(from: .metersPerSecond, to: .milesPerHour, label: "mph")
        ])
        let mph = ChannelValue.display("speedDelta", in: sample, units: units)
        #expect(abs((mph ?? 0) - 22.369) < 0.01)
        #expect(ChannelValue.isSpeed("speedDelta") && !ChannelValue.isSpeed("lapDelta"))
        // Without the option the same bar fills from its minimum.
        var plain = params
        plain.fillFromZero = false
        let fromMinimum = try render(.bar(plain), frame: frame, time: 2, session: session)
        #expect(PixelBuffers.pixel(in: fromMinimum, x: 50, y: 200).g > 200)
    }

    @Test func steeringWheelMarkerTurnsWithTheAngle() throws {
        // 0° until 2 s, then 90° to the right from 8 s.
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .aux("steer"), name: "steer", unit: .degrees, times: [0, 2, 8, 10], values: [0, 0, 90, 90])
            ])
        let yellow = RGBAColor(red: 1, green: 1, blue: 0)
        let params = SteeringWheelParams(
            channel: "aux:steer", rimColor: RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5),
            edgeColor: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0), rimWidth: 0.2, markerColor: yellow,
            markerWidth: 0.1)
        let frame = UnitRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)  // rim between 128 and 160 px from (200, 200)
        let straight = try render(.steeringWheel(params), frame: frame, time: 1, session: session)
        try GoldenImage.assertMatches(straight, named: "steering-wheel-straight")
        let top = PixelBuffers.pixel(in: straight, x: 200, y: 56)
        #expect(top.r > 200 && top.g > 200 && top.b < 80, "marker at twelve o'clock: \(top)")
        // The rim is drawn half transparent over the black frame.
        let rim = PixelBuffers.pixel(in: straight, x: 56, y: 200)
        #expect(rim.b > 90 && rim.b < 170 && rim.r < 40, "see-through rim: \(rim)")
        let turned = try render(.steeringWheel(params), frame: frame, time: 9, session: session)
        let right = PixelBuffers.pixel(in: turned, x: 344, y: 200)
        #expect(right.r > 200 && right.g > 200 && right.b < 80, "marker at three o'clock: \(right)")
        #expect(PixelBuffers.pixel(in: turned, x: 200, y: 56).r < 60, "no marker left at the top")
        // Inverted, the same angle turns the marker to nine o'clock.
        var inverted = params
        inverted.invert = true
        let left = PixelBuffers.pixel(
            in: try render(.steeringWheel(inverted), frame: frame, time: 9, session: session), x: 56, y: 200)
        #expect(left.r > 200 && left.g > 200)
    }

    @Test func gradientShapeFadesAndTheOverlayLayerCanFade() throws {
        let shape = ShapeParams(
            shape: .rectangle, fillColor: RGBAColor(red: 1, green: 1, blue: 1, alpha: 0),
            gradientEndColor: RGBAColor(red: 1, green: 1, blue: 1, alpha: 1))
        let image = try render(.shape(shape), frame: .full, time: 0)
        let top = PixelBuffers.pixel(in: image, x: 200, y: 8)
        let middle = PixelBuffers.pixel(in: image, x: 200, y: 200)
        let bottom = PixelBuffers.pixel(in: image, x: 200, y: 392)
        #expect(top.r < 20 && middle.r > 100 && middle.r < 160 && bottom.r > 235, "\(top.r) \(middle.r) \(bottom.r)")
        // Half overlay opacity halves a solid white overlay over black.
        let solid = ShapeParams(shape: .rectangle, fillColor: .white)
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID()), frame: .full, opacity: 1, sampler: nil, sync: .identity,
            cache: RenderCache())
        let renderer = try #require(RenderPlanner.renderer(for: .shape(solid), context: context, image: nil))
        let plan = RenderPlan(
            outputWidth: 64, outputHeight: 64, frameRate: 30, videoLayers: [], overlays: [renderer],
            overlayOpacity: 0.5)
        let faded = PixelBuffers.pixel(
            in: try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 0), x: 32, y: 32)
        #expect(faded.r > 110 && faded.r < 145, "half opacity: \(faded.r)")
        #expect(plan.overlayOnly(background: .black).overlayOpacity == 0.5)
    }

    @Test func graphs() throws {
        // These are graphs as they drew before #156, pinned to the right edge as a project saved
        // then is: they must match the images made before the playhead could move.
        let frame = UnitRect(x: 0.05, y: 0.2, width: 0.9, height: 0.6)
        var time = GraphParams(series: [GraphSeries(channel: "speed")], axis: .time, window: 5, label: "SPEED")
        time.pinPlayheadToTheRightEdge()
        try GoldenImage.assertMatches(try render(.graph(time), frame: frame, time: 7), named: "graph-time-7s")
        var twoSeries = GraphParams(
            series: [
                GraphSeries(channel: "lateralG"), GraphSeries(channel: "longitudinalG", color: .white, lineWidth: 2),
            ],
            axis: .time, window: 10, label: "LAT / LONG G", fillUnderLine: false)
        twoSeries.pinPlayheadToTheRightEdge()
        try GoldenImage.assertMatches(
            try render(.graph(twoSeries), frame: frame, time: 9), named: "graph-two-series-9s")
        let lap = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap, label: "LAP vs BEST")
        try GoldenImage.assertMatches(try render(.graph(lap), frame: frame, time: 6), named: "graph-lap-ghost-6s")
        var distance = GraphParams(
            series: [GraphSeries(channel: "lateralG")], axis: .distance, window: 150, minValue: -1, maxValue: 1,
            label: "LAT G", fillUnderLine: false)
        distance.pinPlayheadToTheRightEdge()
        try GoldenImage.assertMatches(
            try render(.graph(distance), frame: frame, time: 8), named: "graph-distance-8s")
    }

    @Test func graphsShowWhatIsComingAndOneChannelAgainstAnother() throws {
        let frame = UnitRect(x: 0.05, y: 0.2, width: 0.9, height: 0.6)
        // New graphs: the current moment in the middle, marked by a line, the future to its right.
        let time = GraphParams(series: [GraphSeries(channel: "speed")], axis: .time, window: 5, label: "SPEED")
        try GoldenImage.assertMatches(try render(.graph(time), frame: frame, time: 7), named: "graph-time-middle-7s")
        let distance = GraphParams(
            series: [GraphSeries(channel: "lateralG")], axis: .distance, window: 150, minValue: -1, maxValue: 1,
            label: "LAT G", fillUnderLine: false)
        try GoldenImage.assertMatches(
            try render(.graph(distance), frame: frame, time: 8), named: "graph-distance-middle-8s")
        // A G-G diagram: longitudinal against lateral G, three seconds of fading trail.
        let gg = GraphParams(
            series: [GraphSeries(channel: "longitudinalG")], axis: .channel, window: 3, label: "G-G",
            xChannel: "lateralG")
        try GoldenImage.assertMatches(
            try render(.graph(gg), frame: UnitRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8), time: 8),
            named: "graph-gg-8s")
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
    func context(
        session: TelemetrySession = SyntheticSession.withDistance, speedUnit: SpeedDisplayUnit = UnitResolver.lastResort
    ) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: session),
            sync: .identity, cache: RenderCache(), speedUnit: speedUnit)
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

    @Test func aGraphShowsWhatIsComingRightOfThePlayhead() throws {
        // A 10 s window with now in the middle: 5 s either side, the cursor at now, not at the end.
        let params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .time, window: 10)
        let layout = GraphRenderer(context: context(), params: params).layout(at: 12, pointBudget: 21)
        let trace = try #require(layout.traces.first)
        #expect(layout.playheadX == 5)
        #expect(abs((trace.points.last?.x ?? 0) - 10) < 1e-6)
        #expect(abs((trace.cursor?.x ?? 0) - 5) < 1e-6)
        // At the right edge it draws as it always did: the last point is now.
        var edge = params
        edge.pinPlayheadToTheRightEdge()
        let old = try #require(
            GraphRenderer(context: context(), params: edge).layout(at: 12, pointBudget: 21).traces.first)
        #expect(old.cursor == old.points.last)
    }

    @Test func aChannelAxisPlotsOneChannelAgainstAnother() throws {
        let params = GraphParams(
            series: [GraphSeries(channel: "longitudinalG")], axis: .channel, window: 2, xChannel: "lateralG",
            xMinValue: -2, xMaxValue: 2)
        let session = SyntheticSession.withDistance
        let layout = GraphRenderer(context: context(), params: params).layout(at: 8, pointBudget: 9)
        let trace = try #require(layout.traces.first)
        #expect(trace.fades)
        #expect(layout.xRange == -2...2)
        #expect(layout.playheadX == nil)
        // The trail ends at now, at (lateral, longitudinal) as the session has them.
        let lateral = try #require(session[.lateralG]?.value(at: 8))
        let longitudinal = try #require(session[.longitudinalG]?.value(at: 8))
        #expect(abs((trace.cursor?.x ?? 0) - lateral) < 1e-6)
        #expect(abs((trace.cursor?.y ?? 0) - longitudinal) < 1e-6)
        // An X-Y graph reads the x channel's value too, so its unit applies to it.
        #expect(DisplayObjectKind.graph(params).displayChannels == ["longitudinalG", "lateralG"])
    }

    @Test func graphWithoutDistanceFallsBackToTime() throws {
        let params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        let layout = GraphRenderer(context: context(session: SyntheticSession.session), params: params)
            .layout(at: 6, pointBudget: 10)
        #expect(layout.traces.count == 1)
        #expect(abs((layout.traces[0].points.last?.x ?? 0) - 2) < 1e-6)
    }

    @Test func timerNewModes() throws {
        let ctx = context()
        let sample = ctx.sample(at: 6)
        let delta = TimerRenderer(context: ctx, params: TimerParams(mode: .deltaToBest)).readout(
            sample: sample, projectTime: 6)
        // Constant speed around the square: no time lost or gained versus the best lap.
        #expect(delta.text == "0.00")
        // At the best lap's pace the lap projects to the best lap's own time, neither ahead nor behind.
        let best = try #require(LapDeltas.sessionBest(in: SyntheticSession.withDistance)?.duration)
        let projected = TimerRenderer(context: ctx, params: TimerParams(mode: .projectedLap))
        #expect(projected.readout(sample: sample, projectTime: 6).text == TimeParsing.lapTimeString(best, decimals: 2))
        #expect(projected.readout(sample: sample, projectTime: 6).color == nil)
        #expect(projected.labelText(sample: sample) == "PROJECTED 1")
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
