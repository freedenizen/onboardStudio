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
    /// Line the two laps up by place rather than metre for metre (#333): for two laps of one
    /// session driven on deliberately different lines, where distance into the lap drifts
    /// through the corner. Off is how every reading was made before it existed.
    public var alignByPosition: Bool

    public init(
        dataInputID: InputID, lap: Int? = nil, reference: Reference = .sessionBest, alignByPosition: Bool = false
    ) {
        self.dataInputID = dataInputID
        self.lap = lap
        self.reference = reference
        self.alignByPosition = alignByPosition
    }

    private enum CodingKeys: String, CodingKey { case dataInputID, lap, reference, alignByPosition }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dataInputID = try c.decode(InputID.self, forKey: .dataInputID)
        lap = try c.decodeIfPresent(Int.self, forKey: .lap)
        reference = try c.decodeIfPresent(Reference.self, forKey: .reference) ?? .sessionBest
        alignByPosition = try c.decodeIfPresent(Bool.self, forKey: .alignByPosition) ?? false
    }
}
