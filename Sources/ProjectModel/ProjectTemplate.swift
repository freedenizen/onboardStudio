import Foundation

/// Everything in a project except its inputs: the objects, the timeline, output size and export
/// settings. Applying a template to a project keeps the project's inputs and rebinds the
/// template's objects to them.
public struct ProjectTemplate: Hashable, Codable, Sendable {
    public static let formatVersion = 1
    public static let fileExtension = "overlaytemplate"

    public var formatVersion: Int
    public var name: String
    public var settings: ProjectSettings
    public var export: ExportSettings
    public var displayObjects: [DisplayObject]
    public var timeline: Timeline

    public init(name: String, project: Project) {
        formatVersion = Self.formatVersion
        self.name = name
        settings = project.settings
        export = project.export
        // Inputs are not part of a template; objects keep an ordinal so they can be rebound.
        displayObjects = project.displayObjects.map { object in
            var copy = object
            copy.inputID = nil
            return copy
        }
        timeline = project.timeline
        // Remember which video input (by order) each video object used.
        let videoInputs = project.videoInputs.map(\.id)
        for (index, object) in project.displayObjects.enumerated() {
            if case .video = object.kind, let id = object.inputID, let ordinal = videoInputs.firstIndex(of: id) {
                displayObjects[index].label = object.label
                videoOrdinals[object.id] = ordinal
            }
        }
    }

    /// Video object id → index of the video input it used, so PiP layouts survive re-binding.
    public var videoOrdinals: [DisplayObjectID: Int] = [:]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, name, settings, export, displayObjects, timeline, videoOrdinals
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Template"
        settings = try c.decodeIfPresent(ProjectSettings.self, forKey: .settings) ?? ProjectSettings()
        export = try c.decodeIfPresent(ExportSettings.self, forKey: .export) ?? .hd1080
        displayObjects = try c.decodeIfPresent([DisplayObject].self, forKey: .displayObjects) ?? []
        timeline = try c.decodeIfPresent(Timeline.self, forKey: .timeline) ?? .empty
        let raw = try c.decodeIfPresent([String: Int].self, forKey: .videoOrdinals) ?? [:]
        videoOrdinals = Dictionary(
            uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { (DisplayObjectID($0), value) }
            })
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(name, forKey: .name)
        try c.encode(settings, forKey: .settings)
        try c.encode(export, forKey: .export)
        try c.encode(displayObjects, forKey: .displayObjects)
        try c.encode(timeline, forKey: .timeline)
        try c.encode(
            Dictionary(uniqueKeysWithValues: videoOrdinals.map { ($0.key.rawValue.uuidString, $0.value) }),
            forKey: .videoOrdinals)
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public init(data: Data) throws {
        let template = try JSONDecoder().decode(ProjectTemplate.self, from: data)
        guard template.formatVersion <= Self.formatVersion else {
            throw ProjectTemplateError.newerFormat(template.formatVersion)
        }
        self = template
    }

    /// Replaces the project's objects, timeline, output settings and export settings with the
    /// template's, binding video objects to the project's video inputs in order and data objects
    /// to its first data input. Video objects with no matching input are dropped.
    public func apply(to project: inout Project) {
        let videoInputs = project.videoInputs.map(\.id)
        let dataInput = project.dataInputs.first?.id
        var objects: [DisplayObject] = []
        var nextVideo = 0
        for var object in displayObjects {
            if case .video = object.kind {
                let ordinal = videoOrdinals[object.id] ?? nextVideo
                nextVideo = max(nextVideo, ordinal + 1)
                guard ordinal < videoInputs.count else { continue }
                object.inputID = videoInputs[ordinal]
            } else if object.kind.needsData {
                object.inputID = dataInput
            } else {
                object.inputID = nil
            }
            objects.append(object)
        }
        project.displayObjects = objects
        var timeline = self.timeline
        timeline.prune(keeping: objects.map(\.id))
        project.timeline = timeline
        project.settings = settings
        project.export = export
    }

    /// A project with no inputs showing the template's objects (for New from Template).
    public func makeProject() -> Project {
        var project = Project()
        apply(to: &project)
        return project
    }
}

public enum ProjectTemplateError: Error, CustomStringConvertible {
    case newerFormat(Int)

    public var description: String {
        switch self {
        case .newerFormat(let version): "This template was saved by a newer version of OverlayGen (format \(version))."
        }
    }
}

// MARK: - Built-in templates

extension ProjectTemplate {
    /// Templates shipped with the app.
    public static let builtIn: [ProjectTemplate] = [classicDash, minimal, dataWall]

    private static func make(_ name: String, _ objects: [DisplayObject]) -> ProjectTemplate {
        let camera = DisplayObject(label: "Camera", inputID: nil, frame: .full, kind: .video(VideoObjectParams()))
        return ProjectTemplate(name: name, project: Project(displayObjects: [camera] + objects))
    }

    private static func object(_ label: String, _ kind: DisplayObjectKind, _ frame: UnitRect) -> DisplayObject {
        DisplayObject(label: label, inputID: nil, frame: frame, kind: kind)
    }

    /// Speedometer, tachometer, track map, G-force, lap timer and gear: the RaceRender look.
    public static let classicDash = make(
        "Classic Dash",
        [
            object("Speed", .speedometer(.speedometer()), UnitRect(x: 0.74, y: 0.56, width: 0.22, height: 0.4)),
            object("RPM", .tachometer(.tachometer()), UnitRect(x: 0.52, y: 0.62, width: 0.18, height: 0.32)),
            object("Map", .trackMap(TrackMapParams()), UnitRect(x: 0.03, y: 0.05, width: 0.2, height: 0.34)),
            object("G", .gForce(GForceParams()), UnitRect(x: 0.03, y: 0.62, width: 0.16, height: 0.28)),
            object("Lap", .timer(TimerParams()), UnitRect(x: 0.3, y: 0.04, width: 0.4, height: 0.08)),
            object("Best", .timer(TimerParams(mode: .bestLap)), UnitRect(x: 0.3, y: 0.13, width: 0.4, height: 0.06)),
            object("Gear", .gear(GearParams()), UnitRect(x: 0.66, y: 0.05, width: 0.07, height: 0.12)),
        ])

    /// Just the numbers: speed and lap readouts with a small map.
    public static let minimal = make(
        "Minimal",
        [
            object(
                "Speed", .textData(TextDataParams(channel: "speed", label: "", alignment: .trailing, fontScale: 0.7)),
                UnitRect(x: 0.72, y: 0.84, width: 0.25, height: 0.12)),
            object(
                "Lap", .timer(TimerParams(showLapNumber: true, label: "LAP")),
                UnitRect(x: 0.03, y: 0.86, width: 0.3, height: 0.08)),
            object("Map", .trackMap(TrackMapParams()), UnitRect(x: 0.83, y: 0.04, width: 0.14, height: 0.24)),
        ])

    /// Bars, graph, delta and counters for data-heavy videos.
    public static let dataWall = make(
        "Data Wall",
        [
            object(
                "Throttle",
                .bar(BarParams(channel: "throttle", label: "THR", segments: 20, unitLabel: "%")),
                UnitRect(x: 0.03, y: 0.5, width: 0.3, height: 0.05)),
            object(
                "Brake",
                .bar(
                    BarParams(
                        channel: "brake", label: "BRK", fillColor: .red, segments: 20, unitLabel: "%")),
                UnitRect(x: 0.03, y: 0.56, width: 0.3, height: 0.05)),
            object(
                "Speed vs best",
                .graph(GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap, label: "SPEED")),
                UnitRect(x: 0.03, y: 0.63, width: 0.3, height: 0.22)),
            object(
                "Delta", .timer(TimerParams(mode: .deltaToBest)), UnitRect(x: 0.03, y: 0.42, width: 0.2, height: 0.06)),
            object("Lap", .timer(TimerParams()), UnitRect(x: 0.3, y: 0.04, width: 0.4, height: 0.08)),
            object(
                "Laps", .lapCounter(LapCounterParams(showTotal: true)),
                UnitRect(x: 0.03, y: 0.34, width: 0.15, height: 0.07)),
            object("Gear", .gear(GearParams()), UnitRect(x: 0.36, y: 0.03, width: 0.07, height: 0.12)),
            object("Speed", .speedometer(.speedometer()), UnitRect(x: 0.74, y: 0.56, width: 0.22, height: 0.4)),
            object("G", .gForce(GForceParams()), UnitRect(x: 0.8, y: 0.05, width: 0.16, height: 0.28)),
        ])
}
