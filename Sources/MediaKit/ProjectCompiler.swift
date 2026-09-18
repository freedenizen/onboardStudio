import AVFoundation
import CoreGraphics
import Foundation
import Importers
import ProjectModel
import RenderKit
import Scripting
import TelemetryKit

/// Loads a project's media and data files and compiles them into an AVFoundation composition
/// with overlays. The single entry point for both the CLI and the app.
public enum ProjectCompiler {
    public struct LoadedProject: Sendable {
        public var project: Project
        public var location: ProjectLocation
        public var sessions: [InputID: TelemetrySession]
        public var mediaInfo: [InputID: MediaInfo]
        /// Playable URL per video input (differs from the source when ffmpeg converted it).
        public var mediaURLs: [InputID: URL]
        public var images: [InputID: LoadedImage]
        /// Inputs that could not be loaded (missing or unreadable files) with the reason; the
        /// rest of the project still renders so the user can relink them.
        public var problems: [InputID: String]
        /// Map imagery for track maps with a background style, keyed by the window they cover.
        public var mapBackgrounds: [MapBackgroundRequest: MapBackground]

        public init(
            project: Project,
            location: ProjectLocation,
            sessions: [InputID: TelemetrySession],
            mediaInfo: [InputID: MediaInfo],
            mediaURLs: [InputID: URL] = [:],
            images: [InputID: LoadedImage] = [:],
            problems: [InputID: String] = [:],
            mapBackgrounds: [MapBackgroundRequest: MapBackground] = [:]
        ) {
            self.project = project
            self.location = location
            self.sessions = sessions
            self.mediaInfo = mediaInfo
            self.mediaURLs = mediaURLs
            self.images = images
            self.problems = problems
            self.mapBackgrounds = mapBackgrounds
        }
    }

    /// Reads the project file and imports every data input.
    public static func load(_ url: URL) async throws -> LoadedProject {
        let location = ProjectLocation(url)
        let project = try location.load()
        return try await load(project, location: location)
    }

    /// Imports data, prepares and probes media, and loads images. Pass `previous` to reuse the
    /// results for inputs whose source and settings have not changed (the app calls this on every
    /// edit). An input whose file is missing or unreadable is recorded in `problems` instead of
    /// failing the whole load, so the project still opens and the file can be relinked.
    public static func load(_ project: Project, location: ProjectLocation, reusing previous: LoadedProject? = nil)
        async throws
        -> LoadedProject
    {
        var loaded = LoadedProject(project: project, location: location, sessions: [:], mediaInfo: [:])
        for input in project.inputs {
            let url = location.resolve(input.source)
            let unchanged =
                previous?.project.input(input.id).map { $0.source == input.source && $0.kind == input.kind } ?? false
                && previous?.problems[input.id] == nil
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { throw LoadError.missingFile(url) }
                switch input.kind {
                case .data(let settings):
                    if unchanged, let cached = previous?.sessions[input.id] {
                        loaded.sessions[input.id] = cached
                    } else {
                        loaded.sessions[input.id] = try importData(at: url, settings: settings)
                    }
                case .video, .audio:
                    if unchanged, let cached = previous?.mediaInfo[input.id] {
                        loaded.mediaInfo[input.id] = cached
                        loaded.mediaURLs[input.id] = previous?.mediaURLs[input.id]
                    } else {
                        let playable = try await FFmpegBridge.prepare(url)
                        loaded.mediaInfo[input.id] = try await MediaProbe.probe(playable)
                        if playable != url { loaded.mediaURLs[input.id] = playable }
                    }
                case .image:
                    if unchanged, let cached = previous?.images[input.id] {
                        loaded.images[input.id] = cached
                    } else {
                        loaded.images[input.id] = try LoadedImage.load(url)
                    }
                }
            } catch {
                loaded.problems[input.id] = "\(error)"
            }
        }
        for request in RenderPlanner.mapBackgroundRequests(for: project, sessions: loaded.sessions) {
            if let cached = previous?.mapBackgrounds[request] {
                loaded.mapBackgrounds[request] = cached
            } else if let fetched = await MapSnapshotService.background(for: request) {
                loaded.mapBackgrounds[request] = fetched
            }
        }
        return loaded
    }

    public enum LoadError: Error, CustomStringConvertible {
        case missingFile(URL)
        case noPlayableVideo

        public var description: String {
            switch self {
            case .missingFile(let url): "File not found: \(url.path)"
            case .noPlayableVideo: "The project has no video input that can be opened."
            }
        }
    }

    // MARK: - Export helpers

    /// The project seconds to export for `range`, or `nil` for everything. Lap ranges use the
    /// first data input that has laps, mapped through that input's sync settings.
    public static func exportRange(_ range: ExportRange, in loaded: LoadedProject, duration: Double)
        -> ClosedRange<Double>?
    {
        switch range {
        case .whole:
            return nil
        case .span(let start, let end):
            let s = min(max(start, 0), duration)
            let e = min(max(end, s), duration)
            return e > s ? s...e : nil
        case .laps(let first, let last):
            for input in loaded.project.dataInputs {
                guard let session = loaded.sessions[input.id], !session.laps.isEmpty else { continue }
                let laps = session.laps.filter { $0.number >= min(first, last) && $0.number <= max(first, last) }
                guard let start = laps.map(\.start).min() else { return nil }
                let end = laps.compactMap { $0.end ?? session.timeRange?.upperBound }.max() ?? start
                let s = min(max(input.sync.projectTime(forInputTime: start), 0), duration)
                let e = min(max(input.sync.projectTime(forInputTime: end), s), duration)
                return e > s ? s...e : nil
            }
            return nil
        }
    }

    /// The composition to hand to the exporter: overlay-only exports drop the video layers and
    /// clear to the key colour or to transparent.
    public static func prepareForExport(_ compiled: CompiledComposition, settings: ExportSettings)
        -> CompiledComposition
    {
        switch settings.background {
        case .video: return compiled
        case .keyColor(let color): return compiled.overlayOnly(background: color)
        case .transparent: return compiled.overlayOnly(background: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0))
        }
    }

    /// Whether `compile` must rebuild the media composition (inputs or timing changed) rather than
    /// just swapping overlays and layer frames.
    public static func needsRecompile(from old: Project, to new: Project) -> Bool {
        if old.settings != new.settings || old.inputs.count != new.inputs.count { return true }
        for (a, b) in zip(old.inputs, new.inputs) {
            if a.id != b.id || a.source != b.source || a.sync != b.sync { return true }
            switch (a.kind, b.kind) {
            case (.video(let x), .video(let y)):
                // Picture settings are applied by the compositor (replan); timing and audio are not.
                if x.trim != y.trim || x.includeAudio != y.includeAudio || x.audio != y.audio { return true }
            case (.data, .data), (.image, .image), (.audio, .audio):
                if a.kind != b.kind { return true }
            default:
                return true
            }
        }
        return false
    }

    /// Rebuilds only the plan (overlays + layer frames) on an existing compiled composition.
    public static func replan(_ compiled: CompiledComposition, for loaded: LoadedProject) -> CompiledComposition {
        let project = loaded.project
        let videoInputIDs = project.inputs.filter(\.kind.isVideo).map(\.id)
        var trackIDs: [InputID: Int32] = [:]
        for (index, inputID) in videoInputIDs.enumerated() where index < compiled.trackIDs.count {
            trackIDs[inputID] = compiled.trackIDs[index]
        }
        return compiled.replacingPlans(
            timedPlans(
                for: loaded, trackIDs: trackIDs, sourceTransforms: compiled.sourceTransforms,
                duration: compiled.duration))
    }

    /// One plan per timeline cut point, with the objects resolved for that segment.
    static func timedPlans(
        for loaded: LoadedProject, trackIDs: [InputID: Int32], sourceTransforms: [Int32: CGAffineTransform],
        duration: Double
    ) -> [TimedPlan] {
        let project = loaded.project
        let cache = RenderCache()
        return project.timeline.cutPoints(duration: duration).map { start in
            let objects = project.displayObjects(at: start)
            let overlays = RenderPlanner.overlays(
                for: project, objects: objects, sessions: loaded.sessions, images: loaded.images, cache: cache,
                scriptRenderer: { params, context in ScriptedRenderer(context: context, params: params) },
                mapBackgrounds: loaded.mapBackgrounds)
            let layers = RenderPlanner.videoLayers(
                for: project, objects: objects, trackIDs: trackIDs, sourceTransforms: sourceTransforms)
            let plan = RenderPlan(
                outputWidth: project.settings.outputWidth, outputHeight: project.settings.outputHeight,
                frameRate: project.settings.frameRate, videoLayers: layers, overlays: overlays)
            return TimedPlan(start: start, plan: plan)
        }
    }

    static func importData(at url: URL, settings: DataInputSettings) throws -> TelemetrySession {
        var overrides: [String: ChannelRole] = [:]
        for (column, identifier) in settings.roleOverrides {
            if let role = ChannelRole(identifier: identifier) { overrides[column] = role }
        }
        let options = SessionBuilder.Options(
            roleOverrides: overrides,
            deriveSpeedFromPosition: settings.deriveSpeedFromPosition,
            deriveHeadingFromPosition: settings.deriveHeadingFromPosition,
            unitOverrides: settings.unitOverrides.mapValues { TelemetryUnit(parsing: $0) },
            resampleHertz: settings.resampleHertz,
            smoothingSeconds: settings.smoothingSeconds,
            calculatedFields: settings.calculatedFields.map {
                CalculatedField(name: $0.name, expression: $0.expression, unit: $0.unit)
            },
            finishLine: settings.lapLine.map {
                FinishLine(
                    latitude: $0.latitude, longitude: $0.longitude, headingDegrees: $0.headingDegrees,
                    halfWidthMeters: $0.halfWidthMeters, headingToleranceDegrees: $0.headingToleranceDegrees)
            },
            ignoreFirstCrossings: settings.lapLine?.ignoreFirstCrossings ?? 0)
        if let importerID = settings.importerID {
            guard let importer = FormatDetector.importers.first(where: { type(of: $0).id == importerID }) else {
                throw ImportError.unrecognisedFormat
            }
            return try importer.importSession(at: url, options: options)
        }
        return try FormatDetector.importSession(at: url, options: options)
    }

    /// Builds the composition: video inputs become tracks and layers; data objects become overlays.
    public static func compile(_ loaded: LoadedProject) async throws -> CompiledComposition {
        let project = loaded.project
        var specs: [VideoInputSpec] = []
        var specInputIDs: [InputID] = []
        for input in project.inputs {
            guard case .video(let settings) = input.kind, loaded.problems[input.id] == nil else { continue }
            specs.append(
                VideoInputSpec(
                    url: loaded.mediaURLs[input.id] ?? loaded.location.resolve(input.source), sync: input.sync,
                    trim: settings.trim, frame: .full, includeAudio: settings.includeAudio, audio: settings.audio))
            specInputIDs.append(input.id)
        }
        guard !specs.isEmpty else { throw LoadError.noPlayableVideo }
        let compiled = try await CompositionBuilder.build(
            videos: specs, overlays: [], outputWidth: project.settings.outputWidth,
            outputHeight: project.settings.outputHeight, frameRate: project.settings.frameRate,
            duration: project.settings.duration)
        // Replace the builder's one-layer-per-input default with the project's objects per segment.
        var trackIDs: [InputID: Int32] = [:]
        for (index, inputID) in specInputIDs.enumerated() where index < compiled.trackIDs.count {
            trackIDs[inputID] = compiled.trackIDs[index]
        }
        return compiled.replacingPlans(
            timedPlans(
                for: loaded, trackIDs: trackIDs, sourceTransforms: compiled.sourceTransforms,
                duration: compiled.duration))
    }
}
