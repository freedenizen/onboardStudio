import Foundation
import ProjectModel
import TelemetryKit

/// Files that say they are from another day than the one chosen (#456). A chosen day used to take
/// every file it was given: last month's folder, or the parent of several days, went onto one day
/// and one circuit without a word. Now such a file is read and kept back, the sheet asks, and
/// `place` files it where the user said.
extension TrackDayImport {
    /// What `run` does with a file that is not from the chosen day.
    public enum Strays: Sendable {
        /// Onto the chosen day whatever the file says: the answer "add them to this day", and
        /// what `onboard logbook add --day` asks for by naming the day.
        case ontoTheDay
        /// Read and kept back — `Outcome.waiting` — until `place` is told where.
        case kept
    }

    /// A session read from its file and not yet filed: the entry as the file alone describes it —
    /// its circuit only when the trace was recognised, no car — and the driver the file names.
    struct Reading: Sendable, Equatable {
        var entry: LogbookEntry
        var fileDriver: String?
    }

    /// What is kept of a file that waits: the session as read, or the clip as probed.
    enum Kept: Sendable, Equatable {
        case session(Reading)
        case clip(ClipRecord)
    }

    /// A file read for a chosen day that is dated another day, or lies at another circuit.
    public struct Stray: Sendable, Equatable {
        public let url: URL
        /// The file's own date, when it is not the chosen day.
        public let date: Date?
        /// The circuit the file's trace lies at, when it is not the chosen day's.
        public let circuit: String?
        let kind: Kept

        public var isClip: Bool { if case .clip = kind { true } else { false } }

        /// "dated Aug 23, 2026, not this day's date": what the file says that the day does not.
        public var reason: String {
            let dated = date.map { "dated \($0.formatted(date: .abbreviated, time: .omitted))" }
            let place = circuit.map { "at \($0)" }
            switch (dated, place) {
            case (let dated?, let place?): return "\(dated) \(place), not this day's date or circuit"
            case (let dated?, nil): return "\(dated), not this day's date"
            case (nil, let place?): return "\(place), not this day's circuit"
            case (nil, nil): return "not this day's"
            }
        }

        /// "3 of these 16 files are not from Nov 9, 2026 · Sonoma Raceway.": what the sheet asks
        /// about, `count` of the `files` it read for the day labelled `day`.
        public static func headline(_ count: Int, of files: Int, day: String) -> String {
            if count == files {
                return files == 1 ? "This file is not from \(day)." : "None of these \(files) files is from \(day)."
            }
            return "\(count) of these \(files) files \(count == 1 ? "is" : "are") not from \(day)."
        }

        /// What can be done with them, under the headline.
        public static func explanation(_ count: Int) -> String {
            let (each, them, days) =
                count == 1 ? ("It says", "it", "its own day") : ("Each says", "them", "their own days")
            return "\(each) below what is different. Put \(them) on \(days), as Add Files does when no day is "
                + "chosen, or add \(them) to this day anyway: the answer for a logger or a camera whose clock was "
                + "wrong."
        }

        /// The session, if it is not `day`'s by its own account. A file with no date is not
        /// another day's, and a trace that no circuit was recognised in is not another circuit's:
        /// a log without GPS recorded that day belongs on it. A day whose circuit was typed
        /// rather than chosen from the catalogue is not compared — there is no telling.
        init?(_ reading: Reading, at url: URL, against day: TrackDay) {
            let date = reading.entry.date.flatMap { TrackDay.startOfDay($0) == day.date ? nil : $0 }
            var circuit: String?
            if let own = reading.entry.circuitID, let days = day.circuitID, own != days {
                circuit = CircuitCatalog.circuit(id: own)?.name ?? reading.entry.title
            }
            guard date != nil || circuit != nil else { return nil }
            self.url = url
            self.date = date
            self.circuit = circuit
            kind = .session(reading)
        }

        /// The clip, if its clock says another day than `day`.
        init?(_ clip: ClipRecord, at url: URL, against day: TrackDay) {
            guard let recorded = clip.recordedAt, TrackDay.startOfDay(recorded) != day.date else { return nil }
            self.url = url
            date = recorded
            circuit = nil
            kind = .clip(clip)
        }
    }

    /// Files the kept-back files now that the user has said where: onto `day` whatever they say,
    /// or — with no day — each onto the day its own date and circuit say, as `run` does when no
    /// day is chosen. Nothing is read again except a clip's own GPS, when no session is its.
    public static func place(
        _ strays: [Stray], onto day: TrackDay?, into logbook: Logbook, tracks: TrackLibrary? = nil,
        car: String? = nil, driver: String? = nil
    ) -> [Report] {
        let batch = Batch(tracks: tracks, car: car, driver: driver, day: day)
        var reports: [Report] = []
        // The sessions before the clips, as `run` has them, so a clip and its log pair up.
        for stray in strays {
            guard case .session(let reading) = stray.kind else { continue }
            // The same bytes filed since they were read — the file given twice — are not filed again.
            var filed: Filed
            if let existing = logbook.entry(forContentHash: reading.entry.file.contentHash) {
                filed = Filed(outcome: .alreadyThere(existing))
            } else {
                filed = file(reading, into: logbook, batch: batch)
            }
            reports.append(report(filed, for: stray.url, chosen: day, logbook: logbook))
        }
        for stray in strays {
            guard case .clip(let clip) = stray.kind else { continue }
            var outcome: Outcome
            if let known = knownClip(clip, in: logbook) {
                outcome = .clipAlreadyThere(known)
            } else {
                do {
                    outcome = try fileClip(clip, first: stray.url, into: logbook, batch: batch)
                } catch {
                    outcome = .failed(error.localizedDescription)
                }
            }
            reports.append(report(Filed(outcome: outcome), for: stray.url, chosen: day, logbook: logbook))
        }
        return reports
    }

    /// The clip already on a day of the logbook, known by its fingerprint.
    static func knownClip(_ clip: ClipRecord, in logbook: Logbook) -> ClipRecord? {
        logbook.days().lazy.compactMap { $0.clips.first { $0.fingerprint == clip.fingerprint } }.first
    }

    /// A camera recording onto its day (#394): the chosen one, else the day its clock says.
    /// Matched against the day's sessions; a clip with GPS that matches none is read as a session
    /// of its own first, as it was before days existed, and is then the picture of that session.
    static func fileClip(_ record: ClipRecord, first: URL, into logbook: Logbook, batch: Batch) throws -> Outcome {
        var clip = record
        var day: TrackDay
        if let chosen = batch.day {
            day = logbook.day(id: chosen.id) ?? chosen
        } else {
            // The day the clock says, among the days with sessions then; else one of its own.
            day = try logbook.day(on: clip.recordedAt ?? Date(), car: batch.car ?? "", driver: batch.driver ?? "")
        }
        var sessions = logbook.sessions(of: day)
        var matched = ClipMatcher.match(clip, to: sessions)
        // The day is settled by now, so the clip's own session is not asked about again.
        var onDay = batch
        onDay.day = day
        onDay.strays = .ontoTheDay
        if matched == nil, clip.hasGPS, case .added(let own) = importOne(first, into: logbook, batch: onDay).outcome {
            matched = (own.id, .clock)
            sessions.append(own)
        }
        clip.sessionID = matched?.id
        clip.matchedBy = matched?.by
        day = logbook.day(id: day.id) ?? day
        day.clips.append(clip)
        try logbook.saveDay(day)
        return .clip(clip, session: matched.flatMap { id, _ in sessions.first { $0.id == id } })
    }

    /// Files a session as read: onto the batch's day — with its circuit when the file has none,
    /// its car, its driver and its conditions — else onto the day its own date and circuit say.
    static func file(_ reading: Reading, into logbook: Logbook, batch: Batch) -> Filed {
        do {
            var entry = reading.entry
            let day = batch.day
            var tookDayCircuit = entry.circuitID == nil && day?.circuitID != nil
            if entry.circuitID == nil { entry.circuitID = day?.circuitID }
            // A day whose circuit was typed lends its name the same way (#455): the session was
            // listed under a circuit named after its file, on a day that said where it was.
            if LogbookFilter.venueKey(of: entry).isEmpty, let name = day?.trackName, !name.isEmpty {
                entry.trackName = name
                tookDayCircuit = true
            }
            let previous = entry.circuitID.flatMap { id in logbook.entries().first { $0.circuitID == id } }
            let dayCar = day.flatMap { $0.car.isEmpty ? nil : $0.car }
            let dayDriver = day.flatMap { $0.driver.isEmpty ? nil : $0.driver }
            entry.car = batch.car ?? dayCar ?? previous?.car ?? ""
            entry.driver = batch.driver ?? dayDriver ?? reading.fileDriver ?? previous?.driver ?? ""
            // The same drive from another file — RaceChrono's CSV beside its .rcz — is not a second
            // session (#465). Before the day, so a refused file makes no day either.
            if let twin = logbook.entry(sameSessionAs: entry) { return Filed(outcome: .sameSession(twin)) }
            if let day {
                // Onto the chosen day, with its conditions as the session's to begin with.
                entry.trackDayID = day.id
                if entry.conditions.isEmpty { entry.conditions = day.conditions }
            } else {
                let found = try logbook.assignDay(to: &entry)
                // A day that says what was driven says it for a session that joins it later (#489),
                // rather than the car of whichever session at the circuit came before, or none.
                if batch.car == nil, !found.car.isEmpty { entry.car = found.car }
                if batch.driver == nil, reading.fileDriver == nil, !found.driver.isEmpty { entry.driver = found.driver }
            }
            try logbook.save(entry)
            return Filed(outcome: .added(entry), tookDayCircuit: tookDayCircuit)
        } catch {
            return Filed(outcome: .failed(error.localizedDescription))
        }
    }
}
