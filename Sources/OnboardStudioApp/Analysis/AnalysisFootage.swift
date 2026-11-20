import AVFoundation
import MediaKit
import ProjectModel
import TelemetryKit

/// Where a lap's picture is (#556): a player item, and the item's time for a time of the lap's session.
struct AnalysisFootage {
    let item: AVPlayerItem
    /// Seconds into `item` for a session time; `nil` outside the picture.
    let time: (Double) -> Double?
}

extension LapAnalysisModel {
    /// The picture of every chosen lap that has one: in a project, its own composition, overlays
    /// and all, from where the data's sync and any retimes put it; for a logbook session, the day's
    /// clip that the camera's clock puts the lap in, as Coaching's Watch finds it.
    func loadFootage(for picks: [ReplayPick]) async -> [Int: AnalysisFootage] {
        var found: [Int: AnalysisFootage] = [:]
        var projectItem: AVPlayerItem?
        for (index, pick) in picks.enumerated() {
            guard let session = pick.session, let lap = session.laps.first(where: { $0.number == pick.number }) else {
                continue
            }
            let group = groups.first { $0.id == pick.groupID }
            if let entry = group?.entry {
                if let footage = await Self.clipFootage(of: entry, session: session, lap: lap) {
                    found[index] = footage
                }
            } else if let editor, let compiled = editor.preview.compiled,
                let input = editor.project.dataInputs.first(where: { $0.id.rawValue.uuidString == pick.groupID }),
                editor.camera(for: input.id) != nil
            {
                let item =
                    projectItem
                    ?? {
                        let item = AVPlayerItem(asset: compiled.composition)
                        item.videoComposition = compiled.videoComposition
                        item.audioMix = compiled.audioMix
                        return item
                    }()
                projectItem = item
                let sync = input.sync
                let timeMap = compiled.timeMap
                found[index] = AnalysisFootage(item: item) { t in
                    CornerFootage.outputRange(of: t...t, sync: sync, timeMap: timeMap)?.lowerBound
                }
            }
        }
        return found
    }

    /// The day's clip a logbook lap was filmed in, by the camera's clock and the logger's.
    private static func clipFootage(of entry: LogbookEntry, session: TelemetrySession, lap: Lap) async
        -> AnalysisFootage?
    {
        let records = LogbookModel.shared.clips(of: entry).filter { $0.recordedAt != nil }
        let recordings = records.map {
            CornerFootage.Recording(
                startEpoch: $0.recordedAt?.timeIntervalSince1970 ?? 0, duration: $0.durationSeconds ?? 0)
        }
        guard let end = lap.end,
            let found = CornerFootage.recordingRange(
                of: lap.start...end, epoch: { session.epoch(forSessionTime: $0) }, recordings: recordings),
            let first = records[found.recording].resolveFile()
        else { return nil }
        let record = records[found.recording]
        let chapters = record.chapterPaths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let asset = try? await RecordingAsset.joined([first] + chapters) else { return nil }
        let recording = recordings[found.recording]
        return AnalysisFootage(item: AVPlayerItem(asset: asset)) { t in
            guard let epoch = session.epoch(forSessionTime: t) else { return nil }
            let seconds = epoch - recording.startEpoch
            return (0...recording.duration).contains(seconds) ? seconds : nil
        }
    }
}

/// The picture panel's player (#556): it shows one lap's frame at the cursor, and plays from there
/// with the cursor following.
@MainActor @Observable final class AnalysisPicture {
    let player = AVPlayer()
    /// The trace whose picture is shown.
    var trace = 0
    private(set) var isPlaying = false
    private var clock: Task<Void, Never>?

    /// The frame of `trace`'s lap at the cursor, when not playing.
    func show(_ footage: AnalysisFootage, at sessionTime: Double) {
        guard !isPlaying, let seconds = footage.time(sessionTime) else { return }
        if player.currentItem !== footage.item { player.replaceCurrentItem(with: footage.item) }
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance
        )
    }

    /// Plays from the cursor; `advance` is told each session time that passes, until it says stop.
    func play(_ footage: AnalysisFootage, from sessionTime: Double, advance: @escaping (Double) -> Bool) {
        stop()
        show(footage, at: sessionTime)
        isPlaying = true
        player.play()
        let started = Date()
        clock = Task { @MainActor [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                if !advance(sessionTime + Date().timeIntervalSince(started)) { self.stop() }
            }
        }
    }

    func stop() {
        isPlaying = false
        clock?.cancel()
        clock = nil
        player.pause()
    }
}
