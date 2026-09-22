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

    /// The unit the session's speed was recorded in, which is what *Automatic* resolves to.
    ///
    /// Only the three the app can display; anything else — or no speed channel at all — has no
    /// opinion, and the chain falls through to its last resort.
    ///
    /// Asks the session, not the channel: `SessionBuilder` converts every speed channel to m/s
    /// on import, so the channel's own unit would answer m/s for every file ever loaded.
    public static func recordedSpeedUnit(of session: TelemetrySession) -> SpeedDisplayUnit? {
        switch session.recordedUnit(of: .speed) {
        case .milesPerHour: .mph
        case .kilometersPerHour: .kph
        case .metersPerSecond: .metersPerSecond
        default: nil
        }
    }

    /// The data input an object reads: its own, except that an image object takes its picture
    /// from an image input and its data from the first data input.
    static func dataInputID(for object: DisplayObject, in project: Project) -> InputID? {
        object.kind.needsImage ? project.dataInputs.first?.id : object.inputID
    }

    /// #75's chain for one object — object → project → app → the data it reads — so the
    /// renderer and the inspector describing what the renderer will do agree by construction.
    public static func unitResolver(
        for object: DisplayObject, in project: Project, sessions: [InputID: TelemetrySession],
        appSpeedUnit: SpeedUnitSetting
    ) -> UnitResolver {
        let session = dataInputID(for: object, in: project).flatMap { sessions[$0] }
        return UnitResolver(
            app: appSpeedUnit, project: project.settings.speedUnit,
            automatic: session.flatMap(recordedSpeedUnit(of:)))
    }

    /// #89's chain for every channel of one object's data input: which unit each is drawn in, and
    /// what it is labelled with.
    ///
    /// Speed keeps the chain #75 gave it — the object's own pin still wins — with the attribute
    /// table slotted in beneath it, so that a display unit set for Speed in the table is honoured
    /// while a project saved before the table existed resolves exactly as it always did. Every
    /// other attribute has no object-level pin yet, so the table is the whole of its chain.
    public static func displayUnits(
        for object: DisplayObject, in project: Project, sessions: [InputID: TelemetrySession],
        appSpeedUnit: SpeedUnitSetting, globalAttributeMappings: AttributeMappingTable
    ) -> DisplayUnits {
        guard let inputID = dataInputID(for: object, in: project), let session = sessions[inputID] else {
            return DisplayUnits()
        }
        let mappings = AttributeMappingResolver(
            global: globalAttributeMappings, project: project.settings.attributeMappings,
            input: project.input(inputID)?.dataSettings?.attributeMappings ?? AttributeMappingTable())
        let speed = unitResolver(for: object, in: project, sessions: sessions, appSpeedUnit: appSpeedUnit)

        var conversions: [String: DisplayUnits.Conversion] = [:]
        for channel in session.channels.values {
            let identifier = channel.role.identifier
            let chosen = mappings.resolved(identifier).displayUnit.map { TelemetryUnit(parsing: $0) }
            if ChannelValue.isSpeed(identifier) {
                // The object's own pin outranks the table, as it always has; below it the table
                // speaks, and below that #75's project and app preferences.
                let pinned = object.kind.speedUnit.pinned
                let unit = pinned.map(TelemetryUnit.init(speed:)) ?? chosen
                let fallback = speed.speed(object.kind.speedUnit)
                conversions[identifier] = DisplayUnits.Conversion(
                    from: channel.unit, to: unit ?? TelemetryUnit(speed: fallback),
                    // `SpeedDisplayUnit` spells km/h "kph" and always has. Keep that wherever the
                    // legacy chain answered, so no saved project's speedometer changes its label.
                    label: unit == nil || pinned != nil ? fallback.rawValue : nil)
            } else if let chosen {
                conversions[identifier] = DisplayUnits.Conversion(from: channel.unit, to: chosen)
            }
        }
        return DisplayUnits(conversions)
    }

    /// Overlay drawings in draw order for all visible non-video objects.
    public static func overlays(
        for project: Project,
        objects: [DisplayObject]? = nil,
        sessions: [InputID: TelemetrySession],
        images: [InputID: LoadedImage] = [:],
        cache: RenderCache = RenderCache(),
        scriptRenderer: ScriptRendererFactory? = nil,
        mapBackgrounds: [MapBackgroundRequest: MapBackground] = [:],
        appSpeedUnit: SpeedUnitSetting = .automatic,
        globalAttributeMappings: AttributeMappingTable = AttributeMappingTable()
    ) -> [any OverlayDrawing] {
        (objects ?? project.displayObjects).compactMap { object -> (any OverlayDrawing)? in
            guard object.isVisible, object.kind.isOverlay else { return nil }
            let input = object.inputID.flatMap(project.input)
            let dataInputID = dataInputID(for: object, in: project)
            let sampler = dataInputID.flatMap { sessions[$0] }.map(TelemetrySampler.init)
            let sync = (object.kind.needsImage ? project.dataInputs.first?.sync : input?.sync) ?? .identity
            // #75's and #89's chains, resolved here so every renderer is handed units it can
            // convert with rather than settings that may still say "automatic".
            let resolver = unitResolver(for: object, in: project, sessions: sessions, appSpeedUnit: appSpeedUnit)
            let context = ObjectContext(
                objectID: object.id, frame: object.frame, opacity: object.opacity, sampler: sampler, sync: sync,
                cache: cache, speedUnit: resolver.speed(object.kind.speedUnit),
                units: displayUnits(
                    for: object, in: project, sessions: sessions, appSpeedUnit: appSpeedUnit,
                    globalAttributeMappings: globalAttributeMappings))
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
        case .sectorPanel(let params): SectorPanelRenderer(context: context, params: params)
        case .steeringWheel(let params): SteeringWheelRenderer(context: context, params: params)
        case .scripted: nil  // needs the Scripting module; see `overlays(scriptRenderer:)`
        }
    }
}
