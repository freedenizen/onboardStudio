import ProjectModel
import SwiftUI
import TelemetryKit

/// One row per attribute, three columns, at whichever level of the chain the window is editing.
///
/// Laid out as columns rather than stacked, which is the whole reason for the window: the source,
/// what it is read in and what it is shown in are one row of a table, not three lines of a list.
struct AttributeMappingGrid: View {
    let scope: AttributeMappingWindow.Scope
    let editor: EditorModel?

    @AppStorage(Preferences.attributeMappings.key) private var globalMappings = Preferences.attributeMappings.unset
    @AppStorage(Preferences.speedUnit.key) private var appSpeedUnit = Preferences.speedUnit.unset
    @State private var showAll = false

    private static let sourceWidth: CGFloat = 220
    private static let unitWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            List {
                ForEach(rows, id: \.identifier) { role in
                    AttributeRow(
                        role: role, level: level, resolver: resolver, columns: sourceColumns,
                        detected: detectedUnits[role.identifier], sourceWidth: Self.sourceWidth,
                        unitWidth: Self.unitWidth, write: { write(role, $0) })
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Divider()
            footer
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Attribute").frame(maxWidth: .infinity, alignment: .leading)
            Text("From").frame(width: Self.sourceWidth, alignment: .leading)
            Text("Reads").frame(width: Self.unitWidth, alignment: .leading)
            Text("Shows").frame(width: Self.unitWidth, alignment: .leading)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Toggle("Show every attribute", isOn: $showAll)
                .accessibilityIdentifier("attributes.showAll")
            Spacer()
            Text(explanation).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var explanation: String {
        switch scope {
        case .global: "Set once here and every later import follows."
        case .project: "This project only; inputs and objects can still differ."
        case .input: "This file only, when it is the exception."
        }
    }

    // MARK: - What the chain looks like from here

    private var level: AttributeMappingLevel {
        switch scope {
        case .global: .global
        case .project: .project
        case .input: .input
        }
    }

    private var inputID: InputID? {
        if case .input(let id) = scope { return id }
        return nil
    }

    private var settings: DataInputSettings? {
        inputID.flatMap { editor?.project.input($0) }?.dataSettings
    }

    private var session: TelemetrySession? {
        guard let editor else { return nil }
        if let inputID { return editor.sessions[inputID] }
        return editor.project.dataInputs.first.flatMap { editor.sessions[$0.id] }
    }

    private var resolver: AttributeMappingResolver {
        AttributeMappingResolver(
            global: AttributeMappingTable(json: globalMappings),
            project: editor?.project.settings.attributeMappings ?? AttributeMappingTable(),
            input: settings?.attributeMappings ?? AttributeMappingTable())
    }

    /// The columns of the file being mapped. Empty for the global mapping, where no file is in
    /// view and the column a logger always writes has to be typed rather than picked.
    private var sourceColumns: [String] {
        scope == .global ? [] : (session?.sourceColumns ?? [])
    }

    private var detectedUnits: [String: TelemetryUnit] {
        guard let session else { return [:] }
        return session.channels.reduce(into: [:]) { units, entry in
            units[entry.key.identifier] = session.recordedUnit(of: entry.key)
        }
    }

    /// Attributes worth showing before every one is asked for: those this file supplies, and
    /// those some level has an opinion about. Always a subset of the vocabulary (#191).
    private var interesting: Set<ChannelRole> {
        let fromData = Set(session?.orderedChannels.map(\.role) ?? [])
        let mapped = Set(resolver.mappedRoles.compactMap(ChannelRole.init(identifier:)))
        return Set(ChannelRole.mappableAttributes).intersection(fromData.union(mapped))
    }

    private var rows: [ChannelRole] {
        showAll || interesting.isEmpty
            ? ChannelRole.mappableAttributes
            : ChannelRole.mappableAttributes.filter(interesting.contains)
    }

    private func write(_ role: ChannelRole, _ mapping: AttributeMapping) {
        switch scope {
        case .global:
            var table = AttributeMappingTable(json: globalMappings)
            table[role.identifier] = mapping
            globalMappings = table.json
        case .project:
            editor?.edit("Change Attribute Mapping") { $0.settings.attributeMappings[role.identifier] = mapping }
        case .input(let id):
            guard var new = settings else { return }
            new.attributeMappings[role.identifier] = mapping
            editor?.updateInput(id, name: "Change Attribute Mapping") { $0.kind = .data(new) }
        }
    }
}

/// One attribute: its name, the mapping in force, and the three columns that set it.
struct AttributeRow: View {
    let role: ChannelRole
    let level: AttributeMappingLevel
    let resolver: AttributeMappingResolver
    let columns: [String]
    /// What the file said this attribute's numbers are in, if anything.
    let detected: TelemetryUnit?
    let sourceWidth: CGFloat
    let unitWidth: CGFloat
    let write: (AttributeMapping) -> Void

    /// This level's own opinions — what the pop-ups edit.
    private var mine: AttributeMapping { resolver[level][role.identifier] }
    /// What the levels above already decided, which is what clearing a pop-up back to automatic
    /// leaves in place.
    private var inherited: AttributeMapping { resolver.inherited(role.identifier, below: level) }
    private var resolved: AttributeMapping { mine.resolved(under: inherited) }

    /// The unit the numbers are read in once the chain has had its say — and, failing that, what
    /// the file declared. What the third column may offer follows from it: a value in kPa can be
    /// shown in bar or psi and in nothing else.
    ///
    /// Falling back to the file matters: otherwise a channel the importer read perfectly well as
    /// kPa offers no display units at all until the user redundantly tells the app it is kPa.
    private var sourceUnit: TelemetryUnit? {
        resolved.sourceUnit.map { TelemetryUnit(parsing: $0) } ?? detected
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(role.displayName).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("attribute.\(role.identifier)")
            popUp(.source, automatic: "Any column").frame(width: sourceWidth)
            if role.kind == .state {
                // A state has no unit to be shown in; what it needs is the level at which the
                // channel it is mapped to counts as on. One field, spanning both unit columns.
                thresholdField.frame(width: unitWidth * 2 + 8)
            } else {
                popUp(.sourceUnit, automatic: "File's unit").frame(width: unitWidth)
                popUp(.displayUnit, automatic: "As read").frame(width: unitWidth)
            }
        }
        .padding(.vertical, 2)
    }

    /// A one-line statement of the mapping in force, so a row nobody has touched is still worth
    /// reading and a row somebody has is obvious.
    private var summary: String {
        var parts: [String] = []
        if let source = resolved.source { parts.append(source) }
        // A state has no unit to report; what it has is the level it counts as on at.
        if role.kind == .state {
            parts.append(resolved.threshold.map { "on at \($0)" } ?? "on automatically")
            return parts.isEmpty ? "Automatic" : parts.joined(separator: " · ")
        }
        // The effective source unit, so a file that declared one is reported even when no level
        // of the chain has overridden it (#187).
        if let unit = sourceUnit?.symbol, !unit.isEmpty {
            parts.append(resolved.displayUnit.map { "\(unit) → \($0)" } ?? unit)
        } else if let display = resolved.displayUnit {
            parts.append("shown in \(display)")
        }
        return parts.isEmpty ? "Automatic" : parts.joined(separator: " · ")
    }

    /// Every unit the app can read a column as, drawn from the families — so `none` and `count`,
    /// which measure nothing and convert to nothing, are not offered.
    private var unitSymbols: [String] { UnitFamily.allCases.flatMap(\.units).map(\.symbol) }

    /// #89: only the units this attribute can actually be shown in, so nobody is offered bar for
    /// throttle. With no source unit known there is nothing to convert between and the column
    /// offers only *Automatic*.
    private var displayUnitSymbols: [String] { (sourceUnit?.convertibleUnits ?? []).map(\.symbol) }

    /// The level a state attribute's channel counts as on at or above. Left empty it follows the
    /// suggestion an indicator derives from the channel's own range.
    private var thresholdField: some View {
        TextField(
            "On above…",
            text: Binding(
                get: { mine.threshold.map { "\($0)" } ?? "" },
                set: { text in
                    var mapping = mine
                    mapping.threshold = text.isEmpty ? nil : Double(text)
                    write(mapping)
                })
        )
        .accessibilityIdentifier("attribute.\(role.identifier).threshold")
    }

    private func options(_ field: AttributeMappingField) -> [String] {
        switch field {
        case .source: columns
        case .sourceUnit: unitSymbols
        case .displayUnit: displayUnitSymbols
        case .threshold: []
        }
    }

    /// One column of the row. The *Automatic* entry names what the levels above decided, which is
    /// both what the row will do and what choosing it again would restore.
    private func popUp(_ field: AttributeMappingField, automatic: String) -> some View {
        let mine = value(of: field, in: mine)
        // For the source unit, "what the level above said" is the file itself when no level spoke.
        let above =
            value(of: field, in: inherited)
            ?? (field == .sourceUnit ? detected.map(\.symbol).flatMap { $0.isEmpty ? nil : $0 } : nil)
        let options = options(field)
        return Picker(field.rawValue, selection: binding(field)) {
            Text(above.map { "Automatic (\($0))" } ?? automatic).tag("")
            if !options.isEmpty {
                Divider()
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            // A value chosen before this build knew the unit, or naming a column the open file does
            // not have, must stay selectable — otherwise opening the pop-up discards it silently.
            if let mine, !options.contains(mine) {
                Divider()
                Text(mine).tag(mine)
            }
        }
        .labelsHidden()
        .accessibilityIdentifier("attribute.\(role.identifier).\(field.rawValue)")
    }

    private func binding(_ field: AttributeMappingField) -> Binding<String> {
        Binding(
            get: { value(of: field, in: mine) ?? "" },
            set: { chosen in
                var mapping = mine
                let value = chosen.isEmpty ? nil : chosen
                switch field {
                case .source: mapping.source = value
                case .sourceUnit: mapping.sourceUnit = value
                case .displayUnit: mapping.displayUnit = value
                case .threshold: mapping.threshold = value.flatMap(Double.init)
                }
                write(mapping)
            })
    }

    private func value(of field: AttributeMappingField, in mapping: AttributeMapping) -> String? {
        switch field {
        case .source: mapping.source
        case .sourceUnit: mapping.sourceUnit
        case .displayUnit: mapping.displayUnit
        case .threshold: mapping.threshold.map { "\($0)" }
        }
    }
}
