import AVFoundation
import CoreVideo
import Foundation

// MARK: - Signal extraction from the video

extension MotionSync {
    /// Loudness of the video's audio in dB, one value per sample period from `start` for
    /// `duration` seconds (whole clip when `duration` is nil). Engine and wind noise track speed
    /// closely, and audio decodes in a few seconds, so this is the first signal tried.
    public static func audioLoudness(
        of url: URL, start: Double = 0, duration: Double? = nil, rate: Double = 10
    ) async throws -> [Double]? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1,
            ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        let total = try await asset.load(.duration).seconds
        let end = min(total, start + (duration ?? total))
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        guard reader.startReading() else { return nil }
        var sums: [Double] = []
        var counts: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let format = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                let block = CMSampleBufferGetDataBuffer(sample)
            else { continue }
            let sampleRate = asbd.mSampleRate
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard
                CMBlockBufferGetDataPointer(
                    block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
                    == noErr,
                let pointer
            else { continue }
            let floats = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            let frames = length / MemoryLayout<Float>.size
            for index in 0..<frames {
                let t = time + Double(index) / sampleRate - start
                let bucket = Int(t * rate)
                guard bucket >= 0 else { continue }
                while sums.count <= bucket {
                    sums.append(0)
                    counts.append(0)
                }
                let v = Double(floats[index])
                sums[bucket] += v * v
                counts[bucket] += 1
            }
        }
        guard sums.count > Int(rate * 5) else { return nil }
        return zip(sums, counts).map { sum, count in
            10 * log10(max(1e-10, count > 0 ? sum / Double(count) : 1e-10))
        }
    }

    /// Fraction of cells whose luma moved by more than `threshold`, or the mean change when it is 0.
    static func change(from previous: [Float], to current: [Float], threshold: Float) -> Double {
        var sum: Float = 0
        var moved = 0
        for index in 0..<current.count {
            let delta = abs(current[index] - previous[index])
            sum += delta
            if delta > threshold { moved += 1 }
        }
        return threshold > 0
            ? Double(moved) / Double(max(1, current.count)) : Double(sum) / Double(max(1, current.count))
    }

    /// Box-averaged luma thumbnail (row-major, `width` × `height`) of a bi-planar YCbCr buffer.
    static func luma(of buffer: CVPixelBuffer, width: Int, height: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let sourceWidth = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let sourceHeight = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)?.assumingMemoryBound(to: UInt8.self),
            sourceWidth > 0, sourceHeight > 0
        else { return [Float](repeating: 0, count: width * height) }
        var out = [Float](repeating: 0, count: width * height)
        let cellW = max(1, sourceWidth / width)
        let cellH = max(1, sourceHeight / height)
        // Sample a few pixels per cell rather than every one; plenty for a motion estimate.
        let stepX = max(1, cellW / 4)
        let stepY = max(1, cellH / 4)
        for cy in 0..<height {
            let y0 = cy * sourceHeight / height
            for cx in 0..<width {
                let x0 = cx * sourceWidth / width
                var sum = 0
                var count = 0
                var y = y0
                while y < min(y0 + cellH, sourceHeight) {
                    let row = base + y * rowBytes
                    var x = x0
                    while x < min(x0 + cellW, sourceWidth) {
                        sum += Int(row[x])
                        count += 1
                        x += stepX
                    }
                    y += stepY
                }
                out[cy * width + cx] = count > 0 ? Float(sum) / Float(count) : 0
            }
        }
        return out
    }

    /// A log's motion signal on the session's time axis.
    public struct MotionSignal: Sendable, Equatable {
        public let start: Double
        public let values: [Double]
        /// "speed" or "g-force".
        public let channel: String

        public init(start: Double, values: [Double], channel: String) {
            self.start = start
            self.values = values
            self.channel = channel
        }
    }
}
