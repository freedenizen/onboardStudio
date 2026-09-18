import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import Scripting
@testable import TelemetryKit

/// A short synthetic session: speed ramps 10→35 m/s over 10 s, rpm 2000→7000, two laps.
enum ScriptSession {
    static let session: TelemetrySession = {
        let times = Array(stride(from: 0.0, through: 10.0, by: 0.1))
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(
                    role: .speed, name: "speed", unit: .metersPerSecond, times: times,
                    values: times.map { 10 + 2.5 * $0 }),
                Channel(role: .rpm, name: "rpm", unit: .rpm, times: times, values: times.map { 2000 + 500 * $0 }),
                Channel(role: .throttle, name: "throttle", unit: .percent, times: times, values: times.map { $0 * 10 }),
            ],
            laps: [
                Lap(number: 1, start: 0, end: 4, isComplete: true),
                Lap(number: 2, start: 4, end: nil, isComplete: false),
            ])
    }()

    static func context(frame: UnitRect = UnitRect(x: 0.1, y: 0.1, width: 0.8, height: 0.5)) -> ObjectContext {
        ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-00000000000A") ?? UUID()), frame: frame,
            opacity: 1, sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache())
    }

    static func render(_ source: String, time: Double, size: CGSize = CGSize(width: 400, height: 200)) throws
        -> (CVPixelBuffer, ScriptedRenderer)
    {
        let renderer = ScriptedRenderer(context: context(), params: ScriptedParams(source: source))
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return (try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time), renderer)
    }
}

@Suite("Script engine")
struct ScriptEngineTests {
    @Test func dataAPIReadsTheSession() throws {
        let engine = ScriptEngine(source: "function frame(c, d) {}")
        // Bind data for time 4 s by running a frame, then evaluate expressions.
        let cg = CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: PixelBuffers.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        engine.drawFrame(
            into: try #require(cg), size: CGSize(width: 10, height: 10), time: 4,
            objectContext: ScriptSession.context())
        #expect(engine.evaluate("data.value('speed')") == "20")
        #expect(engine.evaluate("data.speed('kph').toFixed(1)") == "72.0")
        #expect(engine.evaluate("data.speed('mph').toFixed(1)") == "44.7")
        #expect(engine.evaluate("data.value('nope')") == "null")
        #expect(engine.evaluate("data.has('rpm')") == "true")
        #expect(engine.evaluate("data.lap.number") == "2")
        #expect(engine.evaluate("data.lap.last") == "4")
        #expect(engine.evaluate("data.lap.elapsed") == "0")
        #expect(engine.evaluate("data.laps.length") == "2")
        #expect(engine.evaluate("data.valueAgo('speed', 2)") == "15")
        #expect(engine.evaluate("data.range('rpm')[1]") == "7000")
        #expect(engine.evaluate("data.channels.includes('throttle')") == "true")
        #expect(engine.evaluate("data.time") == "4")
        #expect(engine.evaluate("data.duration") == "10")
        // Prelude helpers and RaceRender-style names.
        #expect(engine.evaluate("formatTime(83.456)") == "1:23.46")
        #expect(engine.evaluate("formatTime(5, 1)") == "0:05.0")
        #expect(engine.evaluate("formatDelta(-0.4)") == "−0.40")
        #expect(engine.evaluate("formatDelta(0.001)") == "0.00")
        #expect(engine.evaluate("GetDataValue(DFT_RPM)") == "4000")
        #expect(engine.evaluate("GetSpeed('kph').toFixed(0)") == "72")
        #expect(engine.evaluate("GetLapNumber()") == "2")
        #expect(engine.evaluate("GetLastLapTime()") == "4")
        #expect(engine.evaluate("clamp(5, 0, 3)") == "3")
        #expect(engine.error == nil)
    }

    @Test func reportsSyntaxAndRuntimeErrorsWithoutThrowing() throws {
        let syntax = ScriptEngine(source: "function frame(c, d) { this is not javascript }")
        #expect(syntax.error != nil)
        #expect(syntax.error?.line == 1)
        #expect(ScriptEngine.check("function frame(c, d) { c.rect(0,0,1,1); }") == nil)
        #expect(ScriptEngine.check("var x = ;") != nil)
        #expect(ScriptEngine.check("var x = 1;")?.message.contains("frame") == true)

        let runtime = ScriptEngine(source: "function frame(c, d) {\n  undefinedFunction();\n}")
        #expect(runtime.error == nil)
        let cg = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: PixelBuffers.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        runtime.drawFrame(
            into: cg, size: CGSize(width: 10, height: 10), time: 1, objectContext: ScriptSession.context())
        #expect(runtime.error?.line == 2)
        #expect(runtime.error?.message.contains("undefinedFunction") == true)
    }

    @Test func colourParsing() {
        #expect(RGBAColor(css: "#ff0000") == .red || RGBAColor(css: "#ff0000") == RGBAColor(red: 1, green: 0, blue: 0))
        #expect(RGBAColor(css: "rgba(255, 128, 0, 0.5)") == RGBAColor(red: 1, green: 128 / 255, blue: 0, alpha: 0.5))
        #expect(RGBAColor(css: "rgb(0,0,255)") == RGBAColor(red: 0, green: 0, blue: 1))
        #expect(RGBAColor(css: "white") == .white)
        #expect(RGBAColor(css: "nonsense") == nil)
    }
}

@Suite("Scripted renderer")
struct ScriptedRendererTests {
    @Test func drawsShapesAndTextClippedToTheFrame() throws {
        // Frame is x 40…360, y 20…120 of a 400×200 output.
        let source = """
            function background(canvas) { canvas.fill("#0000ff"); canvas.rect(0, 0, canvas.width, canvas.height); }
            function frame(canvas, data) {
                canvas.fill("#ff0000");
                canvas.circle(canvas.width / 2, canvas.height / 2, canvas.height * 0.4);
                canvas.fill("#00ff00");
                canvas.rect(-50, -50, 40, 40);  // outside: must be clipped away
                canvas.fill("#ffffff");
                canvas.text(data.speed("mph").toFixed(0), 4, 2, { size: 24, bold: true });
            }
            """
        let (frame, renderer) = try ScriptSession.render(source, time: 4)
        #expect(renderer.engine.error == nil)
        let blue = PixelBuffers.pixel(in: frame, x: 50, y: 110)
        #expect(blue.b > 200 && blue.r < 30, "background \(blue)")
        let red = PixelBuffers.pixel(in: frame, x: 200, y: 70)
        #expect(red.r > 200 && red.b < 30, "circle \(red)")
        let outside = PixelBuffers.pixel(in: frame, x: 20, y: 10)
        #expect(outside.r < 10 && outside.g < 10 && outside.b < 10, "clipped \(outside)")
        // Text "45" leaves white pixels near the top-left of the frame.
        var white = 0
        for y in 22..<48 {
            for x in 44..<90 where PixelBuffers.pixel(in: frame, x: x, y: y).g > 220 { white += 1 }
        }
        #expect(white > 20)
    }

    @Test func brokenScriptDrawsABadgeAndNeverThrows() throws {
        let (frame, renderer) = try ScriptSession.render(
            "function frame(c, d) { c.rect(0, 0, undefinedVariable, 1); }", time: 1)
        #expect(renderer.engine.error != nil)
        let badge = PixelBuffers.pixel(in: frame, x: 200, y: 100)
        #expect(badge.r > 100 && badge.g < 60, "badge \(badge)")
        let (frame2, renderer2) = try ScriptSession.render("not javascript at all", time: 1)
        #expect(renderer2.engine.error != nil)
        #expect(PixelBuffers.pixel(in: frame2, x: 200, y: 100).r > 100)
    }

    @Test func everyExampleRunsClean() throws {
        for example in ScriptExamples.all {
            let (_, renderer) = try ScriptSession.render(example.source, time: 6)
            #expect(renderer.engine.error == nil, "\(example.name): \(renderer.engine.error?.message ?? "")")
        }
        #expect(ScriptEngine.check(ScriptedParams.defaultSource) == nil)
    }

    @Test func raceRenderStyleScriptWorks() throws {
        let source = """
            function frame(canvas, data) {
                SetColor(0, 0, 0, 200);
                DrawRect(0, 0, Width(), Height());
                SetColor(255, 255, 255);
                DrawText(10, 10, "RPM " + GetDataValue(DFT_RPM).toFixed(0), 24);
                DrawTime(10, 50, GetLapTime(), 24);
                DrawLine(0, Height() - 1, Width() * GetDataValue(DFT_Throttle) / 100, Height() - 1);
            }
            """
        let (frame, renderer) = try ScriptSession.render(source, time: 5)
        #expect(renderer.engine.error == nil)
        #expect(PixelBuffers.pixel(in: frame, x: 200, y: 90).r < 40)  // dark panel
        #expect(renderer.engine.evaluate("GetDataValue(DFT_RPM)") == "4500")
    }

    @Test func frameBudget() throws {
        // A busy script: 60 shapes and 4 text draws per frame, 300 frames.
        let source = """
            function frame(canvas, data) {
                for (let i = 0; i < 60; i++) {
                    canvas.fill(i % 2 ? "#ff9e1a" : "#ffffff");
                    canvas.rect(i * 5, 10, 4, 30 + (data.value("rpm") % 40));
                }
                canvas.text(data.speed("mph").toFixed(1), 10, 60, { size: 28, bold: true });
                canvas.text(formatTime(data.lap.elapsed), 10, 100, { size: 20 });
                canvas.text("LAP " + data.lap.number, 200, 60, { size: 20 });
                canvas.text(formatDelta(data.lap.delta), 200, 100, { size: 20 });
            }
            """
        let renderer = ScriptedRenderer(context: ScriptSession.context(), params: ScriptedParams(source: source))
        let plan = RenderPlan(
            outputWidth: 1920, outputHeight: 1080, frameRate: 30, videoLayers: [], overlays: [renderer])
        let compositor = try FrameCompositor(plan: plan)
        for i in 0..<300 { _ = try compositor.renderFrame(sources: [:], time: Double(i) / 30) }
        #expect(renderer.engine.error == nil)
        let average = renderer.engine.averageFrameSeconds
        print("script frame average: \(average * 1000) ms")
        #expect(average < 0.004, "average \(average * 1000) ms per frame")
    }
}

@Suite("Scripted model")
struct ScriptedModelTests {
    @Test func roundTripsAndDefaults() throws {
        let kind = DisplayObjectKind.scripted(ScriptedParams(source: "function frame(c, d) {}"))
        let data = try JSONEncoder().encode(kind)
        #expect(try JSONDecoder().decode(DisplayObjectKind.self, from: data) == kind)
        #expect(kind.needsData && kind.isOverlay && kind.typeName == "Script")
        let legacy = try JSONDecoder().decode(ScriptedParams.self, from: Data("{}".utf8))
        #expect(legacy.source == ScriptedParams.defaultSource)
        #expect(DisplayObject.templates.map(\.name).contains("Script"))
        // Without a factory the planner skips scripted objects; with one it uses it.
        let data2 = Input(label: "d", source: MediaReference(path: "x.csv"), kind: .data(DataInputSettings()))
        let project = Project(
            inputs: [data2],
            displayObjects: [DisplayObject(label: "s", inputID: data2.id, frame: .full, kind: kind)])
        #expect(RenderPlanner.overlays(for: project, sessions: [data2.id: ScriptSession.session]).isEmpty)
        let withFactory = RenderPlanner.overlays(
            for: project, sessions: [data2.id: ScriptSession.session],
            scriptRenderer: { params, context in ScriptedRenderer(context: context, params: params) })
        #expect(withFactory.count == 1)
    }
}
