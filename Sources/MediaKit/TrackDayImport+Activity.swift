import Foundation

extension TrackDayImport {
    /// Where one Add Files has got to.
    public enum Phase: Sendable, Equatable {
        /// Behind another import, which is read first: two at once could each add the same file.
        case waiting
        case reading
        /// Files of another day are waiting to be told where they go.
        case asking
        case placing
        case done
    }

    /// An import as the Logbook window shows it while its sheet is away (#664): the sheet's only
    /// button closed it, the files went on being read with nothing to say so, and the report —
    /// where a file that was not read is named — never came back.
    public struct Activity: Sendable, Equatable {
        public var phase: Phase
        /// The file being read, once the folders are listed.
        public var step: Step?
        /// Its sheet was sent away with Continue in Background.
        public var isInBackground: Bool

        public init(phase: Phase, step: Step? = nil, isInBackground: Bool = false) {
            self.phase = phase
            self.step = step
            self.isInBackground = isInBackground
        }

        /// The sheet comes back unasked: there is a question only the user can answer, or the
        /// report to read.
        public var wantsItsSheet: Bool { isInBackground && (phase == .asking || phase == .done) }

        /// The files are still being read or filed, so closing the sheet does not end the import.
        public var isWorking: Bool { phase == .waiting || phase == .reading || phase == .placing }

        /// What the sheet's button says: while files are read it sends the sheet away and the
        /// import goes on, which "Close" did not say.
        public var closeTitle: String { phase == .done ? "Done" : "Continue in Background" }

        /// The line beside the progress bar.
        public var line: String {
            switch phase {
            case .waiting: "Waiting for the files before these…"
            case .reading: step?.sentence ?? "Looking for files…"
            case .asking: "Some files are from another day."
            case .placing: "Adding…"
            case .done: "The files are in the logbook."
            }
        }

        /// How far through, where that is known: `nil` draws a bar that only says it is busy.
        public var fraction: Double? {
            switch phase {
            case .reading: step.map { Double($0.index) / Double(max($0.count, 1)) }
            case .asking, .done: 1
            case .waiting, .placing: nil
            }
        }

        /// The button that brings the sheet back.
        public var showTitle: String {
            switch phase {
            case .done: "Show Report"
            case .asking: "Answer…"
            case .waiting, .reading, .placing: "Show Progress"
            }
        }

        /// What the project's status line says when the sheet is sent away from its window.
        public static let sentToBackground =
            "Adding the files to the logbook. The report comes back when they are in."
    }
}
