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
        /// Playable URLs of the following clips of a sequence, per video input.
        public var clipURLs: [InputID: [URL]] = [:]
        /// Where each file of a multi-file recording falls on its input's media timeline. Empty
        /// for single-file inputs, so callers can treat "no chapters" as "nothing to show".
        public var chapters: [InputID: [ChapterSpan]] = [:]
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
                        loaded.clipURLs[input.id] = previous?.clipURLs[input.id]
                        loaded.chapters[input.id] = previous?.chapters[input.id]
                    } else {
                        let playable = try await FFmpegBridge.prepare(url)
                        var info = try await MediaProbe.probe(playable)
                        if playable != url { loaded.mediaURLs[input.id] = playable }
                        if case .video(let settings) = input.kind, !settings.clips.isEmpty {
                            let clips = try await loadClips(settings.clips, location: location)
                            loaded.chapters[input.id] = ChapterSpan.layout(
                                firstName: input.source.displayName, firstDuration: info.duration,
                                clips: settings.clips, playedDurations: clips.played)
                            info.duration += clips.duration
                            loaded.clipURLs[input.id] = clips.urls
                        }
                        loaded.mediaInfo[input.id] = info
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

    /// Prepares and probes the following clips of a sequence: the summed duration is added to the
    /// first file's info (everything else, orientation included, comes from the first file).
    /// The result of preparing a sequence's following clips.
    struct LoadedClips {
        /// Playable URL per clip, in order.
        var urls: [URL] = []
        /// Seconds the clips add to the input, gaps included.
        var duration: Double = 0
        /// Seconds of each clip's file that actually play, after its own trim.
        var played: [Double] = []
    }

    static func loadClips(_ clips: [VideoClip], location: ProjectLocation) async throws -> LoadedClips {
        var result = LoadedClips()
        for clip in clips {
            let clipURL = location.resolve(clip.source)
            guard FileManager.default.fileExists(atPath: clipURL.path) else { throw LoadError.missingFile(clipURL) }
            let playable = try await FFmpegBridge.prepare(clipURL)
            let full = try await MediaProbe.probe(playable).duration
            let clipPlayed = min(clip.trim.end ?? full, full) - min(max(clip.trim.start ?? 0, 0), full)
            result.duration += max(0, clip.gapBefore) + clip.sequenceDuration(played: clipPlayed)
            result.played.append(max(0, clipPlayed))
            result.urls.append(playable)
        }
        return result
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

    /// Whether `compile` must rebuild the media composition (inputs or timing changed) rather than
    /// just swapping overlays and layer frames.
    public static func needsRecompile(from old: Project, to new: Project) -> Bool {
        if old.settings.withoutFraming != new.settings.withoutFraming || old.inputs.count != new.inputs.count {
            return true
        }
        for (a, b) in zip(old.inputs, new.inputs) {
            if a.id != b.id || a.source != b.source || a.sync != b.sync { return true }
            switch (a.kind, b.kind) {
            case (.video(let x), .video(let y)):
                // Picture settings are applied by the compositor (replan); timing and audio are not.
                if x.trim != y.trim || x.includeAudio != y.includeAudio || x.audio != y.audio || x.clips != y.clips {
                    return true
                }
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
                for: loaded, trackIDs: trackIDs, sourceTransforms: { compiled.sourceTransforms(at: $0) },
                orientationChanges: compiled.orientationChangeTimes, duration: compiled.duration))
    }

    /// One plan per timeline cut point, with the objects resolved for that segment.
    static func timedPlans(
        for loaded: LoadedProject, trackIDs: [InputID: Int32],
        sourceTransforms: @escaping (Double) -> [Int32: CGAffineTransform], orientationChanges: [Double] = [],
        duration: Double
    ) -> [TimedPlan] {
        let project = loaded.project
        let cache = RenderCache()
        // A plan per timeline cut and per orientation change (a chapter shot the other way up).
        let cuts = Set(project.timeline.cutPoints(duration: duration) + orientationChanges.filter { $0 < duration })
        return cuts.sorted().map { start in
            let objects = project.displayObjects(at: start)
            let sourceTransforms = sourceTransforms(start)
            let overlays = RenderPlanner.overlays(
                for: project, objects: objects, sessions: loaded.sessions, images: loaded.images, cache: cache,
                scriptRenderer: { params, context in ScriptedRenderer(context: context, params: params) },
                mapBackgrounds: loaded.mapBackgrounds)
            let layers = RenderPlanner.videoLayers(
                for: project, objects: objects, trackIDs: trackIDs, sourceTransforms: sourceTransforms)
            let plan = RenderPlan(
                outputWidth: project.settings.outputWidth, outputHeight: project.settings.outputHeight,
                frameRate: project.settings.frameRate, videoLayers: layers, overlays: overlays,
                overlayOpacity: project.settings.overlayOpacity)
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
            ignoreFirstCrossings: settings.lapLine?.ignoreFirstCrossings ?? 0,
            sectorMode: sectorMode(settings.sectors),
            trimStart: settings.trim.start, trimEnd: settings.trim.end)
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
                    url: loaded.mediaURLs[input.id] ?? loaded.location.resolve(input.source),
                    clips: settings.clips.enumerated().map { index, clip in
                        ClipSpec(
                            url: loaded.clipURLs[input.id]?[index] ?? loaded.location.resolve(clip.source),
                            trim: clip.trim, gapBefore: clip.gapBefore, speed: clip.speed)
                    },
                    sync: input.sync, trim: settings.trim, frame: .full, includeAudio: settings.includeAudio,
                    audio: settings.audio))
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
                for: loaded, trackIDs: trackIDs, sourceTransforms: { compiled.sourceTransforms(at: $0) },
                orientationChanges: compiled.orientationChangeTimes, duration: compiled.duration))
    }
}

extension ProjectCompiler.LoadedProject {
    /// Identifier, name and value range of every channel of every loaded data input.
    public var channelSummaries: [InputID: [ChannelSummary]] {
        sessions.mapValues { session in
            // Measuring the turn direction costs a correlation per channel, so only channels that
            // could plausibly carry a steering angle or a lateral acceleration are measured.
            session.orderedChannels.map { channel in
                ChannelSummary(
                    identifier: channel.role.identifier, name: channel.name, minValue: channel.minValue,
                    maxValue: channel.maxValue,
                    rightTurnCorrelation: Self.turnsWith(channel) == true
                        ? TurnDirection.reading(for: channel, in: session)?.correlation : nil)
            }
        }
    }

    /// Whether a channel is worth measuring a turn direction for: the lateral acceleration role,
    /// or anything whose name looks like a steering angle.
    static func turnsWith(_ channel: Channel) -> Bool {
        if channel.role == .lateralG { return true }
        let words = (channel.role.identifier + " " + channel.name).lowercased()
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.contains { $0.hasPrefix("steer") || $0 == "swa" }
    }
}

extension ProjectCompiler {
    /// The project's sector settings as TelemetryKit understands them.
    static func sectorMode(_ spec: SectorSpec) -> SectorMode {
        switch spec.mode {
        case .equalDistance: .equalDistance(count: spec.count)
        case .cornerAware: .cornerAware(count: spec.count)
        case .manual:
            .manual(
                lines: spec.lines.map {
                    FinishLine(
                        latitude: $0.latitude, longitude: $0.longitude, headingDegrees: $0.headingDegrees,
                        halfWidthMeters: $0.halfWidthMeters, headingToleranceDegrees: $0.headingToleranceDegrees)
                })
        }
    }
}
