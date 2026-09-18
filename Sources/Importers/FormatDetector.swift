import Foundation
import TelemetryKit

/// Chooses the best importer for a file by asking every registered importer for its confidence.
public enum FormatDetector {
    public struct Candidate: Sendable {
        public let importer: any TelemetryImporter
        public let id: String
        public let displayName: String
        public let confidence: ImportConfidence
    }

    /// Every importer, in priority order for ties.
    public static let importers: [any TelemetryImporter] = [
        RaceRenderCSVImporter(),
        RaceChronoCSVImporter(),
        GPXImporter(),
        TCXImporter(),
        NMEAImporter(),
        VBOImporter(),
        GenericCSVImporter(),
    ]

    public static func candidates(for url: URL) throws -> [Candidate] {
        let sniff = try FileSniff.sniff(url)
        return importers.compactMap { importer -> Candidate? in
            let type = type(of: importer)
            let confidence = type.confidence(for: sniff)
            guard confidence > .no else { return nil }
            return Candidate(importer: importer, id: type.id, displayName: type.displayName, confidence: confidence)
        }
        .sorted { $0.confidence > $1.confidence }
    }

    /// The most confident importer, or `nil` if nothing recognises the file.
    public static func detect(_ url: URL) throws -> Candidate? {
        try candidates(for: url).first
    }

    /// Detects the format and imports the file into a session.
    public static func importSession(at url: URL, options: SessionBuilder.Options = .init()) throws -> TelemetrySession
    {
        guard let candidate = try detect(url) else { throw ImportError.unrecognisedFormat }
        var session = try candidate.importer.importSession(at: url, options: options)
        if session.info.sourceFileName == nil { session.info.sourceFileName = url.lastPathComponent }
        return session
    }
}
