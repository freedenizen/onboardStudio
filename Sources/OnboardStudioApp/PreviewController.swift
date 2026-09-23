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
        // The periodic observer stops with the player, so it never sees the player stop itself at
        // the end; without this the transport went on saying Pause.
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem, ended == ObjectIdentifier(item) else { return }
                self.isPlaying = false
            }
        }
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

    /// J-K-L (#230): `direction` 1 plays forward, −1 backward, 0 stops. Another tap in the same
    /// direction doubles the speed, up to 8×, as it does in every editor. Returns false when
    /// the picture cannot play backward, so the caller can step instead.
    @discardableResult
    func shuttle(_ direction: Int) -> Bool {
        guard direction != 0 else {
            player.pause()
            isPlaying = false
            return true
        }
        if direction < 0, player.currentItem?.canPlayReverse != true { return false }
        let current = player.rate
        let speed: Float =
            (current != 0 && (current > 0) == (direction > 0)) ? min(abs(current) * 2, 8) : 1
        if direction > 0, duration > 0, currentTime >= duration - 0.02 { seek(to: 0) }
        player.rate = speed * Float(direction)
        isPlaying = player.rate != 0
        return true
    }

    /// The shuttle speed, signed: 2 is forward at double speed.
    var rate: Float { player.rate }

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
