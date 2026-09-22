import Foundation

/// What became of every column of a data file (#149).
///
/// A file that imports badly explains nothing on its own: the channel list shows what survived and
/// says nothing about what did not, or about what quietly lost its meaning on the way in. This is
/// the record of the decisions, kept so the app can show them rather than leaving the user to
/// infer them from what is missing.
///
/// "Badly" is rarely a column being rejected. In a real CAN log every column becomes a channel and
/// the trouble is elsewhere: three columns called `speed`, of which one keeps the role and two are
/// renamed; an analog input with no unit and no name anyone recognises; a sensor that read the
/// same number for the whole session.
public struct ImportReport: Hashable, Sendable {
    /// One column of the file, and what happened to it.
    public struct Column: Hashable, Sendable, Identifiable {
        /// Unique within a report even when two columns share a name, which is the interesting
        /// case: `speed` appears three times in a RaceChrono CAN log.
        public var id: Int
        public var name: String
        /// The file's own grouping for it — RaceChrono's `200: canbus`, and whatever the other
        /// formats call theirs. `nil` when the format has no such idea.
        public var source: String?
        /// The unit its numbers were read in, after any override the user set.
        public var unit: TelemetryUnit
        /// The channel it became, or `nil` when no channel was built from it.
        public var role: ChannelRole?
        public var notes: [Note]

        public init(
            id: Int, name: String, source: String? = nil, unit: TelemetryUnit = .none,
            role: ChannelRole? = nil, notes: [Note] = []
        ) {
            self.id = id
            self.name = name
            self.source = source
            self.unit = unit
            self.role = role
            self.notes = notes
        }

        /// Whether anything here is worth the user's attention. A column that was read cleanly
        /// into the role it asked for needs no explaining.
        public var needsAttention: Bool { notes.contains { $0.isWarning } }
    }

    /// Something worth saying about one column.
    public enum Note: Hashable, Sendable {
        /// The role this column asked for was already another column's, so it was renamed.
        /// Carries the column that kept the role, because "which one won" is the actual question.
        case roleTaken(by: String, role: ChannelRole)
        /// Nothing in the name or the unit suggested a meaning, and nobody assigned one.
        case noMeaning
        /// No usable samples, so no channel was built.
        case empty
        /// Every sample was the same number. Usually a sensor that is not wired to anything.
        case constant(Double)
        /// The file gave a unit the app does not recognise, so the values belong to no family and
        /// cannot be converted or relabelled.
        case unknownUnit(String)
        /// The file gave no unit at all, so nothing is known about what the numbers mean.
        case noUnit
        /// The user pointed an attribute at this column, rather than the importer guessing.
        case mapped

        /// Whether this is a problem rather than a remark. `mapped` is the user being obeyed.
        public var isWarning: Bool {
            switch self {
            case .mapped: false
            case .roleTaken, .noMeaning, .empty, .constant, .unknownUnit, .noUnit: true
            }
        }
    }

    public var columns: [Column]

    public init(columns: [Column] = []) {
        self.columns = columns
    }

    /// Columns that became a channel.
    public var read: [Column] { columns.filter { $0.role != nil } }
    /// Columns no channel was built from.
    public var skipped: [Column] { columns.filter { $0.role == nil } }
    /// Columns worth looking at, whether or not they were read.
    public var needingAttention: [Column] { columns.filter(\.needsAttention) }

    /// A one-line statement of how the import went, for a panel header.
    public var summary: String {
        let read = read.count
        let attention = needingAttention.count
        let columns = "\(columns.count) column\(columns.count == 1 ? "" : "s")"
        let readPart = "\(columns), \(read) read"
        return attention == 0 ? readPart : "\(readPart), \(attention) worth a look"
    }
}

extension ImportReport.Note {
    /// How the note reads in the app, in the user's terms rather than the importer's.
    public var message: String {
        switch self {
        case .roleTaken(let owner, let role):
            "Another column (\(owner)) is already \(role.displayName), so this one was kept under its own name."
        case .noMeaning:
            "Nothing in the name or unit said what this is. Point an attribute at it to give it one."
        case .empty:
            "No usable values, so nothing was imported from it."
        case .constant(let value):
            "Every sample read \(Self.number(value)). A sensor that never changes is usually not connected."
        case .unknownUnit(let text):
            "The unit “\(text)” is not one this app knows, so these values cannot be converted or labelled."
        case .noUnit:
            "The file gave no unit, so the values cannot be converted. Set one under Attributes."
        case .mapped:
            "You pointed an attribute at this column."
        }
    }

    /// Trailing zeros help nobody in a sentence about a sensor reading the same thing all day.
    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9
            ? String(Int(value)) : String(format: "%.3f", value)
    }
}
