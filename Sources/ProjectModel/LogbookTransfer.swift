import Foundation
import TelemetryKit

/// The logbook as something you can take with you (#350): a folder of entry files (with the data
/// files beside them when asked), read back anywhere with a merge by content hash; and the
/// sessions and laps as CSV and Markdown for spreadsheets and coaches.
public enum LogbookTransfer {
    public static let filesFolderName = "Files"

    public struct Summary: Equatable, Sendable {
        public var written = 0
        public var added = 0
        public var updated = 0
        public var skipped = 0
        public var filesCopied = 0
        /// Track days written, or added and updated on the way in (#392).
        public var days = 0
    }

    // MARK: - A folder of entries

    /// Writes `entries` as `.onboardsession` files into `folder`, their track days as
    /// `.onboardday` files (those of `days` that the entries belong to, #392), the garage beside
    /// them, and — with `includingFiles` — each entry's data file under `Files/`, so the folder
    /// is complete. A day's clips are written by path alone: the videos are not copied.
    @discardableResult
    public static func export(
        _ entries: [LogbookEntry], days: [TrackDay] = [], cars: [Car] = [], goals: [Goal] = [], to folder: URL,
        includingFiles: Bool = false
    ) throws -> Summary {
        var summary = Summary()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wanted = Set(entries.compactMap(\.trackDayID))
        for day in days where wanted.contains(day.id) {
            var written = day
            for index in written.clips.indices { written.clips[index].bookmark = nil }
            try Logbook.writeDay(
                written, to: folder.appending(path: "\(day.id.uuidString).\(Logbook.dayFileExtension)"))
            summary.days += 1
        }
        let files = folder.appending(path: filesFolderName)
        if includingFiles { try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true) }
        for entry in entries {
            var written = entry
            if includingFiles, let source = entry.resolveFile() {
                let destination = files.appending(path: Self.fileName(for: entry, source: source))
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                    summary.filesCopied += 1
                }
                written.file.path = "\(filesFolderName)/\(destination.lastPathComponent)"
                written.file.bookmark = nil
            }
            try Logbook.write(written, to: folder.appending(path: "\(entry.id.uuidString).\(Logbook.fileExtension)"))
            summary.written += 1
        }
        if !cars.isEmpty {
            try Logbook.encoder.encode(cars).write(to: folder.appending(path: Logbook.garageFileName), options: .atomic)
        }
        // The goals (#461), beside the garage.
        if !goals.isEmpty {
            try Logbook.encoder.encode(goals).write(to: folder.appending(path: Logbook.goalsFileName), options: .atomic)
        }
        return summary
    }

    /// `<hash prefix>-<name>`: unique across sessions, still recognisable in the Finder.
    static func fileName(for entry: LogbookEntry, source: URL) -> String {
        "\(entry.file.contentHash.prefix(8))-\(source.lastPathComponent)"
    }

    /// Reads a folder written by `export` (or any folder of entry files) into `logbook`: an entry
    /// whose bytes the logbook already has is skipped, or updated when the file's is newer; a
    /// data file copied under `Files/` is pointed at when the entry's own path no longer resolves;
    /// cars not yet in the garage are added. Track days arrive by id — unknown ones are added,
    /// known ones replaced when the arriving copy is newer — and an entry whose day did not come
    /// along is put on one by its date and circuit (#392).
    @discardableResult
    public static func `import`(from folder: URL, into logbook: Logbook) throws -> Summary {
        var summary = Summary()
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        summary.days = try importDays(contents, into: logbook)
        let existing = logbook.entries()
        for url in contents where url.pathExtension == Logbook.fileExtension {
            guard var entry = try? Logbook.read(from: url) else { continue }
            if entry.resolveFile() == nil {
                let beside = folder.appending(path: entry.file.path)
                if FileManager.default.fileExists(atPath: beside.path) { entry.file.path = beside.path }
            }
            if let known = existing.first(where: { $0.file.contentHash == entry.file.contentHash }) {
                guard entry.modified > known.modified else {
                    summary.skipped += 1
                    continue
                }
                entry.id = known.id
                if entry.resolveFile() == nil, let kept = known.resolveFile() {
                    entry.file.path = kept.path
                    entry.file.bookmark = known.file.bookmark
                }
                try logbook.save(entry, keepingModified: true)
                summary.updated += 1
            } else {
                try logbook.save(entry, keepingModified: true)
                summary.added += 1
            }
        }
        let garage = folder.appending(path: Logbook.garageFileName)
        if let data = try? Data(contentsOf: garage), let cars = try? Logbook.decoder.decode([Car].self, from: data) {
            var mine = logbook.cars()
            for car in cars where !mine.contains(where: { $0.name.caseInsensitiveCompare(car.name) == .orderedSame }) {
                mine.append(car)
            }
            try logbook.saveCars(mine)
        }
        // Goals arrive by id: one the logbook has stays as it is.
        let goals = folder.appending(path: Logbook.goalsFileName)
        if let data = try? Data(contentsOf: goals),
            let arriving = try? Logbook.decoder.decode([Goal].self, from: data)
        {
            let mine = logbook.goals()
            let new = arriving.filter { goal in !mine.contains { $0.id == goal.id } }
            if !new.isEmpty { try logbook.saveGoals(mine + new) }
        }
        try logbook.ensureDays()
        return summary
    }

    /// The `.onboardday` files among `urls`: unknown days added, known ones replaced when the
    /// arriving copy is newer. Returns how many were written.
    static func importDays(_ urls: [URL], into logbook: Logbook) throws -> Int {
        var written = 0
        for url in urls where url.pathExtension == Logbook.dayFileExtension {
            guard let day = try? Logbook.readDay(from: url) else { continue }
            if let known = logbook.day(id: day.id), day.modified <= known.modified { continue }
            try logbook.saveDay(day, keepingModified: true)
            written += 1
        }
        return written
    }

    // MARK: - CSV

    public static let sessionColumns = [
        "date", "day", "circuit", "car", "driver", "laps", "best", "best_lap", "optimal", "rolling", "top_speed_kmh",
        "weather", "track", "air_c", "tyres", "setup", "notes", "tags", "file",
    ]

    /// One line per session, times in seconds, speeds in km/h, dates ISO 8601; `day` is the
    /// track day's label when `days` has it (#392).
    public static func sessionsCSV(_ entries: [LogbookEntry], days: [TrackDay] = []) -> String {
        var lines = [sessionColumns.joined(separator: ",")]
        let labels = Dictionary(days.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            let cells: [String] = [
                entry.date.map(ProjectDetails.iso) ?? "", entry.trackDayID.flatMap { labels[$0] } ?? "", entry.title,
                entry.car, entry.driver,
                String(entry.completeLapCount), seconds(entry.bestLap), entry.bestLapNumber.map(String.init) ?? "",
                seconds(entry.optimalLap), seconds(entry.fastestRollingLap),
                entry.topSpeed.map { String(format: "%.1f", $0 * 3.6) } ?? "",
                entry.conditions.weather?.rawValue ?? "", entry.conditions.track?.rawValue ?? "",
                entry.conditions.ambientCelsius.map { String(format: "%.1f", $0) } ?? "", entry.conditions.tyres,
                entry.conditions.setup, entry.notes, entry.tags.joined(separator: " "), entry.file.path,
            ]
            lines.append(cells.map(quoted).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `cones` and `official` are a run's (#552): the cones it hit and the time that counts, empty
    /// for a circuit's laps and for a DNF.
    public static let lapColumns = ["date", "circuit", "car", "lap", "seconds", "complete", "cones", "official"]

    /// One line per lap of every session.
    public static func lapsCSV(_ entries: [LogbookEntry]) -> String {
        var lines = [lapColumns.joined(separator: ",")]
        for entry in entries {
            for lap in entry.laps {
                let cells = [
                    entry.date.map(ProjectDetails.iso) ?? "", entry.title, entry.car, String(lap.number),
                    seconds(lap.seconds), lap.isComplete ? "yes" : "no",
                    entry.isRuns ? String(lap.cones) : "",
                    entry.isRuns ? seconds(lap.officialSeconds(perCone: entry.perCone)) : "",
                ]
                lines.append(cells.map(quoted).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func seconds(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "" }

    /// RFC 4180: quoted when it holds a comma, a quote or a line break, quotes doubled.
    static func quoted(_ cell: String) -> String {
        guard cell.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return cell }
        return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Markdown

    /// A summary a coach can read: a table of the sessions, then each session's laps.
    public static func markdown(_ entries: [LogbookEntry], title: String = "Logbook") -> String {
        var lines = ["# \(title)", ""]
        lines.append("| Date | Circuit | Car | Laps | Best | Optimal | Rolling | Conditions |")
        lines.append("|---|---|---|---:|---:|---:|---:|---|")
        for entry in entries {
            let cells = [
                entry.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—", entry.title,
                entry.car.isEmpty ? "—" : entry.car, String(entry.completeLapCount), lapTime(entry.bestLap),
                lapTime(entry.optimalLap), lapTime(entry.fastestRollingLap),
                entry.conditions.summary.isEmpty ? "—" : entry.conditions.summary,
            ]
            let escaped = cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }
            lines.append("| " + escaped.joined(separator: " | ") + " |")
        }
        for entry in entries where !entry.laps.isEmpty {
            lines.append("")
            let when = entry.date.map { " — " + $0.formatted(date: .long, time: .omitted) } ?? ""
            lines.append("## \(entry.title)\(when)")
            if !entry.car.isEmpty || !entry.driver.isEmpty {
                lines.append("*\([entry.car, entry.driver].filter { !$0.isEmpty }.joined(separator: " · "))*")
            }
            lines.append("")
            for lap in entry.laps {
                var line = "- \(entry.isRuns ? "Run" : "Lap") \(lap.number): \(lapTime(lap.seconds))"
                // "+ 2 cones = 0:55.97" (#552): the clock, then what it counts as.
                if entry.isRuns, lap.cones > 0, let official = lap.officialSeconds(perCone: entry.perCone) {
                    line += " + \(lap.cones) \(lap.cones == 1 ? "cone" : "cones") = \(lapTime(official))"
                }
                if lap.number == entry.bestLapNumber { line += " **best**" }
                if entry.isRuns ? lap.isDNF : !lap.isComplete { line += entry.isRuns ? " (DNF)" : " (partial)" }
                lines.append(line)
            }
            if !entry.notes.isEmpty {
                lines.append("")
                lines.append(entry.notes)
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func lapTime(_ value: Double?) -> String { value.map { TimeParsing.lapTimeString($0) } ?? "—" }
}
