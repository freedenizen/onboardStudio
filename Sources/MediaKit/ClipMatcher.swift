import CryptoKit
import Foundation
import GPMFKit
import ProjectModel
import TelemetryKit

/// A camera clip and the session it belongs to (#394): what the camera says about the clip —
/// when it started, by which clock, for how long, whether it has GPS — and the match of that
/// span against the day's sessions. The clocks decide; nothing about the content does.
public enum ClipMatcher {
    /// Camera clip extensions, as the editor accepts them.
    public static let clipExtensions: Set<String> = ["mp4", "mov", "360"]

    public static func isClip(_ url: URL) -> Bool { clipExtensions.contains(url.pathExtension.lowercased()) }

    /// The session among `sessions` whose time the clip falls in: by the clocks when both sides
    /// have one (the session the clip overlaps most), else the only session there is.
    public static func match(_ clip: ClipRecord, to sessions: [LogbookEntry]) -> (id: UUID, by: ClipRecord.Match)? {
        if let start = clip.recordedAt?.timeIntervalSince1970 {
            let end = start + max(clip.durationSeconds ?? 0, 0)
            var best: (id: UUID, overlap: Double)?
            for session in sessions {
                guard let date = session.date else { continue }
                let sessionStart = date.timeIntervalSince1970
                let sessionEnd = sessionStart + max(session.durationSeconds ?? 0, 0)
                let overlap = min(end, sessionEnd) - max(start, sessionStart)
                guard overlap >= 0, overlap > (best?.overlap ?? -1) else { continue }
                best = (session.id, overlap)
            }
            if let best { return (best.id, .clock) }
            // Dated sessions that the clock put the clip outside of: not theirs.
            if sessions.contains(where: { $0.date != nil }) { return nil }
        }
        if sessions.count == 1, let only = sessions.first { return (only.id, .onlySessionThatDay) }
        return nil
    }

    /// The clip's record: the recording's chapters, its length, when the camera's clock says it
    /// started and which clock that was, and a fingerprint of its bytes.
    public static func record(_ first: URL, chapters: [URL]) async throws -> ClipRecord {
        let info = try await MediaProbe.probe(first)
        var duration = info.duration
        for chapter in chapters {
            if let more = try? await MediaProbe.probe(chapter) { duration += more.duration }
        }
        let (hex, bytes) = try fingerprint(of: first)
        let bookmark =
            (try? first.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? first.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        var recordedAt: Date?
        var clock: String?
        if let start = TimestampSync.recordingStart(of: first, info: info) {
            recordedAt = Date(timeIntervalSince1970: start.epoch)
            clock = start.source
        } else if let values = try? first.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
            let date = values.creationDate ?? values.contentModificationDate
        {
            // A camera with no clock of its own: the file's own date is the last word there is.
            recordedAt = date
            clock = "file date"
        }
        return ClipRecord(
            path: first.path, bookmark: bookmark, byteCount: bytes, fingerprint: hex,
            chapterPaths: chapters.map(\.path), durationSeconds: duration > 0 ? duration : nil, recordedAt: recordedAt,
            clock: clock, hasGPS: info.hasGPMF)
    }

    /// SHA-256 of the first mebibyte and the file's length, hex — enough to know the file again
    /// without reading a 20 GB clip through — and the length.
    public static func fingerprint(of url: URL) throws -> (hex: String, byteCount: Int) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        if let head = try handle.read(upToCount: 1 << 20) { hasher.update(data: head) }
        hasher.update(data: Data(String(size).utf8))
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }

    /// "12:04–12:31, 27 min": the clip's span in words, for a report line or a row.
    public static func describe(_ clip: ClipRecord) -> String {
        var parts: [String] = []
        if let start = clip.recordedAt {
            var span = start.formatted(date: .omitted, time: .shortened)
            if let duration = clip.durationSeconds {
                span += "–" + start.addingTimeInterval(duration).formatted(date: .omitted, time: .shortened)
            }
            parts.append(span)
        }
        if let duration = clip.durationSeconds {
            let minutes = Int((duration / 60).rounded())
            parts.append(minutes >= 1 ? "\(minutes) min" : "\(Int(duration.rounded())) s")
        }
        if !clip.chapterPaths.isEmpty { parts.append("\(clip.chapterPaths.count + 1) chapters") }
        return parts.joined(separator: ", ")
    }
}
