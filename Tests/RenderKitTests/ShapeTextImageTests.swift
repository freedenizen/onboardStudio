import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit
@testable import TelemetryKit

@Suite("Shape, text and image renderers")
struct ShapeTextImageTests {
    let size = CGSize(width: 400, height: 400)

    func render(_ kind: DisplayObjectKind, frame: UnitRect, image: LoadedImage? = nil, time: Double = 0) throws
        -> CVPixelBuffer
    {
        let context = ObjectContext(
            objectID: DisplayObjectID(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()), frame: frame,
            opacity: 1, sampler: TelemetrySampler(session: SyntheticSession.session), sync: .identity,
            cache: RenderCache())
        let renderer = try #require(RenderPlanner.renderer(for: kind, context: context, image: image))
        let plan = RenderPlan(outputWidth: 400, outputHeight: 400, frameRate: 30, videoLayers: [], overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    static var arrow: LoadedImage {
        get throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(
                path: "Fixtures/arrow.png")
            return try LoadedImage.load(url)
        }
    }

    @Test func shapes() throws {
        let params = ShapeParams(
            shape: .ellipse, fillColor: RGBAColor(red: 0.2, green: 0.6, blue: 1), strokeColor: .white, strokeWidth: 0.01
        )
        let frame = try render(.shape(params), frame: UnitRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6))
        try GoldenImage.assertMatches(frame, named: "shape-ellipse")
        let centre = PixelBuffers.pixel(in: frame, x: 200, y: 200)
        #expect(centre.b > 200 && centre.r < 100)
        #expect(PixelBuffers.pixel(in: frame, x: 45, y: 85).r == 0)  // outside the ellipse, inside the frame
        let rect = try render(
            .shape(ShapeParams(shape: .rectangle, fillColor: .white)),
            frame: UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(PixelBuffers.pixel(in: rect, x: 202, y: 202).r == 255)
        #expect(PixelBuffers.pixel(in: rect, x: 198, y: 198).r == 0)
    }

    @Test func text() throws {
        let params = TextParams(
            text: "Lap 3", fontScale: 0.6, color: .white, backgroundColor: .translucentBlack, alignment: .center,
            outlineWidth: 0.05)
        let frame = try render(.text(params), frame: UnitRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2))
        try GoldenImage.assertMatches(frame, named: "text-caption")
        var lit = 0
        for x in stride(from: 40, to: 360, by: 2) where PixelBuffers.pixel(in: frame, x: x, y: 200).r > 200 { lit += 1 }
        #expect(lit > 10)
    }

    @Test func imageStaticAndRotated() throws {
        let image = try Self.arrow
        let up = try render(
            .image(ImageObjectParams()), frame: UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), image: image)
        try GoldenImage.assertMatches(up, named: "image-arrow-up")
        // Arrow head near the top centre, shaft at the bottom centre.
        #expect(PixelBuffers.pixel(in: up, x: 200, y: 130).r > 150)
        #expect(PixelBuffers.pixel(in: up, x: 200, y: 280).r > 150)
        #expect(PixelBuffers.pixel(in: up, x: 120, y: 200).r == 0)
        // Rotated 90° clockwise: the head points right.
        let right = try render(
            .image(ImageObjectParams(rotation: 90)), frame: UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            image: image)
        #expect(PixelBuffers.pixel(in: right, x: 270, y: 200).r > 150)
        #expect(PixelBuffers.pixel(in: right, x: 140, y: 140).r == 0)
    }

    @Test func imageFollowsChannels() throws {
        let image = try Self.arrow
        let frame = UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        // Heading channel from the synthetic session: between t=2.5 and 5 the car heads east (90°).
        let heading = try render(
            .image(ImageObjectParams(rotationChannel: "heading", degreesPerUnit: 1)), frame: frame, image: image,
            time: 3)
        #expect(PixelBuffers.pixel(in: heading, x: 270, y: 200).r > 150, "arrow should point east")
        // Opacity from a channel: gear 1…6 scaled by 1/6 → ~0.17 at t=0.
        let faint = try render(
            .image(ImageObjectParams(opacityChannel: "gear", opacityScale: 1.0 / 6)), frame: frame, image: image,
            time: 0)
        let p = PixelBuffers.pixel(in: faint, x: 200, y: 280)
        #expect(p.r > 20 && p.r < 90, "expected a faint arrow, got \(p)")
        // Flashing: with speed above threshold the image is hidden for half of each cycle.
        let params = ImageObjectParams(flashChannel: "speed", flashThreshold: 0, flashHertz: 1)
        let shown = try render(.image(params), frame: frame, image: image, time: 0.25)
        let hidden = try render(.image(params), frame: frame, image: image, time: 0.75)
        #expect(PixelBuffers.pixel(in: shown, x: 200, y: 280).r > 150)
        #expect(PixelBuffers.pixel(in: hidden, x: 200, y: 280).r == 0)
    }

    @Test func plannerWiresImagesAndVideoTransforms() {
        let video = Input(
            label: "v", source: MediaReference(path: "v.mp4"),
            kind: .video(VideoInputSettings(rotation: 90, mirror: Mirror(horizontal: true), crop: CropInsets(top: 0.1)))
        )
        let picture = Input(label: "p", source: MediaReference(path: "p.png"), kind: .image(ImageInputSettings()))
        let project = Project(
            inputs: [video, picture],
            displayObjects: [
                DisplayObject(
                    label: "v", inputID: video.id, frame: .full,
                    kind: .video(
                        VideoObjectParams(mirror: Mirror(horizontal: true), channelMask: RGBMask(red: false)))),
                DisplayObject(label: "p", inputID: picture.id, frame: .full, kind: .image(ImageObjectParams())),
                DisplayObject(label: "t", inputID: nil, frame: .full, kind: .text(TextParams())),
            ])
        let layers = RenderPlanner.videoLayers(for: project, trackIDs: [video.id: 5])
        #expect(layers.count == 1)
        #expect(layers[0].transform.rotation == 90)
        #expect(layers[0].transform.mirror == Mirror(horizontal: false))  // input mirror cancelled by object mirror
        #expect(layers[0].transform.crop.top == 0.1)
        #expect(layers[0].transform.channelMask.red == false)
        let overlays = RenderPlanner.overlays(for: project, sessions: [:], images: [:])
        #expect(overlays.count == 2)
        #expect(overlays[0] is ImageRenderer && overlays[1] is TextRenderer)
    }
}

@Suite("Track projection performance")
struct TrackProjectionPerformanceTests {
    /// A 20-minute session at 100 Hz (120k points) must project in well under a second; a
    /// quadratic implementation took minutes on real RaceChrono exports.
    @Test func projectsLongSessionsQuickly() {
        let count = 120_000
        let times = (0..<count).map { Double($0) / 100 }
        let lat = Channel(
            role: .latitude, name: "lat", unit: .degrees, times: times, values: times.map { 45 + 0.001 * sin($0 / 60) })
        let lon = Channel(
            role: .longitude, name: "lon", unit: .degrees, times: times,
            values: times.map { -122 + 0.001 * cos($0 / 60) })
        let session = TelemetrySession(info: SessionInfo(sourceFormat: "perf"), channels: [lat, lon])
        let start = Date()
        let projection = TrackProjection(session: session, rotationDegrees: 0)
        let elapsed = Date().timeIntervalSince(start)
        #expect(projection?.points.count == count)
        #expect(elapsed < 5, "projection took \(elapsed) s")
    }
}
