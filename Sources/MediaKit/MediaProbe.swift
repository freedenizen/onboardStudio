import AVFoundation
import Foundation
import GPMFKit

/// Basic facts about a media file, loaded asynchronously via AVFoundation.
public struct MediaInfo: Sendable, Equatable {
    public var url: URL
    public var duration: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
    /// Display size after applying the track's preferred transform (rotation).
    public var width: Int
    public var height: Int
    public var nominalFrameRate: Double
    public var videoCodec: String?
    public var creationDate: Date?
    /// Whether the file carries a GoPro `gpmd` or similar metadata track.
    public var hasMetadataTrack: Bool
    /// Whether the file carries GoPro GPMF telemetry (AVFoundation hides that track; see GPMFKit).
    public var hasGPMF: Bool = false
}

public enum MediaProbeError: Error, CustomStringConvertible {
    case unreadable(URL)
    case noVideoTrack(URL)

    public var description: String {
        switch self {
        case .unreadable(let url): "Cannot read media file \(url.lastPathComponent)."
        case .noVideoTrack(let url): "\(url.lastPathComponent) has no video track."
        }
    }
}

public enum MediaProbe {
    public static func probe(_ url: URL) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard try await asset.load(.isReadable) else { throw MediaProbeError.unreadable(url) }
        let (duration, tracks, metadata) = try await asset.load(.duration, .tracks, .creationDate)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        let metadataTracks = tracks.filter { $0.mediaType == .metadata }

        var width = 0
        var height = 0
        var frameRate = 0.0
        var codec: String?
        if let video = videoTracks.first {
            let (naturalSize, transform, nominal, descriptions) = try await video.load(
                .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            let displaySize = naturalSize.applying(transform)
            width = Int(abs(displaySize.width).rounded())
            height = Int(abs(displaySize.height).rounded())
            frameRate = Double(nominal)
            if let description = descriptions.first {
                codec = fourCC(CMFormatDescriptionGetMediaSubType(description))
            }
        }
        let creation = try await metadata?.load(.dateValue)
        return MediaInfo(
            url: url,
            duration: duration.seconds.isFinite ? duration.seconds : 0,
            hasVideo: !videoTracks.isEmpty,
            hasAudio: !audioTracks.isEmpty,
            width: width,
            height: height,
            nominalFrameRate: frameRate,
            videoCodec: codec,
            creationDate: creation,
            hasMetadataTrack: !metadataTracks.isEmpty, hasGPMF: MP4Boxes.hasTrack("gpmd", in: url))
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? String(code)
    }
}
