import CoreGraphics
import CoreText
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

@Suite("Chosen fonts (#118)")
struct TypefaceTests {
    static let futura = Typeface(family: "Futura", face: "Condensed ExtraBold")
    static let missing = Typeface(family: "No Such Family", face: "Bold")

    @Test func facesAreListedLightestFirst() {
        let faces = Typefaces.faces(of: "Helvetica Neue")
        #expect(faces.contains("Regular"))
        #expect(faces.contains("Bold"))
        let regular = try? #require(faces.firstIndex(of: "Regular"))
        let bold = try? #require(faces.firstIndex(of: "Bold"))
        #expect((regular ?? 0) < (bold ?? 0))
        #expect(Typefaces.faces(of: Self.missing.family).isEmpty)
        #expect(Typefaces.families().contains("Helvetica Neue"))
        #expect(!Typefaces.families().contains { $0.hasPrefix(".") })
    }

    @Test func aChosenFaceResolvesToThatFaceAndNothingElse() throws {
        let font = try #require(Typefaces.font(Self.futura, size: 20))
        #expect(CTFontCopyFamilyName(font) as String == "Futura")
        #expect(CTFontCopyName(font, kCTFontStyleNameKey) as String? == "Condensed ExtraBold")
        // A family this Mac lacks is missing, not quietly swapped for one the system picked.
        #expect(Typefaces.font(Self.missing, size: 20) == nil)
        #expect(Typefaces.font(Typeface(family: "Futura", face: "No Such Face"), size: 20) == nil)
        #expect(!Typefaces.isInstalled(Self.missing))
    }

    @Test func pickingAFamilyKeepsTheFaceWhereItCan() {
        #expect(Typefaces.face(for: "Helvetica Neue", keeping: "Light") == "Light")
        #expect(Typefaces.face(for: "Helvetica Neue", keeping: "Condensed ExtraBold") == "Bold")
        #expect(Typefaces.face(for: "Futura", keeping: nil) == "Bold")
        #expect(Typefaces.face(for: Self.missing.family, keeping: "Bold") == nil)
    }

    @Test func aStyleTakesTheChosenFontAndSize() {
        let context = context(typeface: Self.futura, textScale: 1.5)
        let style = context.styled(.mono(20))
        let font = TextDrawing.font(for: style)
        #expect(CTFontCopyFamilyName(font) as String == "Futura")
        #expect(CTFontGetSize(font) == 30)
        // Without a choice the renderer's own font stands.
        let plain = TextDrawing.font(for: self.context().styled(.mono(20)))
        #expect(CTFontCopyPostScriptName(plain) as String == "Menlo-Bold")
        // A missing font draws in the renderer's own, not in a system stand-in.
        let fallback = TextDrawing.font(for: self.context(typeface: Self.missing).styled(.mono(20)))
        #expect(CTFontCopyPostScriptName(fallback) as String == "Menlo-Bold")
    }

    @Test func numbersKeepOneWidthInAProportionalFace() {
        let style = context(typeface: Typeface(family: "Helvetica Neue", face: "Bold")).styled(.mono(40))
        let one = TextDrawing.size(of: "111", style: style).width
        let eight = TextDrawing.size(of: "888", style: style).width
        #expect(abs(one - eight) < 1)
    }

    @Test func everyTextOfAnObjectIsDrawnInTheChosenFont() throws {
        let timer = DisplayObjectKind.timer(TimerParams())
        let plain = try render(timer)
        let futura = try render(timer, typeface: Self.futura)
        #expect(differingPixels(plain, futura) > 50)
        // A font that is not installed changes nothing at all.
        let missing = try render(timer, typeface: Self.missing)
        #expect(differingPixels(plain, missing) == 0)
        let larger = try render(timer, textScale: 1.4)
        #expect(litPixels(larger) > litPixels(plain))
    }

    @Test func aCachedFaceIsRedrawnWhenTheFontChanges() throws {
        // A gauge caches its face, labels and all; the same cache must not hand back the old face.
        let cache = RenderCache()
        let gauge = DisplayObjectKind.speedometer(GaugeParams.speedometer(unit: .kph, max: 200))
        let plain = try render(gauge, cache: cache)
        let futura = try render(gauge, typeface: Self.futura, cache: cache)
        #expect(differingPixels(plain, futura) > 50)
    }

    @Test func theObjectsFontWinsOverTheProjects() {
        var project = Project()
        project.settings.typeface = Self.futura
        var object = DisplayObject(label: "Timer", inputID: nil, frame: .full, kind: .timer(TimerParams()))
        #expect(RenderPlanner.typeface(for: object, in: project) == Self.futura)
        object.typeface = Typeface(family: "Helvetica Neue", face: "Light")
        #expect(RenderPlanner.typeface(for: object, in: project)?.face == "Light")
        #expect(RenderPlanner.typeface(for: object, in: Project())?.face == "Light")
        object.typeface = nil
        #expect(RenderPlanner.typeface(for: object, in: Project()) == nil)
    }

    // MARK: -

    func context(typeface: Typeface? = nil, textScale: Double = 1, cache: RenderCache = RenderCache())
        -> ObjectContext
    {
        ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000118") ?? UUID()),
            frame: UnitRect(x: 0.05, y: 0.3, width: 0.9, height: 0.4), opacity: 1,
            sampler: TelemetrySampler(session: SyntheticSession.session), sync: .identity, cache: cache,
            typeface: typeface, textScale: textScale)
    }

    func render(
        _ kind: DisplayObjectKind, typeface: Typeface? = nil, textScale: Double = 1, cache: RenderCache = RenderCache()
    ) throws -> CVPixelBuffer {
        let context = context(typeface: typeface, textScale: textScale, cache: cache)
        let renderer = try #require(RenderPlanner.renderer(for: kind, context: context, image: nil))
        let plan = RenderPlan(outputWidth: 400, outputHeight: 400, frameRate: 30, videoLayers: [], overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 12.3)
    }

    /// Sampled pixels that look different: some channel more than a few levels apart (#258).
    ///
    /// Not any difference at all. Frames are composited on the GPU, and CI's runner is a VM on a
    /// paravirtualised one, where the same frame drawn twice can come back with a glyph edge one
    /// level off — 24 such pixels once failed "a missing font changes nothing". A font that is
    /// really different moves hundreds of pixels by far more than this.
    func differingPixels(_ a: CVPixelBuffer, _ b: CVPixelBuffer, tolerance: Int = 8) -> Int {
        var count = 0
        for y in stride(from: 0, to: 400, by: 2) {
            for x in stride(from: 0, to: 400, by: 2) {
                let p = PixelBuffers.pixel(in: a, x: x, y: y)
                let q = PixelBuffers.pixel(in: b, x: x, y: y)
                let apart = [(p.r, q.r), (p.g, q.g), (p.b, q.b), (p.a, q.a)].map { abs(Int($0) - Int($1)) }.max() ?? 0
                if apart > tolerance { count += 1 }
            }
        }
        return count
    }

    func litPixels(_ buffer: CVPixelBuffer) -> Int {
        var count = 0
        for y in stride(from: 0, to: 400, by: 2) {
            for x in stride(from: 0, to: 400, by: 2) where PixelBuffers.pixel(in: buffer, x: x, y: y).r > 128 {
                count += 1
            }
        }
        return count
    }
}

@Suite("Details in text (#74)")
struct DetailTextRenderTests {
    @Test func aTextObjectIsDrawnWithTheProjectsDetailsFilledIn() throws {
        var project = Project()
        project.details = ProjectDetails(track: "Sonoma Raceway")
        project.displayObjects = [
            DisplayObject(label: "Title", inputID: nil, frame: .full, kind: .text(TextParams(text: "{track} {car}")))
        ]
        let overlays = RenderPlanner.overlays(for: project, sessions: [:])
        let text = try #require(overlays.first as? TextRenderer)
        // The car was never entered, so it still asks for one.
        #expect(text.params.text == "Sonoma Raceway {car}")
    }
}
