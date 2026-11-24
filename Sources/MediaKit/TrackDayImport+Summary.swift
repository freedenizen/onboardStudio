import Foundation

extension TrackDayImport {
    /// The report's first line: "9 sessions added, 3 of them from camera recordings with no logger
    /// session, 9 clips, 1 already in the logbook, 2 not read."
    ///
    /// The sessions counted are the ones the logbook's table then shows. A recording that matched
    /// no logger session is read as a session of its own, and was counted as a clip alone: the
    /// line said six sessions and the table had nine (#665). `onChosenDay` is for files added to a
    /// day chosen first, where a session that went elsewhere is said to have (#456).
    public static func summary(of reports: [Report], onChosenDay: Bool) -> String {
        guard !reports.isEmpty else { return "Nothing in those files that this app reads." }
        let added = reports.filter(\.isAdded).count
        let fromClips = reports.filter(\.madeSession).count
        let sessions = added + fromClips
        let skipped = reports.filter(\.isAlreadyThere).count
        let clips = reports.filter(\.isClip).count
        var parts = ["\(sessions) session\(sessions == 1 ? "" : "s") added"]
        let elsewhere = onChosenDay ? reports.filter { $0.isAdded && $0.dayLabel != nil }.count : 0
        if elsewhere > 0 {
            let days = elsewhere == 1 ? "its own day" : "their own days"
            parts.append(elsewhere == sessions ? "on \(days)" : "\(elsewhere) of them on \(days)")
        }
        if fromClips > 0 {
            let recordings = fromClips == 1 ? "a camera recording" : "camera recordings"
            let whose = fromClips == sessions ? "" : "\(fromClips) of them "
            parts.append("\(whose)from \(recordings) with no logger session")
        }
        if clips > 0 { parts.append("\(clips) clip\(clips == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) already in the logbook") }
        let rest = reports.count - added - skipped - clips
        if rest > 0 { parts.append("\(rest) not read") }
        return parts.joined(separator: ", ") + "."
    }

    /// Where a batch has got to, for a progress bar that knows its total (#665): the file being
    /// read is `index + 1` of `count`. A recording in chapters is one.
    public struct Step: Sendable, Equatable {
        public var index: Int
        public var count: Int
        public var name: String

        public init(index: Int, count: Int, name: String) {
            self.index = index
            self.count = count
            self.name = name
        }

        /// "Reading 3 of 20: session_3.csv…"
        public var sentence: String { "Reading \(index + 1) of \(count): \(name)…" }
    }
}
