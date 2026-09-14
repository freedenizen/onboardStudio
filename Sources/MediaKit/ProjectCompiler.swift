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
    }

    /// Reads the project file and imports every data input.
    public static func load(_ url: URL) async throws -> LoadedProject {
        let location = ProjectLocation(url)
        let project = try location.load()
        return try await load(project, location: location)
    }

    public static func load(_ project: Project, location: ProjectLocation) async throws -> LoadedProject {
        var sessions: [InputID: TelemetrySession] = [:]
        var mediaInfo: [InputID: MediaInfo] = [:]
        for input in project.inputs {
            let url = location.resolve(input.source)
            switch input.kind {
            case .data(let settings):
                sessions[input.id] = try importData(at: url, settings: settings)
            case .video, .audio:
                mediaInfo[input.id] = try await MediaProbe.probe(url)
            case .image:
                break
            }
        }
        return LoadedProject(project: project, location: location, sessions: sessions, mediaInfo: mediaInfo)
    }

    static func importData(at url: URL, settings: DataInputSettings) throws -> TelemetrySession {
        var overrides: [String: ChannelRole] = [:]
        for (column, identifier) in settings.roleOverrides {
            if let role = ChannelRole(identifier: identifier) { overrides[column] = role }
        }
        let options = SessionBuilder.Options(
            roleOverrides: overrides, deriveSpeedFromPosition: settings.deriveSpeedFromPosition,
            deriveHeadingFromPosition: settings.deriveHeadingFromPosition)
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
                    url: loaded.location.resolve(input.source), sync: input.sync, trim: settings.trim, frame: .full,
                    includeAudio: settings.includeAudio))
            specInputIDs.append(input.id)
        }
        let cache = RenderCache()
        let overlays = RenderPlanner.overlays(for: project, sessions: loaded.sessions, cache: cache)
        var compiled = try await CompositionBuilder.build(
            videos: specs, overlays: overlays, outputWidth: project.settings.outputWidth,
            outputHeight: project.settings.outputHeight, frameRate: project.settings.frameRate,
            duration: project.settings.duration)
        // Replace the builder's one-layer-per-input default with the project's video objects.
        var trackIDs: [InputID: Int32] = [:]
        for (index, inputID) in specInputIDs.enumerated() where index < compiled.plan.videoLayers.count {
            trackIDs[inputID] = compiled.plan.videoLayers[index].trackID
        }
        let layers = RenderPlanner.videoLayers(for: project, trackIDs: trackIDs)
        compiled = compiled.replacingPlan(videoLayers: layers)
        return compiled
    }
}
