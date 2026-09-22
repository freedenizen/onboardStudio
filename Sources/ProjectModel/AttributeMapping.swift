import Foundation

/// One row of the attribute mapping table (#111, #89): for a single attribute — speed, brake,
/// lateral G — where it comes from, what the file's numbers are in, and what objects show it in.
///
/// Every field is optional and `nil` means *automatic*: follow whatever the level above decided,
/// and if no level has an opinion, whatever the importer detected. That is what makes an absent
/// row and a row full of `nil` mean the same thing, and what lets a user clear one field back to
/// automatic without clearing the others.
///
/// The unit fields are text (`kPa`, `km/h`) rather than a `TelemetryUnit`, for the same reason
/// `roleOverrides` and `unitOverrides` above them are: `ProjectModel` is a leaf target that holds
/// the document schema and does not depend on `TelemetryKit`. `TelemetryUnit(parsing:)` round-trips
/// the symbols, and a unit this build has never heard of survives being saved and reopened instead
/// of decoding to nothing.
public struct AttributeMapping: Hashable, Codable, Sendable {
    /// Column of the source file that supplies this attribute, e.g. `canbus:front_brake_pressure`.
    /// `nil` leaves it to whichever column the importer matched to this attribute.
    public var source: String?
    /// What that column's numbers are in — the unit values are *read* as. `nil` takes the file's
    /// own declaration, or the importer's guess from the column name. Setting this never changes
    /// how a value is shown; that is `displayUnit`.
    public var sourceUnit: String?
    /// What every object shows this attribute in unless it pins its own. `nil` shows it in the
    /// source unit, which is what *Automatic* means for an attribute (#89).
    ///
    /// Meaningless for a `state` attribute, which has no unit to be shown in; that is what
    /// `threshold` is for.
    public var displayUnit: String?
    /// The level at or above which a **state** attribute reads as on (#191).
    ///
    /// A logger rarely records a state as a boolean — the reference session carries ABS as a raw
    /// analog channel reading 512…2800 — so what a state attribute needs is a level to cross, not
    /// a unit. `nil` leaves it to the suggestion derived from the channel's own range.
    public var threshold: Double?

    public init(
        source: String? = nil, sourceUnit: String? = nil, displayUnit: String? = nil, threshold: Double? = nil
    ) {
        self.source = source
        self.sourceUnit = sourceUnit
        self.displayUnit = displayUnit
        self.threshold = threshold
    }

    /// True when the row says nothing — every field is automatic. Such a row is dropped on the way
    /// into a table so that "the user cleared every field" and "the user never touched this
    /// attribute" are the same saved document.
    public var isAutomatic: Bool {
        source == nil && sourceUnit == nil && displayUnit == nil && threshold == nil
    }

    /// This row's opinions, with `fallback` filling in every field this row leaves automatic.
    /// Field by field, deliberately: pinning a display unit must not also pin the source column.
    public func resolved(under fallback: AttributeMapping) -> AttributeMapping {
        AttributeMapping(
            source: source ?? fallback.source,
            sourceUnit: sourceUnit ?? fallback.sourceUnit,
            displayUnit: displayUnit ?? fallback.displayUnit,
            threshold: threshold ?? fallback.threshold)
    }
}

/// Which field of a mapping a caller is asking about, so that a control can report where the value
/// it is showing came from without three near-identical lookups.
public enum AttributeMappingField: String, Hashable, Sendable, CaseIterable {
    case source, sourceUnit, displayUnit, threshold
}

/// The whole table: one row per attribute, keyed by `ChannelRole.identifier` (`speed`, `brake`,
/// `canbus:front_brake_pressure`).
///
/// Keyed by the identifier string rather than the role itself because `ChannelRole` lives in
/// `TelemetryKit` — see the note on `AttributeMapping`. `ChannelRole(identifier:)` turns a key back
/// into a role wherever one is needed.
public struct AttributeMappingTable: Hashable, Codable, Sendable {
    public private(set) var rows: [String: AttributeMapping]

    public init(_ rows: [String: AttributeMapping] = [:]) {
        self.rows = rows.filter { !$0.value.isAutomatic }
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// The row for an attribute. Reading an attribute nobody has touched gives a fully automatic
    /// row rather than `nil`, because "no opinion" is a valid answer and every caller wants it.
    /// Writing a fully automatic row removes it.
    public subscript(role: String) -> AttributeMapping {
        get { rows[role] ?? AttributeMapping() }
        set { rows[role] = newValue.isAutomatic ? nil : newValue }
    }

    /// Encoded as the bare dictionary, so a saved project reads as
    /// `"attributeMappings": { "brake": { "sourceUnit": "kPa", "displayUnit": "bar" } }`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(try c.decode([String: AttributeMapping].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rows)
    }

    /// The table as JSON text, which is how the global level is stored: `@AppStorage` carries
    /// property-list values, and a dictionary of structs is not one. Empty text for an empty
    /// table, so an untouched preference and a cleared one read alike.
    public var json: String {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Reads back `json`. Unreadable text gives an empty table rather than throwing: a corrupted
    /// preference should cost the user their saved mapping, not the ability to open a project.
    public init(json: String) {
        guard let data = json.data(using: .utf8),
            let table = try? JSONDecoder().decode(AttributeMappingTable.self, from: data)
        else {
            self.init()
            return
        }
        self = table
    }
}

/// Which level of the chain supplied a mapping field.
///
/// The order is the resolution order: an input's word beats the project's, which beats the global
/// preference, and `automatic` means nobody had an opinion and the importer decides.
public enum AttributeMappingLevel: String, Hashable, Sendable, CaseIterable {
    case input, project, global, automatic

    /// How a control describes a value it did not itself set.
    public var describedAsInherited: String? {
        switch self {
        case .input: nil
        case .project: "from this project"
        case .global: "from Settings"
        case .automatic: "from the data"
        }
    }
}

/// Resolves #111's chain for one data input: **input → project → global → automatic**.
///
/// The same shape as `UnitResolver`, which does this for speed alone (#75), generalised to every
/// attribute and to all three of the table's columns. Each level stores only what somebody pinned,
/// so changing a global moves every project and input that has not pinned that field, and leaves
/// the pinned ones alone. That is the point, not a side effect.
public struct AttributeMappingResolver: Hashable, Sendable {
    /// The mapping saved in app preferences: "in my files, Brake press is the brake channel, in
    /// kPa". Set once, applied to every later import.
    public var global: AttributeMappingTable
    /// This project's deviations from the global mapping.
    public var project: AttributeMappingTable
    /// This input's deviations, for when one file is the exception.
    public var input: AttributeMappingTable

    public init(
        global: AttributeMappingTable = AttributeMappingTable(),
        project: AttributeMappingTable = AttributeMappingTable(),
        input: AttributeMappingTable = AttributeMappingTable()
    ) {
        self.global = global
        self.project = project
        self.input = input
    }

    /// The mapping actually in force for an attribute. Fields that no level pinned stay `nil`,
    /// which is the importer's cue to decide.
    public func resolved(_ role: String) -> AttributeMapping {
        input[role].resolved(under: project[role]).resolved(under: global[role])
    }

    /// Which level supplied one field, so a control can say so rather than showing a bare value.
    public func level(of field: AttributeMappingField, for role: String) -> AttributeMappingLevel {
        for (level, table) in [(AttributeMappingLevel.input, input), (.project, project), (.global, global)]
        where table[role][keyPath: Self.keyPath(field)] != nil {
            return level
        }
        return .automatic
    }

    /// The table one level stores, on its own — what a control editing that level reads and
    /// writes. `automatic` stores nothing, so it reads empty and ignores a write.
    public subscript(level: AttributeMappingLevel) -> AttributeMappingTable {
        get {
            switch level {
            case .input: input
            case .project: project
            case .global: global
            case .automatic: AttributeMappingTable()
            }
        }
        set {
            switch level {
            case .input: input = newValue
            case .project: project = newValue
            case .global: global = newValue
            case .automatic: break
            }
        }
    }

    /// What the chain would say if `level` had no opinion: the value a control at that level shows
    /// as its placeholder, and exactly what clearing it back to automatic will produce.
    public func inherited(_ role: String, below level: AttributeMappingLevel) -> AttributeMapping {
        switch level {
        case .input: project[role].resolved(under: global[role])
        case .project: global[role]
        case .global, .automatic: AttributeMapping()
        }
    }

    /// Every attribute any level has an opinion about — the rows a table view has to show on top
    /// of the ones the loaded data suggests.
    public var mappedRoles: Set<String> {
        Set(global.rows.keys).union(project.rows.keys).union(input.rows.keys)
    }

    private static func keyPath(_ field: AttributeMappingField) -> KeyPath<AttributeMapping, String?> {
        switch field {
        case .source: \.source
        case .sourceUnit: \.sourceUnit
        case .displayUnit: \.displayUnit
        // A threshold is a number, so it has no `String?` to report a level for. Asking which
        // level set it is not a question any control needs to ask.
        case .threshold: \.source
        }
    }
}
