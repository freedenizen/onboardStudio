import AVFoundation
import MediaKit
import ProjectModel
import TelemetryKit

/// One stretch Watch plays (#516): a player item, the part of it that shows a piece of the corner,
/// and what that piece is.
struct WatchClip {
    let title: String
    let item: AVPlayerItem
    let range: ClosedRange<Double>
}

extension CoachingSelection {
    /// The reference was driven as one stretch of this lap's own session.
    var referenceIsThisSession: Bool {
        switch reference {
        case .sessionBest, .lap, .fastestRolling: true
        case .compositeOptimal, .otherInput, .logbook: false
        }
    }
}

extension CoachingAnalysis {
    /// "Lap 2", "Lap 4, your best lap".
    func watchTitle(_ side: CornerFootage.Side, lapNumber: Int) -> String {
        side == .lap ? "Lap \(lapNumber)" : "\(reference.label), \(referencePhrase)"
    }
}

/// A project plays the corner in its own picture, overlays and all: the preview's composition,
/// from where the data's sync and any retimes put it.
extension ProjectCoachingSource {
    func watchClips(
        for comparison: CornerComparison, analysis: CoachingAnalysis, selection: CoachingSelection
    ) async -> [WatchClip] {
        guard let editor, let compiled = editor.preview.compiled, editor.camera(for: selection.input.id) != nil
        else { return [] }
        let referenceInput: Input? =
            switch selection.reference {
            case .sessionBest, .lap, .fastestRolling: selection.input
            case .otherInput(let id, _): editor.camera(for: id) != nil ? editor.project.input(id) : nil
            case .compositeOptimal, .logbook: nil
            }
        let item = AVPlayerItem(asset: compiled.composition)
        item.videoComposition = compiled.videoComposition
        item.audioMix = compiled.audioMix
        let pieces = CornerFootage.pieces(of: comparison, in: analysis, referenceIsFootage: referenceInput != nil)
        return pieces.compactMap { piece in
            guard let input = piece.side == .lap ? selection.input : referenceInput,
                let range = CornerFootage.outputRange(
                    of: piece.sessionTimes, sync: input.sync, timeMap: compiled.timeMap)
            else { return nil }
            return WatchClip(
                title: analysis.watchTitle(piece.side, lapNumber: selection.lapNumber), item: item, range: range)
        }
    }
}

/// A logbook session plays the corner from the day's own clips, lined up by the camera's clock
/// and the logger's, as a project made from the session would line them up.
extension LogbookCoachingSource {
    func watchClips(
        for comparison: CornerComparison, analysis: CoachingAnalysis, selection: CoachingSelection
    ) async -> [WatchClip] {
        guard let session else { return [] }
        let records = LogbookModel.shared.clips(of: entry).filter { $0.recordedAt != nil }
        let recordings = records.map {
            CornerFootage.Recording(
                startEpoch: $0.recordedAt?.timeIntervalSince1970 ?? 0, duration: $0.durationSeconds ?? 0)
        }
        guard !recordings.isEmpty else { return [] }
        let pieces = CornerFootage.pieces(
            of: comparison, in: analysis, referenceIsFootage: selection.referenceIsThisSession)
        var items: [Int: AVPlayerItem] = [:]
        var clips: [WatchClip] = []
        for piece in pieces {
            guard
                let found = CornerFootage.recordingRange(
                    of: piece.sessionTimes, epoch: { session.epoch(forSessionTime: $0) }, recordings: recordings)
            else { continue }
            if items[found.recording] == nil {
                let record = records[found.recording]
                guard let first = record.resolveFile() else { continue }
                let chapters = record.chapterPaths.map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                guard let asset = try? await RecordingAsset.joined([first] + chapters) else { continue }
                items[found.recording] = AVPlayerItem(asset: asset)
            }
            guard let item = items[found.recording] else { continue }
            clips.append(
                WatchClip(
                    title: analysis.watchTitle(piece.side, lapNumber: selection.lapNumber), item: item,
                    range: found.range))
        }
        return clips
    }
}
