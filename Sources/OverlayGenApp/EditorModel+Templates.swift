import Foundation
import Importers
import MediaKit
import ProjectModel

/// Templates and media relinking.
extension EditorModel {
    // MARK: - Templates and relinking

    func apply(_ template: ProjectTemplate) {
        edit("Apply Template \(template.name)") { template.apply(to: &$0) }
        selectedObjectID = nil
        selectedSegmentID = nil
    }

    func applyTemplate(at url: URL) {
        do { apply(try TemplateStore.load(url)) } catch { errorMessage = "\(error)" }
    }

    func importTemplate() {
        guard let url = OpenPanels.chooseTemplate() else { return }
        applyTemplate(at: url)
    }

    func saveAsTemplate() {
        let suggested = fileURL?.deletingPathExtension().lastPathComponent ?? "My Template"
        guard let name = OpenPanels.askTemplateName(default: suggested) else { return }
        do {
            let url = try TemplateStore.save(ProjectTemplate(name: name, project: project), name: name)
            statusMessage = "Saved template \(url.lastPathComponent)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - Embedded telemetry and timestamp sync

    /// Adds the GoPro telemetry embedded in a video as a data input that follows the video.
    func useEmbeddedTelemetry(of videoID: InputID) {
        guard let video = project.input(videoID) else { return }
        let input = Input(
            label: "\(video.label) GPS", source: video.source,
            kind: .data(DataInputSettings(importerID: GoProImporter.id)), sync: video.sync)
        edit("Use Embedded GPS") { $0.inputs.append(input) }
        selectedInputID = input.id
        selectedObjectID = nil
        statusMessage = "Added the telemetry embedded in \(video.label)."
    }

    /// The video's recording start on the wall clock, from its GPS clock or creation date.
    func recordingStart(of video: Input) -> (epoch: Double, source: String)? {
        guard let info = loaded?.mediaInfo[video.id] else { return nil }
        let url = loaded?.mediaURLs[video.id] ?? location.resolve(video.source)
        return TimestampSync.recordingStart(of: url, info: info)
    }

    /// Sync settings that line `dataID` up with the first video by timestamps, if both carry a clock.
    func suggestedSync(for dataID: InputID) -> TimestampSync.Suggestion? {
        guard let session = sessions[dataID], session.hasAbsoluteTime, let video = project.videoInputs.first,
            let start = recordingStart(of: video)
        else { return nil }
        return TimestampSync.suggest(
            data: session, video: video.sync, videoStartEpoch: start.epoch, videoClock: start.source)
    }

    /// Applies the timestamp-based sync to a data input.
    func autoSync(_ dataID: InputID) {
        guard let suggestion = suggestedSync(for: dataID) else {
            errorMessage = "Timestamps are missing: the data file or the video has no usable clock."
            return
        }
        updateInput(dataID, name: "Auto-Sync from Timestamps") { $0.sync = suggestion.sync }
        statusMessage = "Synced from timestamps using the \(suggestion.videoClock)."
    }

    /// Points a missing or unreadable input at a new file.
    func relink(_ id: InputID) {
        guard let input = project.input(id) else { return }
        let url: URL? =
            switch input.kind {
            case .video, .audio: OpenPanels.chooseVideo()
            case .image: OpenPanels.chooseImage()
            case .data: OpenPanels.chooseData()
            }
        guard let url else { return }
        updateInput(id, name: "Relink Input") { $0.source = MediaReference.make(for: url, relativeTo: fileURL) }
    }
}
