import AVFoundation
import Foundation

/// The debrief read aloud (#335): each card's text and each corner's note spoken by the system
/// voice into short audio files, which the stitch lays under the picture, ducking the clips'
/// own sound while a note plays. Off unless asked for.
public struct DebriefNarration: Sendable {
    public struct Piece: Sendable, Equatable {
        public let url: URL
        public let seconds: Double
    }

    public var title: Piece?
    /// One per corner of the plan, in the plan's order; `nil` where there was nothing to say.
    public var corners: [Piece?]
    public var closing: Piece?

    /// How long the voice needs after its last word before the picture moves on.
    public static let tail = 0.8

    /// A plan long enough for its narration: a card plays at least as long as its words.
    public func fitting(_ plan: DebriefPlan) -> DebriefPlan {
        var fitted = plan
        if let title { fitted.title.seconds = max(plan.title.seconds, title.seconds + Self.tail) }
        if let closing { fitted.closing.seconds = max(plan.closing.seconds, closing.seconds + Self.tail) }
        return fitted
    }
}

public enum DebriefNarrator {
    public enum Failure: Error, LocalizedError {
        case noVoice
        case timedOut
        public var errorDescription: String? {
            switch self {
            case .noVoice: "No system voice is available to read the notes."
            case .timedOut: "The system voice did not answer in time."
            }
        }
    }

    /// Whether this Mac can speak at all.
    public static var isAvailable: Bool { !AVSpeechSynthesisVoice.speechVoices().isEmpty }

    /// Speaks every part of `plan` into `folder`. The title card reads its lines, each corner its
    /// headline and what to try, the closing card its experiments.
    public static func narrate(_ plan: DebriefPlan, into folder: URL) async throws -> DebriefNarration {
        guard isAvailable else { throw Failure.noVoice }
        var narration = DebriefNarration(title: nil, corners: [], closing: nil)
        let titleText = ([plan.title.title] + plan.title.lines).joined(separator: ". ")
        narration.title = try await speak(titleText, to: folder.appending(path: "narration-title.caf"))
        for (index, corner) in plan.corners.enumerated() {
            let text = index < plan.cornerNotes.count ? plan.cornerNotes[index] : corner.title
            narration.corners.append(
                try await speak(text, to: folder.appending(path: String(format: "narration-%02d.caf", index + 1))))
        }
        let closingText = ([plan.closing.title] + plan.closing.lines).joined(separator: " ")
        narration.closing = try await speak(closingText, to: folder.appending(path: "narration-closing.caf"))
        return narration
    }

    /// `text` spoken into a Core Audio file at `url`; its length in seconds.
    public static func speak(_ text: String, to url: URL, timeout: Duration = .seconds(60)) async throws
        -> DebriefNarration.Piece
    {
        try? FileManager.default.removeItem(at: url)
        let writer = SpeechWriter(url: url)
        let seconds = try await withThrowingTaskGroup(of: Double.self) { group in
            group.addTask { try await writer.write(text) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.timedOut
            }
            let first = try await group.next() ?? 0
            group.cancelAll()
            return first
        }
        return DebriefNarration.Piece(url: url, seconds: seconds)
    }
}

/// Drives one `AVSpeechSynthesizer.write` and collects its buffers into a file. The synthesizer
/// and the file are touched only from the synthesizer's callback, in order.
private final class SpeechWriter: @unchecked Sendable {
    private let url: URL
    private let synthesizer = AVSpeechSynthesizer()
    private var file: AVAudioFile?
    private var frames: Int64 = 0
    private var sampleRate = 22_050.0
    private var finished = false

    init(url: URL) { self.url = url }

    func write(_ text: String) async throws -> Double {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.write(utterance) { [self] buffer in
                guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finished = true
                    continuation.resume(returning: Double(frames) / sampleRate)
                    return
                }
                do {
                    if file == nil {
                        sampleRate = pcm.format.sampleRate
                        file = try AVAudioFile(
                            forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat,
                            interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                    frames += Int64(pcm.frameLength)
                } catch {
                    finished = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
