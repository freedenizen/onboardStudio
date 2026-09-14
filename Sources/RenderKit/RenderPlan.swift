import CoreGraphics
import ProjectModel

/// Anything that draws overlay content for a frame. Implementations must be immutable value types
/// or otherwise thread-safe: the compositor calls `draw` from AVFoundation's background queues.
public protocol OverlayDrawing: Sendable {
    /// Draws into `context` whose coordinate system is `size` pixels with the origin at the
    /// top-left (already flipped for you). `time` is project time in seconds.
    func draw(in context: CGContext, size: CGSize, time: Double)
}

/// One video source placed on the output frame.
public struct VideoLayer: Sendable, Equatable {
    /// The composition track ID whose pixels feed this layer.
    public let trackID: Int32
    public let frame: UnitRect
    public let opacity: Double

    public init(trackID: Int32, frame: UnitRect = .full, opacity: Double = 1) {
        self.trackID = trackID
        self.frame = frame
        self.opacity = opacity
    }
}

/// Everything the compositor needs to render any frame. Immutable and Sendable so it can be
/// handed to AVFoundation's render queues; edits produce a new plan.
public struct RenderPlan: Sendable {
    public let outputWidth: Int
    public let outputHeight: Int
    public let frameRate: Double
    /// Bottom-to-top draw order.
    public let videoLayers: [VideoLayer]
    /// Drawn on top of all video layers, in order.
    public let overlays: [any OverlayDrawing]

    public init(
        outputWidth: Int, outputHeight: Int, frameRate: Double, videoLayers: [VideoLayer],
        overlays: [any OverlayDrawing]
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.frameRate = frameRate
        self.videoLayers = videoLayers
        self.overlays = overlays
    }

    public var outputSize: CGSize { CGSize(width: outputWidth, height: outputHeight) }
}
