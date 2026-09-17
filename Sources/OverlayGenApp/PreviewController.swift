import AVFoundation
import Foundation
import MediaKit
import Observation

/// Owns the `AVPlayer` that previews the compiled composition. The player plays exactly what the
/// exporter encodes: same composition, same custom compositor.
@Observable
final class PreviewController {
    let player = AVPlayer()
    private(set) var compiled: CompiledComposition?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private var timeObserver: Any?
    private var isSeeking = false

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) {
            [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    /// Installs a freshly compiled composition (inputs changed), keeping the playhead.
    func replace(with compiled: CompiledComposition) {
        let wasPlaying = isPlaying
        let time = currentTime
        self.compiled = compiled
        duration = compiled.duration
        let item = AVPlayerItem(asset: compiled.composition)
        item.videoComposition = compiled.videoComposition
        item.audioMix = compiled.audioMix
        player.replaceCurrentItem(with: item)
        seek(to: min(time, compiled.duration))
        if wasPlaying { player.play() }
    }

    /// Swaps only the overlay plan (object edits) and forces the current frame to redraw.
    func update(with compiled: CompiledComposition) {
        self.compiled = compiled
        guard let item = player.currentItem else { return }
        item.videoComposition = compiled.videoComposition
        if player.rate == 0 {
            // Re-seeking to the same time makes AVPlayer re-render the paused frame.
            let time = player.currentTime()
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func togglePlayback() {
        if player.rate != 0 {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.02 { seek(to: 0) }
            player.play()
        }
        isPlaying = player.rate != 0
    }

    func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        currentTime = clamped
        isSeeking = true
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            MainActor.assumeIsolated { self?.isSeeking = false }
        }
    }
}
