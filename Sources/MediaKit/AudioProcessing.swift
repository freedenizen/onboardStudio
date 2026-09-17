import AVFoundation
import Foundation
import MediaToolbox
import ProjectModel

/// Builds the `AVAudioMix` for a composition: volume via mix parameters, balance and channel
/// selection via an `MTAudioProcessingTap` that rewrites the PCM buffers in place.
enum AudioMixBuilder {
    static func mix(for tracks: [(track: AVMutableCompositionTrack, settings: AudioSettings)]) -> AVMutableAudioMix? {
        var parameters: [AVMutableAudioMixInputParameters] = []
        for entry in tracks where !entry.settings.isNeutral {
            let input = AVMutableAudioMixInputParameters(track: entry.track)
            input.setVolume(Float(entry.settings.effectiveVolume), at: .zero)
            if entry.settings.balance != 0 || entry.settings.channels != .stereo {
                input.audioTapProcessor = AudioTap.make(
                    balance: entry.settings.balance, channels: entry.settings.channels)
            }
            parameters.append(input)
        }
        guard !parameters.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }
}

/// Per-buffer gains for a stereo pair derived from balance and channel selection.
struct ChannelGains: Sendable, Equatable {
    /// gains[out][in]: how much of input channel `in` goes to output channel `out`.
    let leftFromLeft: Float
    let leftFromRight: Float
    let rightFromLeft: Float
    let rightFromRight: Float

    init(balance: Double, channels: AudioChannelSelection) {
        // Constant-power balance: −1 = full left, +1 = full right.
        let angle = (balance + 1) / 2 * Double.pi / 2
        let leftGain = Float(cos(angle) * sqrt(2))
        let rightGain = Float(sin(angle) * sqrt(2))
        switch channels {
        case .stereo:
            leftFromLeft = leftGain
            leftFromRight = 0
            rightFromLeft = 0
            rightFromRight = rightGain
        case .mono:
            leftFromLeft = 0.5 * leftGain
            leftFromRight = 0.5 * leftGain
            rightFromLeft = 0.5 * rightGain
            rightFromRight = 0.5 * rightGain
        case .left:
            leftFromLeft = leftGain
            leftFromRight = 0
            rightFromLeft = rightGain
            rightFromRight = 0
        case .right:
            leftFromLeft = 0
            leftFromRight = leftGain
            rightFromLeft = 0
            rightFromRight = rightGain
        }
    }
}

/// Wraps the C-level audio tap. The gains are stored in the tap's client info and never change.
enum AudioTap {
    final class Box {
        let gains: ChannelGains
        var isInterleaved = false
        var channelCount = 0
        init(gains: ChannelGains) { self.gains = gains }
    }

    static func make(balance: Double, channels: AudioChannelSelection) -> MTAudioProcessingTap? {
        let box = Box(gains: ChannelGains(balance: balance, channels: channels))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque()),
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: nil,
            process: audioTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr else { return nil }
        return tap
    }

    /// Mixes a stereo float buffer in place. Mono sources are left untouched.
    static func apply(
        _ g: ChannelGains, to list: UnsafeMutablePointer<AudioBufferList>, frames: Int, channels: Int, interleaved: Bool
    ) {
        guard channels >= 2, frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        if interleaved {
            guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let stride = channels
            for frame in 0..<frames {
                let l = data[frame * stride]
                let r = data[frame * stride + 1]
                data[frame * stride] = l * g.leftFromLeft + r * g.leftFromRight
                data[frame * stride + 1] = l * g.rightFromLeft + r * g.rightFromRight
            }
        } else {
            guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return }
            for frame in 0..<frames {
                let l = left[frame]
                let r = right[frame]
                left[frame] = l * g.leftFromLeft + r * g.leftFromRight
                right[frame] = l * g.rightFromLeft + r * g.rightFromRight
            }
        }
    }
}

// MARK: - C callbacks (file scope keeps them out of the region-isolation checker's way)

private func audioTapInit(
    tap: MTAudioProcessingTap, clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func audioTapFinalize(tap: MTAudioProcessingTap) {
    Unmanaged<AudioTap.Box>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func audioTapPrepare(
    tap: MTAudioProcessingTap, maxFrames: CMItemCount, format: UnsafePointer<AudioStreamBasicDescription>
) {
    let box = Unmanaged<AudioTap.Box>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    box.channelCount = Int(format.pointee.mChannelsPerFrame)
    box.isInterleaved = format.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
}

// swiftlint:disable:next function_parameter_count
private func audioTapProcess(
    tap: MTAudioProcessingTap,
    frames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferList: UnsafeMutablePointer<AudioBufferList>,
    framesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut)
    guard status == noErr else { return }
    let box = Unmanaged<AudioTap.Box>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    AudioTap.apply(
        box.gains, to: bufferList, frames: Int(framesOut.pointee), channels: box.channelCount,
        interleaved: box.isInterleaved)
}
