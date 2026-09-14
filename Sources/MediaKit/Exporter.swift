import AVFoundation
import Foundation
import ProjectModel

public struct ExportProgress: Sendable, Equatable {
    /// 0…1
    public let fraction: Double
    public let framesWritten: Int
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
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await job.run()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func videoSettings(_ settings: ExportSettings) -> [String: Any] {
        let codec: AVVideoCodecType = settings.codec == .hevc ? .hevc : .h264
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: settings.frameRate,
            AVVideoMaxKeyFrameIntervalKey: Int(settings.frameRate * 2),
        ]
        if settings.codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: settings.width,
            AVVideoHeightKey: settings.height,
            AVVideoCompressionPropertiesKey: compression,
        ]
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
    private let start: Double
    private let end: Double
    private let onProgress: @Sendable (ExportProgress) -> Void
    private let frames = Counter()

    init(
        compiled: CompiledComposition,
        settings: ExportSettings,
        range: ClosedRange<Double>?,
        outputURL: URL,
        onProgress: @escaping @Sendable (ExportProgress) -> Void
    ) throws {
        let timescale: CMTimeScale = 600
        start = range?.lowerBound ?? 0
        end = min(range?.upperBound ?? compiled.duration, compiled.duration)
        timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            end: CMTime(seconds: end, preferredTimescale: timescale))
        self.onProgress = onProgress

        try? FileManager.default.removeItem(at: outputURL)
        do { reader = try AVAssetReader(asset: compiled.composition) } catch {
            throw ExportError.cannotCreateReader("\(error)")
        }
        reader.timeRange = timeRange
        do { writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4) } catch {
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
                    self.onProgress(ExportProgress(fraction: fraction, framesWritten: count, currentTime: time))
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
                throw error
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw ExportError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        await writer.finishWriting()
        if writer.status == .failed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown") }
        onProgress(ExportProgress(fraction: 1, framesWritten: frames.value, currentTime: end))
    }

    /// Copies sample buffers from a reader output to a writer input, honouring back-pressure and
    /// Task cancellation.
    private func pump(
        from output: AVAssetReaderOutput,
        to input: AVAssetWriterInput,
        label: String,
        onSample: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "overlaygen.export.\(label)")
        let finished = Flag()
        // AVFoundation invokes the block only on `queue`, serially, so these captures are safe.
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if finished.value { return }
                    if Task.isCancelled {
                        input.markAsFinished()
                        if !finished.exchange(true) { continuation.resume(throwing: ExportError.cancelled) }
                        return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        if !finished.exchange(true) { continuation.resume() }
                        return
                    }
                    if !input.append(sample) {
                        input.markAsFinished()
                        if !finished.exchange(true) {
                            continuation.resume(throwing: ExportError.writerFailed("append rejected"))
                        }
                        return
                    }
                    onSample(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                }
            }
        }
    }
}

/// Tiny thread-safe counter/flag helpers for the export pump.
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

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    /// Sets the flag and returns the previous value.
    func exchange(_ new: Bool) -> Bool {
        lock.withLock {
            let old = flag
            flag = new
            return old
        }
    }
}
