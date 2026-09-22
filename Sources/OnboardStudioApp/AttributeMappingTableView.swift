import ProjectModel
import SwiftUI
import TelemetryKit

/// The attribute mapping table (#111, #89): one row per attribute, three columns — where it comes
/// from, what the file's numbers are read in, and what objects show it in.
///
/// Asks the question in the direction the user asks it — "where does Brake come from?" — which is
/// the reverse of `ChannelMappingRow`'s "what is this column?". Both directions exist: this one is
/// how a mapping is *set*, that one is how one file is read.
///
/// One view for every level of the chain. It edits the level it is given, and each pop-up's
/// *Automatic* entry names what the levels above already decided, so a row that pins nothing still
/// says what it is going to do.
struct AttributeMappingTableView: View {
    /// The level this view writes to.
    let level: AttributeMappingLevel
    let resolver: AttributeMappingResolver
    /// Column names to offer as sources. Empty where no file is open, and then the pop-up offers
    /// only what some level already chose.
    var columns: [String] = []
    /// Every attribute that could have a row, in the order to show them.
    let attributes: [ChannelRole]
    /// The unit the file itself declared for each attribute, keyed by role identifier. This is
    /// what *Automatic* means in the "Reads" column, and what the "Shows" column's choices are
    /// derived from when nobody has overridden it.
    var detectedUnits: [String: TelemetryUnit] = [:]
    /// Attributes worth showing before the user asks for the rest — the ones this file supplies or
    /// somebody has already mapped.
    let interesting: Set<ChannelRole>
    /// Applies an edited row. The caller decides how it is recorded — an undoable project edit for
    /// a project or an input, a preference write for the global level.
    let write: (ChannelRole, AttributeMapping) -> Void

    @State private var showAll = false

    private var shown: [ChannelRole] {
        showAll ? attributes : attributes.filter(interesting.contains)
    }

    var body: some View {
        ForEach(shown, id: \.identifier) { role in
            AttributeMappingRow(
                role: role, level: level, resolver: resolver, columns: columns,
                detected: detectedUnits[role.identifier], write: { write(role, $0) })
        }
        if shown.count < attributes.count || showAll {
            Toggle("Show every attribute", isOn: $showAll)
                .accessibilityIdentifier("attributes.showAll")
        }
    }
}

/// One attribute: its name, the mapping in force, and the three columns that set it.
private struct AttributeMappingRow: View {
    let role: ChannelRole
    let level: AttributeMappingLevel
    let resolver: AttributeMappingResolver
    let columns: [String]
    /// What the file said this attribute's numbers are in, if anything.
    let detected: TelemetryUnit?
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(role.displayName).lineLimit(1)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("attribute.\(role.identifier)")
            popUp(.source, automatic: "Any column")
            if role.kind == .state {
                // A state has no unit to be shown in; what it needs is the level at which the
                // channel it is mapped to counts as on.
                thresholdField
            } else {
                HStack(spacing: 6) {
                    popUp(.sourceUnit, automatic: "File's unit")
                    popUp(.displayUnit, automatic: "As read")
                }
            }
        }
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
        LabeledContent("On at or above") {
            TextField(
                "Automatic",
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

/// The attribute table as the data input inspector shows it: this input's level of the chain, with
/// the columns the open file actually offers.
struct DataInputAttributesSection: View {
    @Bindable var editor: EditorModel
    let input: Input
    let settings: DataInputSettings
    let session: TelemetrySession?

    @AppStorage(Preferences.attributeMappings.key) private var globalMappings = Preferences.attributeMappings.unset

    /// #111's chain as it stands for this input, so each row shows what every level decided.
    private var mappings: AttributeMappingResolver {
        AttributeMappingResolver(
            global: AttributeMappingTable(json: globalMappings),
            project: editor.project.settings.attributeMappings,
            input: settings.attributeMappings)
    }

    /// Worth showing before the user asks for every attribute: the ones this file already
    /// supplies, and the ones somebody has mapped.
    ///
    /// Only ever a *subset of the vocabulary*. A channel the file names itself — `canbus:analog_1`
    /// — is something an attribute is mapped **to**, never an attribute (#191); listing those made
    /// one car's wiring look like part of the vocabulary.
    private var interesting: Set<ChannelRole> {
        let fromData = Set(session?.orderedChannels.map(\.role) ?? [])
        let mapped = Set(mappings.mappedRoles.compactMap(ChannelRole.init(identifier:)))
        return Set(ChannelRole.mappableAttributes).intersection(fromData.union(mapped))
    }

    /// One row per attribute in the vocabulary, so an attribute the importer failed to find still
    /// has a row to fix it in.
    private var attributes: [ChannelRole] { ChannelRole.mappableAttributes }

    /// What the file declared for each attribute. The *recorded* unit, not the channel's own:
    /// speed is stored in m/s whatever the file wrote, and the table's "Reads" column is about
    /// what the file wrote.
    private var detectedUnits: [String: TelemetryUnit] {
        guard let session else { return [:] }
        return session.channels.reduce(into: [:]) { units, entry in
            units[entry.key.identifier] = session.recordedUnit(of: entry.key)
        }
    }

    var body: some View {
        Section {
            AttributeMappingTableView(
                level: .input, resolver: mappings, columns: session?.sourceColumns ?? [],
                attributes: attributes, detectedUnits: detectedUnits, interesting: interesting,
                write: { role, mapping in
                    var new = settings
                    new.attributeMappings[role.identifier] = mapping
                    editor.updateInput(input.id, name: "Change Attribute Mapping") { $0.kind = .data(new) }
                })
        } header: {
            Text("Attributes")
        } footer: {
            Text(
                "Where each attribute comes from, the unit its numbers are read in, and the unit "
                    + "objects show it in. Set it once in Settings and every later import follows; "
                    + "change it here when this file is the exception."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
