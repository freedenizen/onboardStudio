import Foundation
import ProjectModel
import TelemetryKit

/// Turns a project's display objects into overlay drawings and video layers. Pure: media and data
/// loading happen elsewhere and are passed in.
public enum RenderPlanner {
    /// Video layers in draw order, keyed by the composition track ID assigned to each video input.
    public static func videoLayers(for project: Project, trackIDs: [InputID: Int32]) -> [VideoLayer] {
        project.displayObjects.compactMap { object -> VideoLayer? in
            guard object.isVisible, case .video = object.kind, let inputID = object.inputID,
                let trackID = trackIDs[inputID]
            else { return nil }
            return VideoLayer(trackID: trackID, frame: object.frame, opacity: object.opacity)
        }
    }

    /// Overlay drawings in draw order for all visible non-video objects.
    public static func overlays(
        for project: Project, sessions: [InputID: TelemetrySession], cache: RenderCache = RenderCache()
    ) -> [any OverlayDrawing] {
        project.displayObjects.compactMap { object -> (any OverlayDrawing)? in
            guard object.isVisible, object.kind.needsData else { return nil }
            let input = object.inputID.flatMap(project.input)
            let sampler = object.inputID.flatMap { sessions[$0] }.map(TelemetrySampler.init)
            let context = ObjectContext(
                objectID: object.id, frame: object.frame, opacity: object.opacity, sampler: sampler,
                sync: input?.sync ?? .identity, cache: cache)
            return renderer(for: object.kind, context: context)
        }
    }

    public static func renderer(for kind: DisplayObjectKind, context: ObjectContext) -> (any OverlayDrawing)? {
        switch kind {
        case .video: nil
        case .speedometer(let params), .tachometer(let params), .gauge(let params):
            GaugeRenderer(context: context, params: params)
        case .trackMap(let params): TrackMapRenderer(context: context, params: params)
        case .gForce(let params): GForceRenderer(context: context, params: params)
        case .timer(let params): TimerRenderer(context: context, params: params)
        case .textData(let params): TextDataRenderer(context: context, params: params)
        }
    }
}
