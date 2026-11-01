import Foundation

/// What the Coaching window reads (#321): which data input, which lap, against what.
///
/// Saved in the project so the window shows the same analysis when the project is reopened, and
/// so changing the reference is an undoable edit. The analysis itself is never saved: it is
/// derived from the data every time.
public struct CoachingSettings: Hashable, Codable, Sendable {
    /// What the lap is compared with.
    public enum Reference: Hashable, Codable, Sendable {
        /// The session's quickest complete lap.
        case sessionBest
        /// A particular lap of the same data input.
        case lap(Int)
        /// The quickest lap-length stretch of the session, starting anywhere.
        case fastestRolling
        /// The best sector of each lap joined into one.
        case compositeOptimal
        /// A lap of another data input: another session, or another driver.
        case otherInput(dataInputID: InputID, lap: Int)
    }

    /// The data input the lap comes from.
    public var dataInputID: InputID
    /// The lap to read; `nil` follows the playhead.
    public var lap: Int?
    public var reference: Reference

    public init(dataInputID: InputID, lap: Int? = nil, reference: Reference = .sessionBest) {
        self.dataInputID = dataInputID
        self.lap = lap
        self.reference = reference
    }
}
