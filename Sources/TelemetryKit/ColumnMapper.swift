import Foundation

/// Decides what each column of a file becomes: which attribute it supplies, and the unit its
/// numbers are to be read in.
///
/// Two directions of mapping meet here (#111). `roleOverrides` / `unitOverrides` are keyed by
/// column — "what is this column?" — and `sourceColumns` / `sourceUnits` are keyed by attribute
/// — "where does Brake come from?". The column-keyed pair is consulted first throughout: it
/// names a column in this very file, so it is the most specific thing there is, and it means a
/// project saved before the attribute table existed keeps exactly the mapping it had.
struct ColumnMapper {
    let options: SessionBuilder.Options
    /// Which column each attribute was explicitly pointed at, so that a *guess* on an earlier
    /// column cannot take a role its named owner is waiting for.
    let claimedBy: [ChannelRole: String]
    private var usedRoles = Set<ChannelRole>()
    /// Which column actually took each role. Not the same as `claimedBy`, which is only what
    /// the user named: the usual case is three columns called `speed` and the first winning
    /// by file order, and "which one won" is exactly what the report has to answer.
    private var tookRole: [ChannelRole: String] = [:]

    init(options: SessionBuilder.Options) {
        self.options = options
        var claimedBy: [ChannelRole: String] = [:]
        for (column, role) in options.roleOverrides { claimedBy[role] = column }
        for (role, column) in options.sourceColumns where claimedBy[role] == nil { claimedBy[role] = column }
        self.claimedBy = claimedBy
    }

    /// What one column of the file becomes.
    struct Mapping {
        var role: ChannelRole
        var column: RawColumn
        /// The role it asked for, when another column already had it and this one was renamed.
        var demotedFrom: ChannelRole?
        /// Whether the user named this column rather than the importer guessing it.
        var wasNamed: Bool
    }

    /// The role this column takes and the column as it should be read, or `nil` to drop it
    /// because nothing claims it and nothing guessed it.
    mutating func map(_ column: RawColumn) -> Mapping? {
        let named = { (candidate: String) in candidate.caseInsensitiveCompare(column.name) == .orderedSame }
        let explicitRole =
            options.roleOverrides.first { named($0.key) }?.value
            ?? options.sourceColumns.first { named($0.value) }?.key
        guard let role = explicitRole ?? column.suggestedRole else { return nil }
        // First column wins for a given role; later duplicates become aux channels. A guessed
        // role whose attribute is explicitly mapped to some other column loses it outright,
        // whichever column the file happens to list first.
        let takenByItsOwner = explicitRole == nil && claimedBy[role].map { !named($0) } == true
        let finalRole: ChannelRole
        if usedRoles.contains(role) || takenByItsOwner {
            finalRole = .aux(column.name + (column.source.map { " (\($0))" } ?? ""))
        } else {
            finalRole = role
        }
        usedRoles.insert(finalRole)
        if finalRole == role { tookRole[role] = column.name }
        var effectiveColumn = column
        if let unit = options.unitOverrides.first(where: { named($0.key) })?.value
            ?? options.sourceUnits[finalRole]
        {
            effectiveColumn.unit = unit
        }
        return Mapping(
            role: finalRole, column: effectiveColumn,
            demotedFrom: finalRole == role ? nil : role, wasNamed: explicitRole != nil)
    }

    /// The column that kept `role`, for a column that was renamed out of it.
    func columnKeeping(_ role: ChannelRole) -> String? { tookRole[role] }

    /// One line of the import report (#149): what this column became, and anything about it worth
    /// the user's attention. `mapping` is `nil` when no channel was built from the column.
    static func reportedColumn(
        _ index: Int, _ column: RawColumn, mapping: Mapping?, mapper: ColumnMapper
    ) -> ImportReport.Column {
        var notes: [ImportReport.Note] = []
        if let mapping {
            if mapping.wasNamed { notes.append(.mapped) }
            if let wanted = mapping.demotedFrom {
                notes.append(.roleTaken(by: mapper.columnKeeping(wanted) ?? column.name, role: wanted))
            }
            // An `aux` channel nobody named is one the importer could make nothing of: it is in
            // the session under its own name and no object picker will suggest it for anything.
            if case .aux = mapping.role, mapping.demotedFrom == nil, !mapping.wasNamed {
                notes.append(.noMeaning)
            }
            let values = column.values.compactMap { $0 }
            if values.isEmpty {
                notes.append(.empty)
            } else if let first = values.first, values.allSatisfy({ $0 == first }) {
                notes.append(.constant(first))
            }
        } else {
            notes.append(column.values.contains { $0 != nil } ? .noMeaning : .empty)
        }
        switch column.unit {
        case .custom(let text): notes.append(.unknownUnit(text))
        // Only worth raising for a channel the app could not identify. A gear or a lap number is
        // measured in nothing, and saying so about every one of them buries the real warnings.
        case .none where mapping.map { !ChannelRole.standardRoles.contains($0.role) } ?? true:
            notes.append(.noUnit)
        default: break
        }
        return ImportReport.Column(
            id: index, name: column.name, source: column.source, unit: column.unit,
            role: mapping?.role, notes: notes)
    }
}
