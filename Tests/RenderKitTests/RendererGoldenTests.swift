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
                channel(
                    .heading, .degrees, { (($0 / 10 * 4).truncatingRemainder(dividingBy: 4)).rounded(.down) * 90 },
                    step: true),
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
            TimerRenderer(context: context, params: TimerParams(mode: .currentLap)).readout(
                sample: sample, projectTime: 6
            ).text == "0:02.00")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .lastLap)).readout(
                sample: sample, projectTime: 6
            ).text == "0:04.00")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .bestLap)).labelText(sample: sample) == "BEST 0")
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .currentLap)).labelText(sample: sample) == "LAP 1"
        )
        #expect(
            TimerRenderer(context: context, params: TimerParams(mode: .session)).readout(
                sample: sample, projectTime: 6
            ).text == "0:06.00")
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

@Suite("Track map extras")
struct TrackMapExtrasTests {
    static let size = CGSize(width: 400, height: 400)

    func context(sync: SyncSettings = .identity) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()),
            frame: UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), opacity: 1,
            sampler: TelemetrySampler(session: SyntheticSession.session), sync: sync, cache: RenderCache())
    }

    func render(_ renderer: any OverlayDrawing, time: Double) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: Int(Self.size.width), outputHeight: Int(Self.size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    /// A synthetic "map": green land with a blue diagonal river, mapped so the square track sits
    /// in its middle.
    static func syntheticBackground(request: MapBackgroundRequest) throws -> MapBackground {
        let width = 256
        let height = 256
        let cg = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffers.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        cg.setFillColor(PixelBuffers.color(red: 0.55, green: 0.75, blue: 0.45))
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cg.setStrokeColor(PixelBuffers.color(red: 0.3, green: 0.5, blue: 0.9))
        cg.setLineWidth(18)
        cg.move(to: CGPoint(x: 0, y: 0))
        cg.addLine(to: CGPoint(x: width, y: height))
        cg.strokePath()
        let pixelsPerDegreeLatitude = Double(height) / (request.maxLatitude - request.minLatitude)
        let pixelsPerDegreeLongitude = Double(width) / (request.maxLongitude - request.minLongitude)
        // A dark band just north of the track (45.0009…45.0012°) so orientation is visible.
        func row(_ latitude: Double) -> Double {
            Double(height) / 2 + (latitude - request.centerLatitude) * pixelsPerDegreeLatitude
        }
        cg.setFillColor(PixelBuffers.color(red: 0.2, green: 0.2, blue: 0.2))
        cg.fill(CGRect(x: 0, y: row(45.00095), width: Double(width), height: row(45.0012) - row(45.00095)))
        let image = try #require(cg.makeImage())
        return MapBackground(
            request: request, image: image, centerPoint: CGPoint(x: width / 2, y: height / 2),
            pixelsPerDegreeLongitude: pixelsPerDegreeLongitude, pixelsPerDegreeLatitude: pixelsPerDegreeLatitude)
    }

    @Test func twoVehiclesShowTwoDots() throws {
        // The second vehicle is the same session two seconds behind, so its dot sits elsewhere.
        let second = SecondVehicle(
            sampler: TelemetrySampler(session: SyntheticSession.session), sync: SyncSettings(startPositionInInput: -2))
        let params = TrackMapParams(
            backgroundColor: .faceDark, secondDotColor: RGBAColor(red: 0.25, green: 0.6, blue: 1))
        let frame = try render(TrackMapRenderer(context: context(), params: params, second: second), time: 2.5)
        try GoldenImage.assertMatches(frame, named: "trackmap-two-vehicles-2.5s")
        var orange = 0
        var blue = 0
        for y in stride(from: 0, to: 400, by: 2) {
            for x in stride(from: 0, to: 400, by: 2) {
                let p = PixelBuffers.pixel(in: frame, x: x, y: y)
                if p.r > 200, p.g > 100, p.g < 200, p.b < 80 { orange += 1 }
                if p.b > 200, p.r < 100, p.g > 100 { blue += 1 }
            }
        }
        #expect(orange > 20 && blue > 20, "orange \(orange) blue \(blue)")
    }

    @Test func mapBackgroundIsDrawnBehindTheTrace() throws {
        let request = try #require(MapBackgroundRequest(session: SyntheticSession.session, style: .standard))
        let background = try Self.syntheticBackground(request: request)
        let params = TrackMapParams(background: .standard)
        let frame = try render(TrackMapRenderer(context: context(), params: params, background: background), time: 1)
        try GoldenImage.assertMatches(frame, named: "trackmap-map-background-1s")
        // Land green fills a corner inside the object; the north band is at the top (north up).
        let corner = PixelBuffers.pixel(in: frame, x: 60, y: 200)
        #expect(corner.g > corner.r && corner.g > corner.b, "corner \(corner)")
        let top = PixelBuffers.pixel(in: frame, x: 200, y: 26)
        #expect(top.r < 80 && top.g < 80, "top \(top)")
    }

    @Test func rotatedMapKeepsNorthBandOnTheLeft() throws {
        let request = try #require(MapBackgroundRequest(session: SyntheticSession.session, style: .satellite))
        let background = try Self.syntheticBackground(request: request)
        let params = TrackMapParams(rotation: 90, background: .satellite)
        let frame = try render(TrackMapRenderer(context: context(), params: params, background: background), time: 1)
        // Rotating the map 90° clockwise puts north on the right.
        let right = PixelBuffers.pixel(in: frame, x: 374, y: 200)
        #expect(right.r < 80 && right.g < 80, "right \(right)")
        let left = PixelBuffers.pixel(in: frame, x: 26, y: 200)
        #expect(left.g > 100, "left \(left)")
    }

    @Test func requestsRoundAndPad() throws {
        let request = try #require(MapBackgroundRequest(session: SyntheticSession.session, style: .hybrid))
        #expect(request.minLatitude < 45 && request.maxLatitude > 45.0009)
        #expect(request.minLongitude < -122 && request.maxLongitude > -122 + 0.0009)
        #expect(MapBackgroundRequest(session: SyntheticSession.session, style: .none) == nil)
        let project = Project(
            inputs: [],
            displayObjects: [
                DisplayObject(
                    label: "m", inputID: nil, frame: .full, kind: .trackMap(TrackMapParams(background: .standard)))
            ])
        #expect(RenderPlanner.mapBackgroundRequests(for: project, sessions: [:]).isEmpty)
    }
}

@Suite("Indicator and timing panel")
struct IndicatorPanelTests {
    static let size = CGSize(width: 400, height: 400)

    func context(frame: UnitRect, sync: SyncSettings = .identity) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000003") ?? UUID()), frame: frame,
            opacity: 1, sampler: TelemetrySampler(session: SyntheticSession.session), sync: sync, cache: RenderCache())
    }

    func render(_ kind: DisplayObjectKind, frame: UnitRect, time: Double) throws -> CVPixelBuffer {
        let renderer = try #require(RenderPlanner.renderer(for: kind, context: context(frame: frame)))
        let plan = RenderPlan(
            outputWidth: Int(Self.size.width), outputHeight: Int(Self.size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    @Test func absLightIsDimBelowAndAmberAboveTheThreshold() throws {
        // The synthetic speed ramps 10…35 m/s; "on" above 30 m/s means from 8 s.
        let params = IndicatorParams(channel: "speed", condition: .atLeast, threshold: 30, glyph: .abs, holdSeconds: 0)
        let frame = UnitRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let off = try render(.indicator(params), frame: frame, time: 2)
        let on = try render(.indicator(params), frame: frame, time: 9)
        try GoldenImage.assertMatches(off, named: "indicator-abs-off")
        try GoldenImage.assertMatches(on, named: "indicator-abs-on")
        func amberPixels(_ buffer: CVPixelBuffer) -> Int {
            var count = 0
            for y in stride(from: 0, to: 400, by: 3) {
                for x in stride(from: 0, to: 400, by: 3) {
                    let p = PixelBuffers.pixel(in: buffer, x: x, y: y)
                    if p.r > 200, p.g > 120, p.g < 210, p.b < 80 { count += 1 }
                }
            }
            return count
        }
        #expect(amberPixels(off) == 0)
        #expect(amberPixels(on) > 30)
    }

    @Test func holdKeepsTheLightOnAfterTheConditionEnds() throws {
        // Speed is above 30 from 8 s; with the condition "at most 12" (true only until 0.8 s),
        // a 2 s hold keeps it lit at 2 s but not at 4 s.
        var params = IndicatorParams(channel: "speed", condition: .atMost, threshold: 12, glyph: .light, label: "")
        params.holdSeconds = 2
        let renderer = IndicatorRenderer(context: context(frame: .full), params: params)
        #expect(renderer.isOn(at: 0.5))
        #expect(renderer.isOn(at: 2))
        #expect(!renderer.isOn(at: 4))
        params.holdSeconds = 0
        #expect(!IndicatorRenderer(context: context(frame: .full), params: params).isOn(at: 2))
    }

    @Test func timingPanelShowsLapsAndDeltas() throws {
        let frame = UnitRect(x: 0.02, y: 0.4, width: 0.96, height: 0.18)
        let panel = try render(.lapPanel(LapPanelParams()), frame: frame, time: 6)
        try GoldenImage.assertMatches(panel, named: "lap-panel-6s")
        // Something was drawn across the strip: text/scales are white-ish.
        var bright = 0
        for x in stride(from: 10, to: 390, by: 4) {
            for y in stride(from: 165, to: 230, by: 4) {
                let p = PixelBuffers.pixel(in: panel, x: x, y: y)
                if p.r > 180, p.g > 180, p.b > 180 { bright += 1 }
            }
        }
        #expect(bright > 40, "\(bright) bright pixels")
    }

    @Test func textDataZonesRecolourTheValue() throws {
        var params = TextDataParams(channel: "rpm", label: "RPM")
        params.zones = [GaugeZone(from: 4000, to: nil, color: .red)]
        let frame = UnitRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2)
        let cool = try render(.textData(params), frame: frame, time: 1)  // 2500 rpm
        let hot = try render(.textData(params), frame: frame, time: 8)  // 6000 rpm
        func redPixels(_ buffer: CVPixelBuffer) -> Int {
            var count = 0
            for y in stride(from: 160, to: 240, by: 2) {
                for x in stride(from: 20, to: 380, by: 2) {
                    let p = PixelBuffers.pixel(in: buffer, x: x, y: y)
                    if p.r > 180, p.g < 90, p.b < 90 { count += 1 }
                }
            }
            return count
        }
        #expect(redPixels(cool) == 0)
        #expect(redPixels(hot) > 20)
    }
}
