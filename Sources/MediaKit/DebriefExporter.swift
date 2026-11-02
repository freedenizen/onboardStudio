import AVFoundation
import Foundation
import ProjectModel
import RenderKit

/// Writes a `DebriefPlan` as one video (#327): each card and each corner clip is encoded with the
/// project's export settings into a temporary folder, then the pieces are joined without
/// re-encoding. Progress is weighted by how long each piece plays.
public enum DebriefExporter {
    public static func export(
        _ compiled: CompiledComposition, project: Project, plan: DebriefPlan, settings: ExportSettings,
        to outputURL: URL
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        AsyncThrowingStream { continuation in
            let job = DebriefJob(
                compiled: compiled, project: project, plan: plan, settings: settings, outputURL: outputURL,
                onProgress: { continuation.yield($0) })
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await job.run()
                    continuation.finish()
                } catch {
                    Diagnostics.exportFailed(outputURL.lastPathComponent, error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Owns the non-Sendable composition for one debrief export, as `ExportJob` does for one range,
/// and is touched only from its own detached task.
final class DebriefJob: @unchecked Sendable {
    let compiled: CompiledComposition
    let project: Project
    let plan: DebriefPlan
    let settings: ExportSettings
    let outputURL: URL
    let onProgress: @Sendable (ExportProgress) -> Void

    init(
        compiled: CompiledComposition, project: Project, plan: DebriefPlan, settings: ExportSettings, outputURL: URL,
        onProgress: @escaping @Sendable (ExportProgress) -> Void
    ) {
        self.compiled = compiled
        self.project = project
        self.plan = plan
        self.settings = settings
        self.outputURL = outputURL
        self.onProgress = onProgress
    }

    func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Debrief-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ext = settings.fileExtension
        let total = max(plan.duration, 0.001)
        var done = 0.0
        var frames = 0
        var pieces: [URL] = []

        func piece(_ name: String) -> URL { folder.appending(path: "\(name).\(ext)") }
        func report(_ fraction: Double, _ current: Double) {
            onProgress(ExportProgress(fraction: min(fraction, 1), framesWritten: frames, currentTime: current))
        }

        let title = piece("00-title")
        try await CardWriter.write(plan.title, project: project, settings: settings, to: title)
        pieces.append(title)
        done += plan.title.seconds
        frames += Int(plan.title.seconds * settings.frameRate)
        report(done / total, done)
        try Task.checkCancellation()

        for (index, corner) in plan.corners.enumerated() {
            let url = piece(String(format: "%02d-corner", index + 1))
            let length = corner.range.upperBound - corner.range.lowerBound
            var written = 0
            for try await update in Exporter.export(compiled, settings: settings, range: corner.range, to: url) {
                written = update.framesWritten
                report((done + update.fraction * length) / total, done + update.fraction * length)
            }
            frames += written
            pieces.append(url)
            done += length
            try Task.checkCancellation()
        }

        let closing = piece("99-closing")
        try await CardWriter.write(plan.closing, project: project, settings: settings, to: closing)
        pieces.append(closing)
        done += plan.closing.seconds
        frames += Int(plan.closing.seconds * settings.frameRate)
        report(0.99, done)
        try Task.checkCancellation()

        try await MovieStitcher.concatenate(pieces, fileType: Exporter.fileType(for: settings), to: outputURL)
        report(1, done)
    }
}

/// A card of text as a short movie: one frame drawn with the project's text objects, written for
/// as long as the card says.
enum CardWriter {
    static let background = RGBAColor(red: 0.07, green: 0.07, blue: 0.08)
    static let secondary = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.78)

    static func write(_ card: DebriefPlan.Card, project: Project, settings: ExportSettings, to url: URL) async throws {
        let frame = try render(card, project: project, settings: settings)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: Exporter.fileType(for: settings))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: Exporter.videoSettings(settings))
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: settings.width,
                kCVPixelBufferHeightKey as String: settings.height,
            ])
        guard writer.canAdd(input) else { throw ExportError.cannotAddInput }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.cannotCreateWriter("\(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        let timescale: CMTimeScale = 600
        let count = max(Int((card.seconds * settings.frameRate).rounded()), 1)
        for index in 0..<count {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
            let time = CMTime(
                value: CMTimeValue((Double(index) * Double(timescale) / settings.frameRate).rounded()),
                timescale: timescale)
            guard adaptor.append(frame, withPresentationTime: time) else {
                throw ExportError.cannotCreateWriter("\(String(describing: writer.error))")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// The card drawn once at the export size, with the project's typeface.
    static func render(_ card: DebriefPlan.Card, project: Project, settings: ExportSettings) throws -> CVPixelBuffer {
        var cardProject = Project(settings: project.settings, displayObjects: objects(for: card, settings: settings))
        cardProject.details = project.details
        let overlays = RenderPlanner.overlays(for: cardProject, sessions: [:])
        let plan = RenderPlan(
            outputWidth: settings.width, outputHeight: settings.height, frameRate: settings.frameRate,
            videoLayers: [], overlays: overlays, background: background)
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 0)
    }

    /// The title across the top, the lines under it, each wrapped to the width.
    static func objects(for card: DebriefPlan.Card, settings: ExportSettings) -> [DisplayObject] {
        let margin = 0.08
        let width = 1 - 2 * margin
        let titleHeight = 0.13
        let lineHeight = 0.058
        let gap = 0.012
        var objects: [DisplayObject] = [
            DisplayObject(
                label: "Title", inputID: nil, frame: UnitRect(x: margin, y: 0.12, width: width, height: titleHeight),
                kind: .text(TextParams(text: card.title, fontScale: 0.62, bold: true, alignment: .leading)))
        ]
        let budget = characterBudget(width: width, lineHeight: lineHeight, fontScale: 0.6, settings: settings)
        var y = 0.12 + titleHeight + 0.05
        for line in card.lines {
            for piece in wrapped(line, budget: budget) {
                guard y + lineHeight <= 0.96 else { return objects }
                objects.append(
                    DisplayObject(
                        label: "Line", inputID: nil, frame: UnitRect(x: margin, y: y, width: width, height: lineHeight),
                        kind: .text(
                            TextParams(
                                text: piece, fontScale: 0.6, bold: false, color: secondary, alignment: .leading))))
                y += lineHeight + gap
            }
            y += gap
        }
        return objects
    }

    /// How many characters fit on a line: the text renderer sets the point size from the line's
    /// height and does not wrap, so the card wraps for it. An average glyph is about half an em.
    static func characterBudget(width: Double, lineHeight: Double, fontScale: Double, settings: ExportSettings) -> Int {
        let pointSize = Double(settings.height) * lineHeight * fontScale
        let pixels = Double(settings.width) * width - pointSize  // less the renderer's padding
        return max(Int(pixels / (pointSize * 0.52)), 12)
    }

    /// `text` broken at spaces into lines of at most `budget` characters; a single word longer
    /// than the budget stays whole.
    static func wrapped(_ text: String, budget: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= budget {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

/// Joins movies written with the same settings into one file without re-encoding.
enum MovieStitcher {
    static func concatenate(_ urls: [URL], fileType: AVFileType, to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard
            let video = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.cannotCreateWriter("no video track") }
        var audio: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            try video.insertTimeRange(range, of: source, at: cursor)
            if let sound = try await asset.loadTracks(withMediaType: .audio).first {
                if audio == nil {
                    audio = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try audio?.insertTimeRange(range, of: sound, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw ExportError.cannotCreateWriter("no passthrough export session") }
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: outputURL, as: fileType)
    }
}
