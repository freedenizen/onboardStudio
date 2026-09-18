import Foundation
import Importers
import TelemetryKit

/// Telemetry a camera writes next to its video rather than inside it: DJI's `.SRT` logs, the
/// `.FIT` file a Garmin VIRB records alongside, a `.GPX` from other action cameras, and Sony's
/// `.XML` sidecar (which only carries the recording date).
public struct CompanionTelemetry: Sendable, Equatable {
    public let url: URL
    public let importerID: String
    public let displayName: String

    /// The first sidecar next to `video` that an importer recognises, trying the usual extensions
    /// (both cases) and Sony's `C0001M01.XML` naming.
    public static func find(for video: URL) -> CompanionTelemetry? {
        let base = video.deletingPathExtension()
        var candidates: [URL] = []
        for ext in ["srt", "SRT", "fit", "FIT", "gpx", "GPX", "csv", "CSV"] {
            candidates.append(base.appendingPathExtension(ext))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard let candidate = try? FormatDetector.detect(url), candidate.confidence >= .likely else { continue }
            return CompanionTelemetry(url: url, importerID: candidate.id, displayName: candidate.displayName)
        }
        return nil
    }

    /// The recording start from a Sony XML sidecar (`<CreationDate value="…"/>`), if there is one.
    public static func sonyCreationDate(for video: URL) -> Date? {
        let base = video.deletingPathExtension()
        let candidates =
            [base.appendingPathExtension("XML"), base.appendingPathExtension("xml")]
            + [base.deletingLastPathComponent().appending(path: base.lastPathComponent + "M01.XML")]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                let range = text.range(of: #"CreationDate value="([^"]+)""#, options: .regularExpression)
            else { continue }
            let match = text[range]
            guard let open = match.firstIndex(of: "\""), let close = match.lastIndex(of: "\""), open < close else {
                continue
            }
            let value = String(match[match.index(after: open)..<close])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
