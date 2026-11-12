import AVKit
import SwiftUI

/// Watch, in a corner's step of the coaching walkthrough (#516): this lap's corner, then the
/// reference lap's, played in the window — Show Me moved a playhead the window itself covered.
struct CornerWatchView: View {
    let load: () async -> [WatchClip]

    @State private var playback = WatchPlayback()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let clips = playback.clips, !clips.isEmpty {
                VideoPlayer(player: playback.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("coaching.walkthrough.player")
                HStack(alignment: .firstTextBaseline) {
                    Button(playback.playing == nil ? "Watch" : "Watch Again", systemImage: "play.fill") {
                        playback.play()
                    }
                    .help(clips.count > 1 ? "Play this lap's corner, then the other lap's" : "Play this lap's corner")
                    .accessibilityIdentifier("coaching.walkthrough.watch")
                    Spacer()
                    Text(playback.playing.map { clips[$0].title } ?? clips.map(\.title).joined(separator: ", then "))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("coaching.walkthrough.watching")
                }
            } else if playback.clips != nil {
                Text("No video covers this corner.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("coaching.walkthrough.noVideo")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task { await playback.load(await load()) }
        .onDisappear { playback.stop() }
    }
}

/// The player behind Watch: each clip from its start to its end, one after the other.
@MainActor @Observable final class WatchPlayback {
    let player = AVPlayer()
    private(set) var clips: [WatchClip]?
    /// The clip playing, by its place in `clips`.
    private(set) var playing: Int?
    @ObservationIgnored private var boundary: Any?
    /// Each play counts up, so a clip ending after another play began does not run on.
    @ObservationIgnored private var run = 0

    /// The clips, the first one's opening frame shown.
    func load(_ clips: [WatchClip]) async {
        self.clips = clips
        if let first = clips.first { await cue(first) }
    }

    func play() {
        run += 1
        let token = run
        Task { await play(0, token: token) }
    }

    func stop() {
        run += 1
        stopObserving()
        player.pause()
        playing = nil
    }

    private func play(_ index: Int, token: Int) async {
        guard token == run else { return }
        stopObserving()
        guard let clips, clips.indices.contains(index) else {
            player.pause()
            playing = nil
            return
        }
        let clip = clips[index]
        await cue(clip)
        guard token == run else { return }
        playing = index
        boundary = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: Self.time(clip.range.upperBound))], queue: .main
        ) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.play(index + 1, token: token) }
            }
        }
        player.play()
    }

    private func cue(_ clip: WatchClip) async {
        player.pause()
        if player.currentItem !== clip.item { player.replaceCurrentItem(with: clip.item) }
        await player.seek(to: Self.time(clip.range.lowerBound), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stopObserving() {
        if let boundary { player.removeTimeObserver(boundary) }
        boundary = nil
    }

    private static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }
}
