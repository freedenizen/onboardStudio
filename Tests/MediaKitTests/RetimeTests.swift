import AVFoundation
import Foundation
import Testing

@testable import MediaKit
@testable import ProjectModel
@testable import RenderKit

/// The slice project retimed (#442): its picture and its overlays slowed and held together.
@Suite("Retime", .serialized, .media)
struct RetimeTests {
    /// 0.5–1.5 s at half speed and a 1 s hold at 2 s: the 3 s slice takes 5 s.
    static let retimes = [
        Retime(start: 0.5, kind: .speed(end: 1.5, rate: 0.5)),
        Retime(start: 2, kind: .hold(seconds: 1)),
    ]

    func compile(retimed: Bool) async throws -> CompiledComposition {
        var loaded = try await ProjectCompiler.load(try ProjectCompilerTests.sliceURL)
        loaded.project.retimes = retimed ? Self.retimes : []
        return try await ProjectCompiler.compile(loaded)
    }

    /// The frame our compositor draws at output time `time`: picture and overlays, not encoded.
    func frame(_ compiled: CompiledComposition, at time: Double) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: compiled.composition)
        generator.videoComposition = compiled.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        return try #require(image.dataProvider?.data as Data?)
    }

    @Test func theRetimedSliceIsLongerAndItsInstructionsTileTheOutput() async throws {
        let compiled = try await compile(retimed: true)
        #expect(abs(compiled.duration - 3) < 0.05, "duration stays the project's")
        #expect(abs(compiled.outputDuration - 5) < 0.05)
        #expect(abs(compiled.composition.duration.seconds - 5) < 0.1, "\(compiled.composition.duration.seconds)")
        let instructions = compiled.videoComposition.instructions.compactMap { $0 as? OverlayInstruction }
        #expect(instructions.first?.timeRange.start == .zero)
        #expect(abs((instructions.last?.timeRange.end.seconds ?? 0) - compiled.outputDuration) < 0.01)
        #expect(instructions.allSatisfy { $0.timeMap == compiled.timeMap })
        // Unretimed, nothing changes: output time is project time.
        let plain = try await compile(retimed: false)
        #expect(plain.timeMap.isIdentity && abs(plain.outputDuration - plain.duration) < 1e-9)
    }

    @Test func aHoldShowsOneFramePictureAndOverlaysAlike() async throws {
        let compiled = try await compile(retimed: true)
        // Output 3.0–4.0 holds project 2.0.
        let early = try await frame(compiled, at: 3.2)
        let late = try await frame(compiled, at: 3.8)
        #expect(early == late, "the held frame changed")
        let after = try await frame(compiled, at: 4.6)
        #expect(early != after, "the video did not play on after the hold")
    }

    @Test func aSlowedFrameIsTheFrameItShowsAtNormalSpeed() async throws {
        // Project 0.8167 s (mid-frame at 30 fps) is output 1.1333 s once 0.5–1.5 plays at half speed.
        let project = 0.8 + 1.0 / 60
        let retimed = try await compile(retimed: true)
        let plain = try await compile(retimed: false)
        let output = retimed.timeMap.outputTime(atProject: project)
        #expect(abs(output - (0.5 + (project - 0.5) * 2)) < 1e-9)
        let slowed = try await frame(retimed, at: output)
        let normal = try await frame(plain, at: project)
        #expect(slowed == normal, "picture or overlays drifted from each other in the slowed stretch")
        // Not trivially equal: the slice changes from frame to frame.
        let later = try await frame(plain, at: 1.2 + 1.0 / 60)
        #expect(slowed != later)
    }

    @Test func theSoundIsMutedWhereTheVideoIsRetimed() async throws {
        let compiled = try await compile(retimed: true)
        let audio = compiled.composition.tracks(withMediaType: .audio)
        guard !audio.isEmpty else { return }
        let mix = try #require(compiled.audioMix)
        for parameters in mix.inputParameters {
            func volume(at seconds: Double) -> Float {
                var start: Float = -1
                var end: Float = -1
                var range = CMTimeRange.zero
                let ramp = parameters.getVolumeRamp(
                    for: CMTime(seconds: seconds, preferredTimescale: 600), startVolume: &start, endVolume: &end,
                    timeRange: &range)
                return ramp ? start : -1
            }
            #expect(volume(at: 0.2) > 0)
            #expect(volume(at: 1.0) == 0, "slowed")
            #expect(volume(at: 2.7) > 0)
            #expect(volume(at: 3.5) == 0, "held")
            #expect(volume(at: 4.5) > 0)
        }
    }
}
