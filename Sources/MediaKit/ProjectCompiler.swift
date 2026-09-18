import AVFoundation
import Foundation
import Importers
import ProjectModel
import RenderKit
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

        public init(
            project: Project,
            location: ProjectLocation,
            sessions: [InputID: TelemetrySession],
            mediaInfo: [InputID: MediaInfo],
            mediaURLs: [InputID: URL] = [:],
            images: [InputID: LoadedImage] = [:]
        ) {
            self.project = project
            self.location = location
            self.sessions = sessions
            self.mediaInfo = mediaInfo
            self.mediaURLs = mediaURLs
            self.images = images
        }
    }

    /// Reads the project file and imports every data input.
    public static func load(_ url: URL) async throws -> LoadedProject {
        let location = ProjectLocation(url)
        let project = try location.load()
        return try await load(project, location: location)
    }

    /// Imports data and probes media. Pass `previous` to reuse sessions/media info for inputs whose
    /// source and settings have not changed (the app calls this on every edit).
    public static func load(_ project: Project, location: ProjectLocation, reusing previous: LoadedProject? = nil)
        async throws
        -> LoadedProject
    {
        var sessions: [InputID: TelemetrySession] = [:]
        var mediaInfo: [InputID: MediaInfo] = [:]
        for input in project.inputs {
            let url = location.resolve(input.source)
            let unchanged =
                previous?.project.input(input.id).map { $0.source == input.source && $0.kind == input.kind } ?? false
            switch input.kind {
            case .data(let settings):
                if unchanged, let cached = previous?.sessions[input.id] {
                    sessions[input.id] = cached
                } else {
                    sessions[input.id] = try importData(at: url, settings: settings)
                }
            case .video, .audio:
                if unchanged, let cached = previous?.mediaInfo[input.id] {
                    mediaInfo[input.id] = cached
                } else {
                    mediaInfo[input.id] = try await MediaProbe.probe(url)
                }
            case .image:
                break
            }
        }
        return LoadedProject(project: project, location: location, sessions: sessions, mediaInfo: mediaInfo)
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
        let overlays = RenderPlanner.overlays(
            for: project, sessions: loaded.sessions, images: loaded.images, cache: RenderCache())
        // The source rotation lives on the existing layers; a replan must keep it.
        let sourceTransforms = Dictionary(
            compiled.plan.videoLayers.map { ($0.trackID, $0.sourceTransform) }, uniquingKeysWith: { first, _ in first })
        let layers = RenderPlanner.videoLayers(for: project, trackIDs: trackIDs, sourceTransforms: sourceTransforms)
        let plan = RenderPlan(
            outputWidth: project.settings.outputWidth, outputHeight: project.settings.outputHeight,
            frameRate: project.settings.frameRate, videoLayers: layers, overlays: overlays)
        return compiled.replacingPlan(plan)
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
            guard case .video(let settings) = input.kind else { continue }
            specs.append(
                VideoInputSpec(
                    url: loaded.mediaURLs[input.id] ?? loaded.location.resolve(input.source), sync: input.sync,
                    trim: settings.trim, frame: .full, includeAudio: settings.includeAudio, audio: settings.audio))
            specInputIDs.append(input.id)
        }
        let cache = RenderCache()
        let overlays = RenderPlanner.overlays(
            for: project, sessions: loaded.sessions, images: loaded.images, cache: cache)
        var compiled = try await CompositionBuilder.build(
            videos: specs, overlays: overlays, outputWidth: project.settings.outputWidth,
            outputHeight: project.settings.outputHeight, frameRate: project.settings.frameRate,
            duration: project.settings.duration)
        // Replace the builder's one-layer-per-input default with the project's video objects.
        var trackIDs: [InputID: Int32] = [:]
        for (index, inputID) in specInputIDs.enumerated() where index < compiled.trackIDs.count {
            trackIDs[inputID] = compiled.trackIDs[index]
        }
        let sourceTransforms = Dictionary(
            uniqueKeysWithValues: compiled.plan.videoLayers.map { ($0.trackID, $0.sourceTransform) })
        let layers = RenderPlanner.videoLayers(for: project, trackIDs: trackIDs, sourceTransforms: sourceTransforms)
        compiled = compiled.replacingPlan(videoLayers: layers)
        return compiled
    }
}
