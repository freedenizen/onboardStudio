import CoreGraphics
import CoreImage
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Stabilisation (#262)")
struct StabilisationTests {
    /// 120 frames a second: a slow steady turn about y with an 8 Hz shake about x on top.
    static func shakyTurn(seconds: Double = 4) -> CameraOrientationTrack {
        let times = Array(stride(from: 0.0, to: seconds, by: 1.0 / 120))
        let camera = times.map { t -> Quaternion in
            let turn = 0.2 * t  // radians about y
            let shake = 0.01 * sin(2 * .pi * 8 * t)  // radians about x
            let yaw = Quaternion(w: cos(turn / 2), x: 0, y: sin(turn / 2), z: 0)
            let pitch = Quaternion(w: cos(shake / 2), x: sin(shake / 2), y: 0, z: 0)
            return (yaw * pitch).normalized
        }
        return CameraOrientationTrack(times: times, camera: camera, focalLength: 0.74)
    }

    @Test func theShakeIsCorrectedAndTheTurnComesThrough() throws {
        let track = Self.shakyTurn()
        let path = try #require(StabilisationPath(track: track, smoothing: 0.5, maxShift: 0.2))
        // Mid-clip, the vertical correction mirrors the 8 Hz shake about x at the lens's magnification…
        var worst = 0.0
        for t in stride(from: 1.0, to: 3.0, by: 1.0 / 120) {
            let shake = 0.01 * sin(2 * .pi * 8 * t)
            worst = max(worst, abs(path.correction(at: t).y + shake * 0.74))
        }
        #expect(worst < 0.002, "residual \(worst) picture heights")
        // …while the steady turn about y is followed, not corrected away.
        #expect(abs(path.correction(at: 2).x) < 0.01)
    }

    @Test func aStillCameraIsLeftAloneAndAMoveNeverExceedsTheZoom() throws {
        let still = CameraOrientationTrack(
            times: [0, 0.5, 1], camera: Array(repeating: .identity, count: 3), focalLength: 0.74)
        let steady = try #require(StabilisationPath(track: still, smoothing: 0.5, maxShift: 0.1))
        #expect(steady.correction(at: 0.5) == .zero)
        // A sudden 10° jolt cannot move a frame further than the zoom hides.
        let jolt = Quaternion(w: cos(0.0873), x: sin(0.0873), y: 0, z: 0)
        let jolted = CameraOrientationTrack(
            times: [0, 0.5, 0.51, 1], camera: [.identity, .identity, jolt, jolt], focalLength: 0.74)
        let capped = try #require(StabilisationPath(track: jolted, smoothing: 1, maxShift: 0.05))
        let c = capped.correction(at: 0.51)
        #expect(((c.x * c.x + c.y * c.y).squareRoot()) <= 0.05 + 1e-9)
        #expect(abs(StabilisationSettings(zoom: 1.2).maxShift - 0.2 / 2.4) < 1e-12)
    }

    @Test func samplesAreMovedBackByTheirLag() throws {
        var track = Self.shakyTurn(seconds: 1)
        track.lag = 2.0 / 120
        let path = try #require(StabilisationPath(track: track, smoothing: 0.3, maxShift: 0.2))
        let unlagged = try #require(
            StabilisationPath(
                track: CameraOrientationTrack(times: track.times, camera: track.camera, focalLength: 0.74),
                smoothing: 0.3, maxShift: 0.2))
        #expect(abs(path.correction(at: 0.5).y - unlagged.correction(at: 0.5 + 2.0 / 120).y) < 1e-9)
    }

    @Test func theCompositorMovesTheRecordedFrameBeforeAnythingElse() throws {
        // The camera jolts 0.1 rad about x at 5 s; a 2 s path has not followed it 10 ms later, so that
        // frame is moved back by about a tenth of its height (focal length 1 picture height per radian).
        let jolt = Quaternion(w: cos(0.05), x: sin(0.05), y: 0, z: 0)
        let track = CameraOrientationTrack(
            times: [0, 4.99, 5, 10], camera: [.identity, .identity, jolt, jolt], focalLength: 1)
        let path = try #require(StabilisationPath(track: track, smoothing: 2, maxShift: 1))
        let moved = path.correction(at: 5.01).y
        #expect(abs(abs(moved) - 0.1) < 0.02, "correction \(moved)")
        // A frame with a bright spot at its centre.
        let source = try PixelBuffers.makeBuffer(width: 200, height: 100)
        try PixelBuffers.fill(source, red: 0, green: 0, blue: 0)
        let spot = CIImage(color: .white).cropped(to: CGRect(x: 95, y: 45, width: 10, height: 10))
        CIContext().render(spot.composited(over: CIImage(cvPixelBuffer: source)), to: source)
        let layer = VideoLayer(trackID: 1, stabilisation: LayerStabilisation(path: path, zoom: 1, sync: .identity))
        let plan = RenderPlan(outputWidth: 200, outputHeight: 100, frameRate: 30, videoLayers: [layer], overlays: [])
        let frame = try FrameCompositor(plan: plan).renderFrame(sources: [1: source], time: 5.01)
        // Core Image's y is up and the buffer's rows run down: a positive correction lifts the spot.
        let row = 50 - Int((moved * 100).rounded())
        #expect(PixelBuffers.pixel(in: frame, x: 100, y: row).r > 200, "no spot at row \(row)")
        #expect(PixelBuffers.pixel(in: frame, x: 100, y: 50).r < 50, "the spot did not move")
        // Before the jolt the path is still, and so is the frame.
        let still = try FrameCompositor(plan: plan).renderFrame(sources: [1: source], time: 2)
        #expect(PixelBuffers.pixel(in: still, x: 100, y: 50).r > 200)
        // With no zoom to hide it, the frame keeps its size rather than shrinking to what is covered.
        let applied = LayerStabilisation(path: path, zoom: 1, sync: .identity)
            .apply(to: CIImage(cvPixelBuffer: source), at: 5.01)
        #expect(applied.extent == CGRect(x: 0, y: 0, width: 200, height: 100))
    }
}
