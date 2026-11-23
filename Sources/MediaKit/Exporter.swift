import AVFoundation
import Foundation
import ProjectModel
import VideoToolbox

public struct ExportProgress: Sendable, Equatable {
    /// 0…1
    public let fraction: Double
    public let framesWritten: Int
    /// The project time of the frame just written.
    public let currentTime: Double

    public init(fraction: Double, framesWritten: Int, currentTime: Double) {
        self.fraction = fraction
        self.framesWritten = framesWritten
        self.currentTime = currentTime
    }
}

public enum ExportError: Error, CustomStringConvertible {
    case cannotCreateWriter(String)
    case cannotCreateReader(String)
    case cannotAddInput
    case writerFailed(String)
    case readerFailed(String)
    case cancelled

    public var description: String {
        switch self {
        case .cannotCreateWriter(let why): "Could not create the output file: \(why)"
        case .cannotCreateReader(let why): "Could not read the composition: \(why)"
        case .cannotAddInput: "The output settings are not supported by the encoder."
        case .writerFailed(let why): "Encoding failed: \(why)"
        case .readerFailed(let why): "Decoding failed: \(why)"
        case .cancelled: "Export was cancelled."
        }
    }
}

/// Encodes a compiled composition to an MP4 with `AVAssetReader` + `AVAssetWriter`. The reader
/// renders every frame through `OverlayCompositor`, so the output matches the preview exactly.
public enum Exporter {
    /// Exports `range` (project seconds; `nil` = everything) to `outputURL`, replacing any existing
    /// file. Progress is reported on the returned stream; cancel by cancelling the consuming task.
    public static func export(
        _ compiled: CompiledComposition,
        settings: ExportSettings,
        range: ClosedRange<Double>? = nil,
        to outputURL: URL
    ) -> AsyncThrowingStream<ExportProgress, Error> {
        AsyncThrowingStream { continuation in
            let job: ExportJob
            do {
                job = try ExportJob(
                    compiled: compiled, settings: settings, range: range, outputURL: outputURL,
                    onProgress: { continuation.yield($0) })
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let name = outputURL.lastPathComponent
            Diagnostics.exportStarted(name, settings)
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await job.run()
                    Diagnostics.exporting.info("Exported \(name, privacy: .public)")
                    continuation.finish()
                } catch {
                    Diagnostics.exportFailed(name, error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func videoSettings(_ settings: ExportSettings) -> [String: Any] {
        let codec: AVVideoCodecType =
            switch settings.codec {
            case .h264: .h264
            case .hevc: .hevc
            case .hevcAlpha: .hevcWithAlpha
            case .proRes4444: .proRes4444
            }
        var output: [String: Any] = [
            AVVideoCodecKey: codec, AVVideoWidthKey: settings.width, AVVideoHeightKey: settings.height,
        ]
        guard settings.codec.usesBitrate else { return output }
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate,
            AVVideoMaxKeyFrameIntervalKey: Int(settings.frameRate * 2),
        ]
        if settings.codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        if settings.codec == .hevcAlpha {
            compression[kVTCompressionPropertyKey_TargetQualityForAlpha as String] = 0.75
        }
        output[AVVideoCompressionPropertiesKey] = compression
        return output
    }

    static func fileType(for settings: ExportSettings) -> AVFileType {
        settings.codec.fileExtension == "mov" ? .mov : .mp4
    }
}

/// Owns the non-Sendable AVFoundation reader/writer objects for one export and drives them from
/// a detached task. Marked `@unchecked Sendable` because every object is touched only from the
/// job's own task and the serial dispatch queues AVFoundation calls back on.
final class ExportJob: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let videoOutput: AVAssetReaderVideoCompositionOutput
    private let videoInput: AVAssetWriterInput
    private let audio: (output: AVAssetReaderAudioMixOutput, input: AVAssetWriterInput)?
    private let timeRange: CMTimeRange
    /// Output seconds.
    private let start: Double
    private let end: Double
    private let timeMap: TimeMap
    private let onProgress: @Sendable (ExportProgress) -> Void
    private let frames = Counter()
    private let outputURL: URL
    private let spherical: Bool

    init(
        compiled: CompiledComposition,
        settings: ExportSettings,
        range: ClosedRange<Double>?,
        outputURL: URL,
        onProgress: @escaping @Sendable (ExportProgress) -> Void
    ) throws {
        let timescale: CMTimeScale = 600
        // `range` is project time; the composition runs in output time, which retimes stretch (#442).
        let map = compiled.timeMap
        timeMap = map
        start = map.outputTime(atProject: range?.lowerBound ?? 0)
        end = min(map.outputTime(atProject: range?.upperBound ?? compiled.duration), compiled.outputDuration)
        timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            end: CMTime(seconds: end, preferredTimescale: timescale))
        self.onProgress = onProgress
        self.outputURL = outputURL
        spherical = settings.spherical

        try? FileManager.default.removeItem(at: outputURL)
        do { reader = try AVAssetReader(asset: compiled.composition) } catch {
            throw ExportError.cannotCreateReader("\(error)")
        }
        reader.timeRange = timeRange
        do { writer = try AVAssetWriter(outputURL: outputURL, fileType: Exporter.fileType(for: settings)) } catch {
            throw ExportError.cannotCreateWriter("\(error)")
        }
        writer.shouldOptimizeForNetworkUse = true

        let videoTracks = compiled.composition.tracks(withMediaType: .video)
        videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.videoComposition = compiled.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ExportError.cannotCreateReader("cannot add video output") }
        reader.add(videoOutput)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Exporter.videoSettings(settings))
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ExportError.cannotAddInput }
        writer.add(videoInput)

        let audioTracks = compiled.composition.tracks(withMediaType: .audio)
        if let audioBitrate = settings.audioBitrate, !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            output.audioMix = compiled.audioMix
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: settings.audioSampleRate,
                    AVNumberOfChannelsKey: settings.audioChannels,
                    AVEncoderBitRateKey: audioBitrate,
                ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audio = (output, input)
            } else {
                audio = nil
            }
        } else {
            audio = nil
        }
    }

    func run() async throws {
        guard reader.startReading() else {
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: timeRange.start)

        let exportDuration = max(end - start, 0.001)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await pump(from: videoOutput, to: videoInput, label: "video") { time in
                    let count = self.frames.increment()
                    let fraction = min(1, (time - self.start) / exportDuration)
                    self.onProgress(
                        ExportProgress(
                            fraction: fraction, framesWritten: count,
                            currentTime: self.timeMap.projectTime(atOutput: time)))
                }
            }
            if let audio {
                group.addTask { [self] in try await pump(from: audio.output, to: audio.input, label: "audio") { _ in } }
            }
            do {
                try await group.waitForAll()
            } catch {
                reader.cancelReading()
                writer.cancelWriting()
                // What was written so far is no video: the file the writer opened and the copy it
                // was writing through go, so a cancelled export leaves nothing to mistake for one.
                Self.removePartial(outputURL)
                throw error
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        await writer.finishWriting()
        if writer.status == .failed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
        Self.removeLeftovers(beside: outputURL)
        if spherical { try SphericalMetadata.inject(into: outputURL) }
        onProgress(
            ExportProgress(fraction: 1, framesWritten: frames.value, currentTime: timeMap.projectTime(atOutput: end)))
    }

    /// Removes the copy the network-optimising pass leaves beside the output (`<name>.sb-…`).
    ///
    /// AVFoundation deletes it only when the writer is released, so a process that ends straight
    /// after an export — the CLI — left one beside every video (#248). The export is complete once
    /// `finishWriting` returns, so the copy is removed then rather than left to the writer.
    static func removeLeftovers(beside outputURL: URL) {
        let folder = outputURL.deletingLastPathComponent()
        let prefix = outputURL.lastPathComponent + ".sb-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    /// The file a writer that was stopped left at `outputURL`, and its `.sb-…` copy (#663).
    static func removePartial(_ outputURL: URL) {
        try? FileManager.default.removeItem(at: outputURL)
        removeLeftovers(beside: outputURL)
    }

    /// Copies sample buffers from a reader output to a writer input, honouring back-pressure and
    /// Task cancellation.
    ///
    /// The block below runs on a dispatch queue, where there is no current task: `Task.isCancelled`
    /// read there is always false, and a cancelled export went on to its last frame while the
    /// sheet said it was over (#663). Cancellation is caught on the task and carried in as a flag.
    private func pump(
        from output: AVAssetReaderOutput,
        to input: AVAssetWriterInput,
        label: String,
        onSample: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "onboard.export.\(label)")
        let pending = PendingPump()
        // AVFoundation invokes the block only on `queue`, serially, so these captures are safe.
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Cancelled before it began: nothing is asked of the writer at all.
                guard pending.park(continuation) else {
                    continuation.resume(throwing: ExportError.cancelled)
                    return
                }
                input.requestMediaDataWhenReady(on: queue) {
                    // One pool per sample: a ready writer can take hundreds of frames in one call,
                    // and every decoded frame and composited buffer is autoreleased.
                    while input.isReadyForMoreMediaData,
                        autoreleasepool(invoking: { () -> Bool in
                            // Settled from outside is cancelled: `run` stops the writer itself.
                            if pending.isSettled { return false }
                            guard let sample = output.copyNextSampleBuffer() else {
                                input.markAsFinished()
                                pending.settle(.success(()))
                                return false
                            }
                            if !input.append(sample) {
                                input.markAsFinished()
                                pending.settle(.failure(ExportError.writerFailed("append rejected")))
                                return false
                            }
                            onSample(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                            return true
                        })
                    {}
                }
            }
        } onCancel: {
            pending.settle(.failure(ExportError.cancelled))
        }
    }
}

/// The continuation a pump waits on, resumed once by whichever comes first: the last sample, a
/// writer that refuses one, or the task being cancelled (#663). Cancellation has to be able to
/// resume it from outside the writer's queue: a writer that has been stopped never calls the
/// pump's block again, and the pump — and the export with it — would wait for ever.
final class PendingPump: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    var isSettled: Bool { lock.withLock { settled } }

    /// Keeps `continuation` to be resumed later; `false` when the pump was settled before it
    /// started, and the caller resumes it itself.
    func park(_ continuation: CheckedContinuation<Void, Error>) -> Bool {
        lock.withLock {
            guard !settled else { return false }
            self.continuation = continuation
            return true
        }
    }

    func settle(_ result: Result<Void, Error>) {
        let waiting: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !settled else { return nil }
            settled = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
    }
}

/// A thread-safe counter for the export pump.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
