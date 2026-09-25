import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import RenderKit
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Steadying from the picture (#264)", .serialized)
struct PictureMotionTests {
    /// A textured picture of `size`, moved `shift` pixels across in Core Image's axes.
    static func frame(shift: Double, size: CGSize) throws -> CIImage {
        let checks = CIFilter.checkerboardGenerator()
        checks.width = 17
        checks.color0 = .white
        checks.color1 = .black
        let blobs = try #require(CIFilter.randomGenerator().outputImage)
            .transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let pattern = try #require(checks.outputImage)
        return blobs.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: pattern])
            .transformed(by: CGAffineTransform(translationX: shift, y: 0))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// A 30 fps video whose picture jumps `jitter` pixels one way then the other, frame after frame.
    static func jitteryVideo(frames: Int, jitter: Double, size: CGSize) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "jitter-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.proRes422, AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let buffer = try PixelBuffers.makeBuffer(width: Int(size.width), height: Int(size.height))
            context.render(try Self.frame(shift: index.isMultiple(of: 2) ? jitter : -jitter, size: size), to: buffer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func aJitterIsMeasuredAndSteadiedAway() async throws {
        let size = CGSize(width: 480, height: 360)
        let url = try await Self.jitteryVideo(frames: 30, jitter: 6, size: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = try await PictureMotion.measure(url) { _ in }
        #expect(track.times.count == 30)
        // The picture moves 12 px (a thirtieth of its height) one way, then back, each frame.
        let steps: [Double] = zip(track.x.dropFirst(), track.x).map { abs($0 - $1) }
        let meanStep: Double = steps.reduce(0, +) / Double(steps.count)
        let expected: Double = 12.0 / 360
        let error: Double = abs(meanStep - expected)
        #expect(error < 0.01, "mean step \(meanStep), expected \(expected)")
        // Moved by their corrections, the frames stand still.
        let path = try #require(StabilisationPath(picture: track, smoothing: 0.5, maxShift: 0.2))
        let steadied = LayerStabilisation(path: path, zoom: 1.1, sync: .identity)
        var before = 0.0
        var after = 0.0
        let context = CIContext()
        var previous: (raw: CVPixelBuffer, steady: CVPixelBuffer)?
        for (index, time) in track.times.enumerated() {
            let raw = try PixelBuffers.makeBuffer(width: Int(size.width), height: Int(size.height))
            context.render(try Self.frame(shift: index.isMultiple(of: 2) ? 6 : -6, size: size), to: raw)
            let steady = try PixelBuffers.makeBuffer(width: Int(size.width), height: Int(size.height))
            context.render(steadied.apply(to: CIImage(cvPixelBuffer: raw), at: time), to: steady)
            if let previous, index > 4, index < 25 {
                before += abs(try PictureMotion.move(from: previous.raw, to: raw).x)
                after += abs(try PictureMotion.move(from: previous.steady, to: steady).x)
            }
            previous = (raw, steady)
        }
        #expect(after < before * 0.3, "jitter \(before) → \(after) px")
    }

    @Test func aMeasurementIsKeptForTheSameFileOnly() async throws {
        let url = try await Self.jitteryVideo(frames: 6, jitter: 2, size: CGSize(width: 160, height: 120))
        defer { try? FileManager.default.removeItem(at: url) }
        var last: PictureMotionTrack?
        for try await (_, track) in PictureMotion.analyse(url) { if let track { last = track } }
        #expect(PictureMotion.saved(for: url) == last)
        #expect(PictureMotion.saved(for: URL(fileURLWithPath: "/tmp/no-such-video.mov")) == nil)
        if let cache = PictureMotion.cacheURL(for: url) { try? FileManager.default.removeItem(at: cache) }
    }

    @Test func chaptersCarryOnFromWhereTheLastEnded() {
        var first = PictureMotionTrack()
        first.append(time: 0, shift: (0, 0), roll: 0)
        first.append(time: 1, shift: (0.1, 0), roll: 0.01)
        var second = PictureMotionTrack()
        second.append(time: 0, shift: (0, 0), roll: 0)
        second.append(time: 1, shift: (0.2, 0), roll: 0)
        let joined = first.followed(by: second, at: 10)
        #expect(joined.times == [0, 1, 10, 11])
        #expect(joined.x == [0, 0.1, 0.1, 0.30000000000000004])
        #expect(joined.roll == [0, 0.01, 0.01, 0.01])
    }
}

/// Measurements are kept apart for the UI tests, so none finds a video already measured (#288).
@Suite struct PictureMotionCacheTests {
    @Test func theUITestsFolderIsUsedWhenGiven() {
        let folder = PictureMotion.cacheFolder(environment: ["ONBOARD_TEST_MOTION_DIR": "/tmp/motion-test"])
        #expect(folder.path == "/tmp/motion-test")
    }

    @Test func otherwiseMeasurementsLiveInApplicationSupport() {
        let folder = PictureMotion.cacheFolder(environment: [:])
        #expect(folder.path.hasSuffix("Application Support/OnboardStudio/Motion"))
    }
}
