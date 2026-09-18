import AVFoundation
import CoreVideo
import Foundation
import RenderKit

/// The instruction handed to `OverlayCompositor` for a time range. Carries the render plan.
public final class OverlayInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    public let plan: RenderPlan

    public init(timeRange: CMTimeRange, plan: RenderPlan, sourceTrackIDs: [Int32]) {
        self.timeRange = timeRange
        self.plan = plan
        self.requiredSourceTrackIDs = sourceTrackIDs.map { NSNumber(value: $0) }
        super.init()
    }
}

/// `AVVideoCompositing` implementation shared by preview and export. For every frame AVFoundation
/// hands us the source pixel buffers; we delegate to `FrameCompositor`.
public final class OverlayCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    public let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [PixelBuffers.pixelFormat],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
    ]
    // swiftlint:disable:next identifier_name
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [PixelBuffers.pixelFormat],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
    ]

    private let lock = NSLock()
    /// Per-instruction compositors. The entry retains its instruction so a recycled object address
    /// can never be mistaken for the instruction that created the cached plan.
    private var compositors: [ObjectIdentifier: (instruction: OverlayInstruction, compositor: FrameCompositor)] = [:]

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock()
        compositors.removeAll()
        lock.unlock()
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? OverlayInstruction else {
            request.finish(with: CompositorError.unexpectedInstruction)
            return
        }
        do {
            let compositor = try self.compositor(for: instruction)
            guard let output = request.renderContext.newPixelBuffer() else { throw CompositorError.noOutputBuffer }
            var sources: [Int32: CVPixelBuffer] = [:]
            for layer in instruction.plan.videoLayers {
                if let buffer = request.sourceFrame(byTrackID: layer.trackID) { sources[layer.trackID] = buffer }
            }
            try compositor.render(sources: sources, time: request.compositionTime.seconds, into: output)
            request.finish(withComposedVideoFrame: output)
        } catch {
            request.finish(with: error)
        }
    }

    public func cancelAllPendingVideoCompositionRequests() {}

    private func compositor(for instruction: OverlayInstruction) throws -> FrameCompositor {
        lock.lock()
        defer { lock.unlock() }
        let key = ObjectIdentifier(instruction)
        if let existing = compositors[key], existing.instruction === instruction { return existing.compositor }
        let created = try FrameCompositor(plan: instruction.plan)
        compositors[key] = (instruction, created)
        return created
    }
}

public enum CompositorError: Error, CustomStringConvertible {
    case unexpectedInstruction
    case noOutputBuffer

    public var description: String {
        switch self {
        case .unexpectedInstruction: "The video composition contains an instruction OverlayCompositor cannot handle."
        case .noOutputBuffer: "AVFoundation did not provide an output pixel buffer."
        }
    }
}
