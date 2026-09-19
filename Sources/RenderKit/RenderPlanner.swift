import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Turns a project's display objects into overlay drawings and video layers. Pure: media and data
/// loading happen elsewhere and are passed in.
public enum RenderPlanner {
    /// Video layers in draw order, keyed by the composition track ID assigned to each video input.
    /// Input picture settings and object mirror/mask combine into the layer transform.
    public static func videoLayers(
        for project: Project, objects: [DisplayObject]? = nil, trackIDs: [InputID: Int32],
        sourceTransforms: [Int32: CGAffineTransform] = [:]
    ) -> [VideoLayer] {
        (objects ?? project.displayObjects).compactMap { object -> VideoLayer? in
            guard object.isVisible, case .video(let params) = object.kind, let inputID = object.inputID,
                let trackID = trackIDs[inputID]
            else { return nil }
            var transform = VideoTransform()
            if let input = project.input(inputID), case .video(let settings) = input.kind {
                transform = VideoTransform(
                    lens: settings.lens, crop: project.settings.framing.effectiveCrop(over: settings.crop),
                    rotation: settings.rotation, mirror: settings.mirror,
                    color: settings.color,
                    chromaKey: settings.chromaKey)
            }
            transform.mirror = Mirror(
                horizontal: transform.mirror.horizontal != params.mirror.horizontal,
                vertical: transform.mirror.vertical != params.mirror.vertical)
            transform.channelMask = params.channelMask
            return VideoLayer(
                trackID: trackID, frame: object.frame, opacity: object.opacity, transform: transform,
                sourceTransform: sourceTransforms[trackID] ?? .identity)
        }
    }

    /// Builds the drawing for a scripted object; supplied by the Scripting module so RenderKit
    /// stays free of JavaScriptCore.
    public typealias ScriptRendererFactory = @Sendable (ScriptedParams, ObjectContext) -> any OverlayDrawing

    /// Overlay drawings in draw order for all visible non-video objects.
    public static func overlays(
        for project: Project,
        objects: [DisplayObject]? = nil,
        sessions: [InputID: TelemetrySession],
        images: [InputID: LoadedImage] = [:],
        cache: RenderCache = RenderCache(),
        scriptRenderer: ScriptRendererFactory? = nil,
        mapBackgrounds: [MapBackgroundRequest: MapBackground] = [:]
    ) -> [any OverlayDrawing] {
        (objects ?? project.displayObjects).compactMap { object -> (any OverlayDrawing)? in
            guard object.isVisible, object.kind.isOverlay else { return nil }
            let input = object.inputID.flatMap(project.input)
            // Image objects take their picture from an image input and data from the first data input.
            let dataInputID: InputID? = object.kind.needsImage ? project.dataInputs.first?.id : object.inputID
            let sampler = dataInputID.flatMap { sessions[$0] }.map(TelemetrySampler.init)
            let sync = (object.kind.needsImage ? project.dataInputs.first?.sync : input?.sync) ?? .identity
            let context = ObjectContext(
                objectID: object.id, frame: object.frame, opacity: object.opacity, sampler: sampler, sync: sync,
                cache: cache)
            let image =
                object.inputID.flatMap { images[$0] }
                ?? object.kind.gaugeParams?.faceImageInputID.flatMap { images[$0] }
            if case .scripted(let params) = object.kind { return scriptRenderer?(params, context) }
            if case .trackMap(let params) = object.kind {
                let session = dataInputID.flatMap { sessions[$0] }
                let request = session.flatMap { MapBackgroundRequest(session: $0, style: params.background) }
                let second = params.secondInputID.flatMap { id -> SecondVehicle? in
                    guard let session = sessions[id], let input = project.input(id) else { return nil }
                    return SecondVehicle(sampler: TelemetrySampler(session: session), sync: input.sync)
                }
                return TrackMapRenderer(
                    context: context, params: params, second: second, background: request.flatMap { mapBackgrounds[$0] }
                )
            }
            return renderer(for: object.kind, context: context, image: image)
        }
    }

    /// The map imagery every track map in `project` needs, given the loaded sessions.
    public static func mapBackgroundRequests(for project: Project, sessions: [InputID: TelemetrySession])
        -> Set<MapBackgroundRequest>
    {
        var requests = Set<MapBackgroundRequest>()
        for object in project.displayObjects {
            guard case .trackMap(let params) = object.kind, params.background != .none, let inputID = object.inputID,
                let session = sessions[inputID],
                let request = MapBackgroundRequest(session: session, style: params.background)
            else { continue }
            requests.insert(request)
        }
        return requests
    }

    public static func renderer(
        for kind: DisplayObjectKind, context: ObjectContext, image: LoadedImage? = nil
    ) -> (any OverlayDrawing)? {
        switch kind {
        case .video: nil
        case .speedometer(let params), .tachometer(let params), .gauge(let params):
            GaugeRenderer(context: context, params: params, faceImage: params.faceImageInputID == nil ? nil : image)
        case .trackMap(let params): TrackMapRenderer(context: context, params: params)
        case .gForce(let params): GForceRenderer(context: context, params: params)
        case .timer(let params): TimerRenderer(context: context, params: params)
        case .textData(let params): TextDataRenderer(context: context, params: params)
        case .shape(let params): ShapeRenderer(context: context, params: params)
        case .text(let params): TextRenderer(context: context, params: params)
        case .image(let params): ImageRenderer(context: context, params: params, image: image)
        case .bar(let params): BarRenderer(context: context, params: params)
        case .graph(let params): GraphRenderer(context: context, params: params)
        case .gear(let params): GearRenderer(context: context, params: params)
        case .lapCounter(let params): LapCounterRenderer(context: context, params: params)
        case .indicator(let params): IndicatorRenderer(context: context, params: params)
        case .lapPanel(let params): LapPanelRenderer(context: context, params: params)
        case .scripted: nil  // needs the Scripting module; see `overlays(scriptRenderer:)`
        }
    }
}
