import Foundation
import GPMFKit
import TelemetryKit

/// Telemetry embedded in a GoPro recording (the `gpmd` metadata track): GPS position, speed,
/// altitude, accelerometer and gyroscope. Times are seconds from the start of the video.
public struct GoProImporter: TelemetryImporter {
    public static let id = "gopro-gpmf"
    public static let displayName = "GoPro GPMF"
    public static let fileExtensions = ["mp4", "mov", "360"]

    public init() {}

    public static func confidence(for sniff: FileSniff) -> ImportConfidence {
        guard fileExtensions.contains(sniff.fileExtension) else { return .no }
        // MP4 files start with a size then "ftyp"; only files with a GPMF track are ours.
        guard sniff.head.dropFirst(4).hasPrefix("ftyp") || sniff.head.contains("ftyp") else { return .no }
        return MP4Boxes.hasTrack("gpmd", in: sniff.url) ? .certain : .no
    }

    public func importFile(at url: URL) throws -> RawTable {
        try GoProTelemetry.importFile(at: url)
    }
}
