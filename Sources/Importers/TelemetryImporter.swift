import Foundation
import TelemetryKit

public enum ImportError: Error, Equatable, CustomStringConvertible {
    case unreadableText
    case unrecognisedFormat
    case missingHeader(String)
    case missingColumn(String)
    case noData
    case malformed(String)

    public var description: String {
        switch self {
        case .unreadableText: "The file is not readable as text."
        case .unrecognisedFormat: "The file format was not recognised."
        case .missingHeader(let what): "Missing header: \(what)."
        case .missingColumn(let name): "Required column not found: \(name)."
        case .noData: "The file contains no data rows."
        case .malformed(let detail): "Malformed file: \(detail)."
        }
    }
}

/// How sure an importer is that it can read a file.
public enum ImportConfidence: Int, Comparable, Sendable {
    case no = 0
    /// The extension matches but the content is not distinctive.
    case possible = 1
    /// The content matches a distinctive signature.
    case likely = 2
    /// The file explicitly declares this format.
    case certain = 3

    public static func < (lhs: ImportConfidence, rhs: ImportConfidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A cheap look at a file used for format detection without parsing everything.
public struct FileSniff: Sendable {
    public let url: URL
    public let fileExtension: String
    /// Up to the first 8 KB of the file decoded as text (empty if not decodable).
    public let head: String

    public init(url: URL, head: String) {
        self.url = url
        self.fileExtension = url.pathExtension.lowercased()
        self.head = head
    }

    public static func sniff(_ url: URL) throws -> FileSniff {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8192) ?? Data()
        // Lossy decoding is deliberate: the 8 KB cut can split a multi-byte sequence.
        // swiftlint:disable:next optional_data_string_conversion
        var head = String(decoding: data, as: UTF8.self)
        if head.hasPrefix("\u{FEFF}") { head.removeFirst() }
        return FileSniff(url: url, head: head)
    }

    public var firstLine: Substring {
        head.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first ?? ""
    }
}

/// A reader for one telemetry file format.
public protocol TelemetryImporter: Sendable {
    /// Stable identifier such as `racerender-csv`.
    static var id: String { get }
    static var displayName: String { get }
    static var fileExtensions: [String] { get }
    static func confidence(for sniff: FileSniff) -> ImportConfidence
    /// Parses the file into a raw table. Column roles are suggested, not final.
    func importFile(at url: URL) throws -> RawTable
}

extension TelemetryImporter {
    /// Convenience: import and build a session in one step.
    public func importSession(at url: URL, options: SessionBuilder.Options = .init()) throws -> TelemetrySession {
        SessionBuilder.build(try importFile(at: url), options: options)
    }
}
