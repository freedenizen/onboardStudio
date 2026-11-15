import CoreGraphics
import CoreVideo
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// #561: the lap being driven painted by any channel, on the ramp set in Settings.
@Suite("Track map coloured by a channel (#561)", .gpu)
struct TrackMapChannelTests {
    let size = CGSize(width: 300, height: 300)

    /// `SectorMapSession` with a speed that climbs steadily through every lap, from 10 m/s at the
    /// line to 30 m/s just before it: the west side is the slow start, the south side the fast end.
    /// A slow out-lap before the first lap would stretch the scale if the range came from it.
    static let session: TelemetrySession = {
        let base = SectorMapSession.session
        let times = base[.latitude]?.times ?? []
        let speeds = times.map { time in
            let into = (time * SectorMapSession.speed).truncatingRemainder(dividingBy: SectorMapSession.lapLength)
            return 10 + 20 * into / SectorMapSession.lapLength
        }
        let speed = Channel(role: .speed, name: "v", unit: .metersPerSecond, times: times, values: speeds)
        let channels = [ChannelRole.latitude, .longitude, .distance].compactMap { base[$0] } + [speed]
        return TelemetrySession(info: base.info, channels: channels, laps: base.laps, sectors: base.sectors)
    }()

    func renderer(_ params: TrackMapParams, ramp: ColorRamp = .standard) -> TrackMapRenderer {
        TrackMapRenderer(
            context: ObjectContext(
                objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000561") ?? UUID()),
                frame: UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9), opacity: 1,
                sampler: TelemetrySampler(session: Self.session), sync: .identity, cache: RenderCache(),
                speedUnit: .kph),
            params: params, ramp: ramp)
    }

    func params(channel: String? = "speed", legend: Bool = false) -> TrackMapParams {
        var params = TrackMapParams(backgroundColor: .faceDark)
        params.lineWidth = 6
        params.colorChannel = channel
        params.showChannelLegend = legend
        return params
    }

    // MARK: - The scale

    @Test func theScaleSpansTheSessionsCompleteLaps() throws {
        let scale = try #require(renderer(params()).channelScale)
        // The 2nd and 98th percentiles of a steady 10→30 climb.
        #expect(abs(scale.low - 10.4) < 0.3)
        #expect(abs(scale.high - 29.6) < 0.3)
        #expect(scale.fraction(of: scale.low) == 0)
        #expect(scale.fraction(of: scale.high) == 1)
    }

    @Test func noChannelOrOneTheDataLacksPaintsNothing() {
        #expect(renderer(params(channel: nil)).channelScale == nil)
        #expect(renderer(params(channel: "rpm")).channelScale == nil, "the data has no rpm")
        #expect(renderer(params(channel: nil)).channelLap(atInputTime: 5) == nil)
    }

    @Test func theLapPaintedIsTheOneTheCarIsOn() throws {
        let panel = renderer(params())
        #expect(panel.channelLap(atInputTime: 5)?.number == 1)
        #expect(panel.channelLap(atInputTime: 25)?.number == 2, "a lap is 20 s")
        #expect(panel.channelLap(atInputTime: 1_000) == nil, "after the last lap nothing is painted")
    }

    @Test func theLegendSaysTheChannelAndItsRangeInTheObjectsUnit() throws {
        let panel = renderer(params(legend: true))
        let scale = try #require(panel.channelScale)
        // 10.4 to 29.6 m/s is 37 to 106 kph.
        #expect(panel.legendText(of: scale) == "Speed 37–106 kph")
    }

    @Test func theLegendTakesABandTheCircuitIsFittedAbove() throws {
        let plain = renderer(params()).plotBounds(in: size)
        #expect(plain == CGRect(origin: .zero, size: size), "no legend, the whole object")
        let panel = renderer(params(legend: true))
        let layout = try #require(panel.legendLayout(in: size))
        #expect(panel.plotBounds(in: size).maxY <= layout.top)
        #expect(layout.bar.maxY < size.height)
    }

    // MARK: - The ramp

    @Test func theRampBlendsBetweenItsColoursAndClampsAtTheEnds() {
        let ramp = ColorRamp.standard
        #expect(ramp.color(at: 0) == ramp.stops[0])
        #expect(ramp.color(at: 1) == ramp.stops[3])
        #expect(ramp.color(at: -1) == ramp.stops[0])
        #expect(ramp.color(at: 2) == ramp.stops[3])
        #expect(ramp.color(at: 1.0 / 3) == ramp.stops[1])
        let between = ramp.color(at: 0.5)
        #expect(between.red > ramp.stops[1].red && between.red < ramp.stops[2].red)
    }

    // MARK: - On the frame

    /// The colour at a point on the circuit, metres east and north of its south-west corner.
    func pixel(_ frame: CVPixelBuffer, east: Double, north: Double, panel: TrackMapRenderer) throws -> RGBAColor {
        let projection = try #require(panel.projection)
        let rect = panel.context.rect(in: size)
        let origin = SectorMapSession.origin
        let point = projection.point(
            latitude: origin.latitude + north / 110_540,
            longitude: origin.longitude + east / (111_320 * cos(origin.latitude * .pi / 180)),
            in: panel.plotBounds(in: rect.size))
        let found = PixelBuffers.pixel(in: frame, x: Int(rect.minX + point.x), y: Int(rect.minY + point.y))
        return RGBAColor(
            red: Double(found.r) / 255, green: Double(found.g) / 255, blue: Double(found.b) / 255,
            alpha: Double(found.a) / 255)
    }

    func render(_ panel: TrackMapRenderer, time: Double) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [panel])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    @Test func theSlowStartIsBlueAndTheFastEndRed() throws {
        let panel = renderer(params())
        let frame = try render(panel, time: 25)
        let slow = try pixel(frame, east: 0, north: 50, panel: panel)
        let fast = try pixel(frame, east: 50, north: 0, panel: panel)
        #expect(slow.blue > 0.7 && slow.red < 0.4, "the west side, where the lap is slowest: \(slow)")
        #expect(fast.red > 0.7 && fast.blue < 0.4, "the south side, where it is fastest: \(fast)")
    }

    @Test func aRampFromSettingsRepaintsTheLap() throws {
        let ramp = ColorRamp(stops: [RGBAColor(red: 0, green: 0, blue: 0), RGBAColor(red: 1, green: 1, blue: 1)])
        let panel = renderer(params(), ramp: ramp)
        let frame = try render(panel, time: 25)
        let slow = try pixel(frame, east: 0, north: 50, panel: panel)
        #expect(slow.red < 0.35 && slow.blue < 0.35, "dark where the lap is slow: \(slow)")
    }

    @Test func withoutAChannelTheLineKeepsItsColour() throws {
        let panel = renderer(params(channel: nil))
        let frame = try render(panel, time: 25)
        let line = try pixel(frame, east: 0, north: 50, panel: panel)
        #expect(line.red > 0.9 && line.green > 0.9 && line.blue > 0.9, "the plain white outline: \(line)")
    }

    @Test func channelColouringWithItsLegend() throws {
        try GoldenImage.assertMatches(try render(renderer(params(legend: true)), time: 25), named: "trackmap-channel")
    }
}
