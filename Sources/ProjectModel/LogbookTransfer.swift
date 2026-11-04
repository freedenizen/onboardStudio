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
    }

    // MARK: - A folder of entries

    /// Writes `entries` as `.onboardsession` files into `folder`, the garage beside them, and —
    /// with `includingFiles` — each entry's data file under `Files/`, so the folder is complete.
    @discardableResult
    public static func export(
        _ entries: [LogbookEntry], cars: [Car] = [], to folder: URL, includingFiles: Bool = false
    ) throws -> Summary {
        var summary = Summary()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
        return summary
    }

    /// `<hash prefix>-<name>`: unique across sessions, still recognisable in the Finder.
    static func fileName(for entry: LogbookEntry, source: URL) -> String {
        "\(entry.file.contentHash.prefix(8))-\(source.lastPathComponent)"
    }

    /// Reads a folder written by `export` (or any folder of entry files) into `logbook`: an entry
    /// whose bytes the logbook already has is skipped, or updated when the file's is newer; a
    /// data file copied under `Files/` is pointed at when the entry's own path no longer resolves;
    /// cars not yet in the garage are added.
    @discardableResult
    public static func `import`(from folder: URL, into logbook: Logbook) throws -> Summary {
        var summary = Summary()
        let contents = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
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
        return summary
    }

    // MARK: - CSV

    public static let sessionColumns = [
        "date", "circuit", "car", "driver", "laps", "best", "best_lap", "optimal", "rolling", "top_speed_kmh",
        "weather", "track", "air_c", "tyres", "setup", "notes", "tags", "file",
    ]

    /// One line per session, times in seconds, speeds in km/h, dates ISO 8601.
    public static func sessionsCSV(_ entries: [LogbookEntry]) -> String {
        var lines = [sessionColumns.joined(separator: ",")]
        for entry in entries {
            let cells: [String] = [
                entry.date.map(ProjectDetails.iso) ?? "", entry.title, entry.car, entry.driver,
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

    public static let lapColumns = ["date", "circuit", "car", "lap", "seconds", "complete"]

    /// One line per lap of every session.
    public static func lapsCSV(_ entries: [LogbookEntry]) -> String {
        var lines = [lapColumns.joined(separator: ",")]
        for entry in entries {
            for lap in entry.laps {
                let cells = [
                    entry.date.map(ProjectDetails.iso) ?? "", entry.title, entry.car, String(lap.number),
                    seconds(lap.seconds), lap.isComplete ? "yes" : "no",
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
                var line = "- Lap \(lap.number): \(lapTime(lap.seconds))"
                if lap.number == entry.bestLapNumber { line += " **best**" }
                if !lap.isComplete { line += " (partial)" }
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
