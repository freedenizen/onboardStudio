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
    /// Input-level processing (crop, rotation, colour, chroma key) combined with object-level
    /// mirror and channel mask.
    public let transform: VideoTransform
    /// The source track's preferred (display) transform. Custom compositors receive buffers in
    /// encoded orientation, so this must be applied before anything else.
    public let sourceTransform: CGAffineTransform

    public init(
        trackID: Int32,
        frame: UnitRect = .full,
        opacity: Double = 1,
        transform: VideoTransform = .identity,
        sourceTransform: CGAffineTransform = .identity
    ) {
        self.trackID = trackID
        self.frame = frame
        self.opacity = opacity
        self.transform = transform
        self.sourceTransform = sourceTransform
    }

    public func with(frame: UnitRect, opacity: Double, transform: VideoTransform) -> VideoLayer {
        VideoLayer(
            trackID: trackID, frame: frame, opacity: opacity, transform: transform, sourceTransform: sourceTransform)
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
    /// What the frame is cleared to before any layer draws (opaque black for normal output;
    /// a key colour or transparent for overlay-only exports).
    public let background: RGBAColor

    public init(
        outputWidth: Int, outputHeight: Int, frameRate: Double, videoLayers: [VideoLayer],
        overlays: [any OverlayDrawing], background: RGBAColor = .black
    ) {
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.frameRate = frameRate
        self.videoLayers = videoLayers
        self.overlays = overlays
        self.background = background
    }

    /// The same plan without video layers, cleared to `background`.
    public func overlayOnly(background: RGBAColor) -> RenderPlan {
        RenderPlan(
            outputWidth: outputWidth, outputHeight: outputHeight, frameRate: frameRate, videoLayers: [],
            overlays: overlays, background: background)
    }

    public var outputSize: CGSize { CGSize(width: outputWidth, height: outputHeight) }
}
