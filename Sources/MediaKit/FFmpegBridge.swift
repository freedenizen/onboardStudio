import AVFoundation
import CryptoKit
import Foundation
import ProjectModel

/// Optional bridge to an external `ffmpeg` for containers AVFoundation cannot open (MTS/M2TS,
/// MKV, some AVI). Never required: when ffmpeg is absent, `prepare` reports why.
public enum FFmpegBridge {
    public enum PrepareError: Error, CustomStringConvertible {
        case unreadableAndNoFFmpeg(URL)
        case ffmpegFailed(String)

        public var description: String {
            switch self {
            case .unreadableAndNoFFmpeg(let url):
                "\(url.lastPathComponent) cannot be opened by macOS and ffmpeg is not installed "
                    + "(brew install ffmpeg) to convert it."
            case .ffmpegFailed(let detail): "ffmpeg failed: \(detail)"
            }
        }
    }

    /// Candidate ffmpeg locations, first match wins. `ONBOARD_FFMPEG` overrides.
    public static var executable: URL? {
        let env = ProcessInfo.processInfo.environment["ONBOARD_FFMPEG"]
        let chosen = UserDefaults.standard.value(for: Preferences.ffmpegPath)
        let preference = chosen.isEmpty ? nil : chosen
        let candidates = [env, preference, "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .compactMap { $0 }
        return candidates.map(URL.init(fileURLWithPath:)).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    /// Where converted files live; keyed by a hash of path + size + modification date.
    public static var cacheDirectory: URL {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "OnboardStudio/remux", directoryHint: .isDirectory)
    }

    /// Returns a URL AVFoundation can play: the original when readable, otherwise a cached
    /// remux (or transcode) produced by ffmpeg.
    public static func prepare(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        if (try? await asset.load(.isReadable)) == true,
            let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty
        {
            return url
        }
        guard let ffmpeg = executable else { throw PrepareError.unreadableAndNoFFmpeg(url) }
        let target = cacheDirectory.appending(path: cacheName(for: url))
        if FileManager.default.fileExists(atPath: target.path) { return target }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        // Try a stream copy first (fast, lossless); fall back to a transcode.
        if (try? run(ffmpeg, ["-y", "-i", url.path, "-c", "copy", "-movflags", "+faststart", target.path])) == nil {
            try run(
                ffmpeg,
                [
                    "-y", "-i", url.path, "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac",
                    "-movflags", "+faststart", target.path,
                ])
        }
        let converted = AVURLAsset(url: target)
        guard (try? await converted.load(.isReadable)) == true else {
            try? FileManager.default.removeItem(at: target)
            throw PrepareError.ffmpegFailed("the converted file is still not readable")
        }
        return target
    }

    static func cacheName(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let digest = SHA256.hash(data: Data("\(url.path)|\(size)|\(modified)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "\(url.deletingPathExtension().lastPathComponent)-\(hex).mov"
    }

    static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-hide_banner", "-loglevel", "error"] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(bytes: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PrepareError.ffmpegFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
