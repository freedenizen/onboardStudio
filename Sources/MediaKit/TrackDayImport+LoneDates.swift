import Foundation
import ProjectModel

/// Files added with no day chosen, where one is dated away from the rest (#655). Each file went
/// on the day its own date said: a recording from a camera whose clock was wrong became a session
/// on a track day of its own, the session it filmed was left with no video, and no line said that
/// one file of twenty was dated differently. Such a file now waits, and the sheet asks — as it
/// does for a file that is not from a day chosen first (#456).
extension TrackDayImport {
    /// The files of one batch as they are read. A file is filed once a second file of the batch
    /// shares its calendar day, so a day's folder still goes in file by file; the first of each
    /// day waits for that second. What is still alone at the end is asked about — when every
    /// other dated file was of one day, so there is a day it may belong to — or else filed on
    /// its own day unasked, as a folder of several days always was.
    struct Apart {
        let logbook: Logbook
        let batch: Batch
        var reports: [Report?]
        /// The dated files read so far on each calendar day.
        private var seen: [Date: Int] = [:]
        /// The first file of a day, with its place in the list, until a second comes.
        private var alone: [Date: (index: Int, stray: Stray)] = [:]
        /// The days the logbook had before these files: a file dated one of them is that day's.
        private let daysBefore: Set<Date>

        init(logbook: Logbook, batch: Batch, count: Int) {
            self.logbook = logbook
            self.batch = batch
            reports = Array(repeating: nil, count: count)
            daysBefore = Set(logbook.days().map(\.date))
        }

        /// A file read: filed now, or kept as the first of its day.
        mutating func take(_ kind: Kept, dated date: Date?, at url: URL, index: Int) {
            let stray = Stray(url: url, date: date, kind: kind)
            // A drive the logbook has from another file is that, not a file to ask about (#465).
            if case .session(let reading) = kind, let twin = logbook.entry(sameSessionAs: reading.entry) {
                reports[index] = report(Filed(outcome: .sameSession(twin)), for: url, chosen: nil, logbook: logbook)
                return
            }
            guard let date else {
                reports[index] = file(stray)
                return
            }
            let day = TrackDay.startOfDay(date)
            let before = seen[day, default: 0]
            seen[day] = before + 1
            if before == 0, !daysBefore.contains(day) {
                alone[day] = (index, stray)
                return
            }
            // The one that waited first: a session is in before the recording that filmed it.
            if let first = alone.removeValue(forKey: day) { reports[first.index] = file(first.stray) }
            reports[index] = file(stray)
        }

        /// The lines, with what is still alone asked about or filed.
        mutating func finish() -> [Report] {
            let shared = seen.filter { $0.value > 1 }.map(\.key)
            let rest = shared.count == 1 ? day(of: shared[0]) : nil
            for lone in alone.values.sorted(by: { $0.index < $1.index }) {
                if let rest {
                    let asked = Stray(url: lone.stray.url, date: lone.stray.date, kind: lone.stray.kind, rest: rest)
                    reports[lone.index] = Report(url: asked.url, outcome: .waiting(asked))
                } else {
                    reports[lone.index] = file(lone.stray)
                }
            }
            alone = [:]
            return reports.compactMap { $0 }
        }

        /// Onto the day its own date and circuit say.
        private func file(_ stray: Stray) -> Report? {
            place([stray], onto: nil, into: logbook, tracks: batch.tracks, car: batch.car, driver: batch.driver).first
        }

        /// The track day most of the batch's sessions of that date went on; a day of that date.
        private func day(of date: Date) -> TrackDay? {
            var counts: [UUID: Int] = [:]
            for report in reports {
                guard case .added(let entry)? = report?.outcome, let id = entry.trackDayID,
                    entry.date.map(TrackDay.startOfDay) == date
                else { continue }
                counts[id, default: 0] += 1
            }
            let days = logbook.days().filter { $0.date == date }
            let most = counts.max { $0.value < $1.value }?.key
            return days.first { $0.id == most } ?? days.first
        }
    }

    /// `run` with no day chosen and files of another day kept back.
    static func runApart(
        telemetry: [URL], clips: [[URL]], into logbook: Logbook, batch: Batch,
        progress: @Sendable (Int, Int, URL) -> Void
    ) async -> [Report] {
        let count = telemetry.count + clips.count
        var apart = Apart(logbook: logbook, batch: batch, count: count)
        for (index, url) in telemetry.enumerated() {
            progress(index, count, url)
            switch read(url, in: logbook, batch: batch) {
            case .done(let filed): apart.reports[index] = report(filed, for: url, chosen: nil, logbook: logbook)
            case .read(let reading): apart.take(.session(reading), dated: reading.entry.date, at: url, index: index)
            }
            await Task.yield()
        }
        // The clips after the sessions, so a clip and its log in one batch pair up (#394).
        for (offset, group) in clips.enumerated() {
            guard let first = group.first else { continue }
            let index = telemetry.count + offset
            progress(index, count, first)
            switch await probe(first, chapters: Array(group.dropFirst()), in: logbook) {
            case .done(let filed): apart.reports[index] = report(filed, for: first, chosen: nil, logbook: logbook)
            case .read(let clip): apart.take(.clip(clip), dated: clip.recordedAt, at: first, index: index)
            }
        }
        return apart.finish()
    }
}
