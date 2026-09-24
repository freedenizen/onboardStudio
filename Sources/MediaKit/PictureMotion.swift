import AVFoundation
import CoreImage
import CryptoKit
import Foundation
import TelemetryKit
import Vision

/// Measures how a video's picture moves, from the picture alone (#264), for the cameras that record
/// no motion data. Each sampled frame is registered onto the one before with a Vision homography —
/// the same measurement the motion-data stabilisation was checked against — on the recorded
/// (unrotated) frames, as the stabiliser moves them.
public enum PictureMotion {
    /// About this many frames a second are measured: enough for the shake of a helmet (a few hertz),
    /// a quarter of the work of every frame of a 120 fps recording.
    public static let sampleRate = 30.0
    /// Width the frames are measured at; the moves are kept in picture heights, so this only sets speed.
    static let width = 480

    /// Measures `url`, reporting the fraction done; the stream's last element carries the track.
    public static func analyse(_ url: URL) -> AsyncThrowingStream<(Double, PictureMotionTrack?), any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    let track = try await measure(url) { continuation.yield(($0, nil)) }
                    try? save(track, for: url)
                    continuation.yield((1, track))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func measure(_ url: URL, progress: (Double) -> Void) async throws -> PictureMotionTrack {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompositionError.noVideoTrack(url)
        }
        let (size, rate, duration) = try await (
            track.load(.naturalSize), track.load(.nominalFrameRate), asset.load(.duration)
        )
        let height = max(2, Int((Double(width) * size.height / max(size.width, 1)).rounded()))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CompositionError.noVideoTrack(url) }
        let step = max(1, Int((Double(rate) / sampleRate).rounded()))
        let seconds = max(duration.seconds, 0.001)
        var result = PictureMotionTrack()
        var previous: CVPixelBuffer?
        var index = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            defer { index += 1 }
            guard index % step == 0, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let previous {
                let move = try autoreleasepool { try Self.move(from: previous, to: buffer) }
                result.append(
                    time: time, shift: (move.x / Double(height), move.y / Double(height)), roll: move.z)
            } else {
                result.append(time: time, shift: (0, 0), roll: 0)
            }
            previous = buffer
            if index % (step * 30) == 0 { progress(min(time / seconds, 1)) }
        }
        if reader.status == .failed { throw reader.error ?? CompositionError.noVideoTrack(url) }
        return result
    }

    /// The picture's shift (x, y: pixels, Core Image axes) and roll (z: radians) between two frames,
    /// from where Vision maps the centre of the later one onto the earlier; no move when Vision cannot
    /// register them.
    static func move(from earlier: CVPixelBuffer, to later: CVPixelBuffer) throws -> SIMD3<Double> {
        let request = VNHomographicImageRegistrationRequest(targetedCVPixelBuffer: later)
        do { try VNImageRequestHandler(cvPixelBuffer: earlier).perform([request]) } catch { return .zero }
        guard let m = request.results?.first?.warpTransform else { return .zero }
        let c = simd_float3(Float(CVPixelBufferGetWidth(later)) / 2, Float(CVPixelBufferGetHeight(later)) / 2, 1)
        let p = m * c
        guard p.z != 0 else { return .zero }
        return SIMD3(
            Double(p.x / p.z - c.x), Double(p.y / p.z - c.y), atan2(Double(m.columns.0.y), Double(m.columns.0.x)))
    }

    // MARK: - Kept between runs

    /// Where the measurement of `url` is kept: by its path, size and modification date, so an edited
    /// or replaced file is measured afresh.
    static func cacheURL(for url: URL) -> URL? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let key = "\(url.standardizedFileURL.path)|\(size)|\(modified.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "OnboardStudio/Motion/\(digest.prefix(32)).json")
    }

    /// A measurement made earlier of this very file, if there is one.
    public static func saved(for url: URL) -> PictureMotionTrack? {
        guard let cache = cacheURL(for: url), let data = try? Data(contentsOf: cache) else { return nil }
        return try? JSONDecoder().decode(PictureMotionTrack.self, from: data)
    }

    static func save(_ track: PictureMotionTrack, for url: URL) throws {
        guard let cache = cacheURL(for: url) else { return }
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(track).write(to: cache, options: .atomic)
    }
}
