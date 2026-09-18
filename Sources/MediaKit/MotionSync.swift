import AVFoundation
import Foundation
import ProjectModel
import TelemetryKit

/// Lines a data log up with a video from what they both record: the car moving. The video's
/// audio loudness (engine and wind noise) or, for silent clips, the change between frames is
/// correlated against the log's speed (or, failing that, its g-forces) to find the offset
/// without timestamps or a manual mark.
public enum MotionSync {
    public struct Options: Sendable {
        /// Seconds of video analysed, from the video input's start position.
        public var window: Double
        /// Samples per second of the motion signal.
        public var rate: Double
        /// Width of the thumbnail the frames are reduced to before differencing.
        public var analysisWidth: Int
        /// Luma change (0…255) above which a thumbnail cell counts as moved; the motion measure is
        /// the fraction of cells that moved, which tracks speed far better than the mean change
        /// (a person walking past a parked car changes a few cells a lot; driving changes most of
        /// them). 0 uses the mean absolute change instead.
        public var changeThreshold: Double

        public init(window: Double = 180, rate: Double = 10, analysisWidth: Int = 64, changeThreshold: Double = 10) {
            self.window = window
            self.rate = rate
            self.analysisWidth = analysisWidth
            self.changeThreshold = changeThreshold
        }
    }

    public struct Suggestion: Sendable, Equatable {
        public let sync: SyncSettings
        /// Data seconds minus video seconds at the same instant.
        public let offset: Double
        /// Pearson correlation of the two motion signals at the match, 0…1.
        public let score: Double
        /// How clearly the match beats the runner-up, 0…1.
        public let prominence: Double
        /// Which log channel matched: "speed" or "g-force".
        public let channel: String
        /// Which side of the video was used: "audio loudness" or "picture motion".
        public let source: String

        /// A strong correlation on its own, or a moderate one that clearly beats every other
        /// alignment. (Lap after lap of similar speed traces makes rival alignments one lap away
        /// score almost as well, so prominence alone would reject perfectly good matches.)
        public var isConvincing: Bool { score >= 0.8 || (score >= 0.5 && prominence >= 0.25) }
    }

    public enum MotionError: Error, CustomStringConvertible {
        case noVideoTrack
        case tooShort
        case noMotionChannel

        public var description: String {
            switch self {
            case .noVideoTrack: "The video has no video track."
            case .tooShort: "Not enough of the video could be analysed."
            case .noMotionChannel: "The data file has neither speed nor g-force channels."
            }
        }
    }

    /// Mean absolute luma change per sample period, from `start` for `duration` seconds.
    public static func motionEnergy(
        of url: URL, start: Double, duration: Double, options: Options = Options(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MotionError.noVideoTrack
        }
        let natural = try await track.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        let end = start + duration
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        guard reader.startReading() else { throw MotionError.noVideoTrack }
        let width = max(8, options.analysisWidth)
        let height = max(4, Int(Double(width) * Double(natural.height) / max(1, Double(natural.width))))
        let period = 1 / options.rate
        var energies: [Double] = []
        var previous: [Float]?
        var nextSampleTime = start
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time + 1e-6 >= nextSampleTime, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let thumb = luma(of: buffer, width: width, height: height)
            if let previous {
                energies.append(change(from: previous, to: thumb, threshold: Float(options.changeThreshold)))
            }
            previous = thumb
            nextSampleTime += period
            progress?(min(1, (time - start) / max(duration, 0.001)))
        }
        if reader.status == .failed { throw MotionError.noVideoTrack }
        guard energies.count >= Int(options.rate * 5) else { throw MotionError.tooShort }
        return energies
    }

    /// The log's motion signal at `rate` Hz: speed when present, otherwise g-force magnitude.
    public static func motionSignal(of session: TelemetrySession, rate: Double) -> MotionSignal? {
        if let speed = session[.speed], speed.count > 4 {
            let (start, values) = SignalCorrelation.resample(times: speed.times, values: speed.values, rate: rate)
            return MotionSignal(start: start, values: values, channel: "speed")
        }
        if let lat = session[.lateralG], let lon = session[.longitudinalG], lat.count > 4 {
            let magnitude = lat.times.map { t -> Double in
                let a = lat.value(at: t) ?? 0
                let b = lon.value(at: t) ?? 0
                return (a * a + b * b).squareRoot()
            }
            let (start, values) = SignalCorrelation.resample(times: lat.times, values: magnitude, rate: rate)
            return MotionSignal(start: start, values: values, channel: "g-force")
        }
        return nil
    }

    /// Correlates a video's motion with a log and returns sync settings for the data input.
    public static func suggest(
        video url: URL, videoSync: SyncSettings, videoDuration: Double, data session: TelemetrySession,
        options: Options = Options(), progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Suggestion? {
        guard let signal = motionSignal(of: session, rate: options.rate) else { throw MotionError.noMotionChannel }
        let start = max(0, videoSync.startPositionInInput)
        // Audio first: it decodes in seconds and tracks speed well. Picture motion only when the
        // clip is silent or the audio match is weak; the better match wins.
        var best: Suggestion?
        if let loudness = try await audioLoudness(
            of: url, start: start, duration: min(3600, videoDuration - start), rate: options.rate)
        {
            best = match(
                energy: loudness, videoStart: start, videoSync: videoSync, signal: signal, source: "audio loudness",
                options: options)
        }
        if best?.isConvincing == true { return best }
        let duration = min(options.window, max(0, videoDuration - start))
        let energy = try await motionEnergy(
            of: url, start: start, duration: duration, options: options, progress: progress)
        let visual = match(
            energy: energy, videoStart: start, videoSync: videoSync, signal: signal, source: "picture motion",
            options: options)
        guard let best else { return visual }
        guard let visual else { return best }
        return visual.score > best.score ? visual : best
    }

    /// The pure part of `suggest`, for tests: `energy` is sampled from video second `videoStart`.
    public static func match(
        energy: [Double], videoStart: Double, videoSync: SyncSettings, signal: MotionSignal,
        source: String = "picture motion", options: Options = Options()
    ) -> Suggestion? {
        // Frame-to-frame measures are spiky; smooth them to the log's time scale. Only the mean is
        // removed (not a trend): the slow rise and fall of speed is exactly what is being matched.
        let smoothed = smooth(energy, radius: Int(options.rate / 2))
        let a = SignalCorrelation.normalise(smoothed, window: 0)
        let b = SignalCorrelation.normalise(signal.values, window: 0)
        guard let result = SignalCorrelation.bestOffset(short: a, long: b, rate: options.rate) else { return nil }
        // a[0] is video second `videoStart`; b[0] is session second `signal.start`.
        // Video second v ↔ session second signal.start + (v − videoStart) + result.offset.
        let sessionAtVideoStart = signal.start + result.offset
        let offset = sessionAtVideoStart - videoStart
        let sync = SyncSettings(
            startPositionInInput: sessionAtVideoStart, offsetInProject: videoSync.offsetInProject,
            playSpeed: videoSync.playSpeed)
        return Suggestion(
            sync: sync, offset: offset, score: result.score, prominence: result.prominence, channel: signal.channel,
            source: source)
    }

    static func smooth(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0, values.count > 2 * radius else { return values }
        var out = values
        for index in 0..<values.count {
            let lo = max(0, index - radius)
            let hi = min(values.count - 1, index + radius)
            out[index] = values[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        return out
    }
}
