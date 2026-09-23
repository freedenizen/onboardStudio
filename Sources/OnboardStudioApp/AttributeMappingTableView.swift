import ProjectModel
import SwiftUI
import TelemetryKit

/// What this input's attributes are mapped to, as much of it as an inspector column can usefully
/// say, and the way to the window that does the mapping (#192).
struct DataInputAttributesSection: View {
    @Bindable var editor: EditorModel
    let input: Input
    let settings: DataInputSettings
    let session: TelemetrySession?

    @AppStorage(Preferences.attributeMappings.key) private var globalMappings = Preferences.attributeMappings.unset

    private var mappings: AttributeMappingResolver {
        AttributeMappingResolver(
            global: AttributeMappingTable(json: globalMappings),
            project: editor.project.settings.attributeMappings,
            input: settings.attributeMappings)
    }

    /// Attributes some level has an opinion about, which is what there is to summarise. A file
    /// that nobody has mapped anything for has nothing to say here.
    private var mapped: [ChannelRole] {
        let opinionated = Set(mappings.mappedRoles.compactMap(ChannelRole.init(identifier:)))
        return ChannelRole.mappableAttributes.filter(opinionated.contains)
    }

    var body: some View {
        Section {
            if let session {
                if mapped.isEmpty {
                    Text("Nothing mapped yet; the importer's own reading of this file is in use.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(mapped, id: \.identifier) { role in
                        LabeledContent(role.displayName) {
                            Text(summary(of: role)).foregroundStyle(.secondary).lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("attribute.\(role.identifier)")
                    }
                }
                importStatus(session.importReport)
            } else {
                // Says what is loading, so a slow file is not mistaken for a stuck one.
                ProgressView {
                    Text("Reading \(input.label)…")
                }
                .controlSize(.small)
            }
            if hasColumnSettings {
                columnSettingsNotice
            }
            OpenAttributeWindowButton(scope: .input(input.id))
        } header: {
            Text("Attributes")
        } footer: {
            Text(
                "Where each attribute comes from, the unit its numbers are read in, and the unit "
                    + "objects show it in. The window's Import tab (⌘2) says what became of every column."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// How the import went, in a line (#149, #215). The whole report is the window's Import tab.
    @ViewBuilder
    private func importStatus(_ report: ImportReport) -> some View {
        if report.columns.isEmpty {
            Text("Nothing imported yet.").font(.caption).foregroundStyle(.secondary)
        } else if report.needingAttention.isEmpty {
            Label("Every column read cleanly.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("import.clean")
        } else {
            Label(report.summary, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("import.inspectorSummary")
        }
    }

    /// Column-by-column settings saved by a version before the attribute window: they still apply,
    /// and win over a mapping for the same column, so they are said out loud rather than hidden,
    /// with the way to let the attribute mapping take over.
    private var hasColumnSettings: Bool { !settings.roleOverrides.isEmpty || !settings.unitOverrides.isEmpty }

    private var columnSettingsNotice: some View {
        let count = Set(settings.roleOverrides.keys).union(settings.unitOverrides.keys).count
        return VStack(alignment: .leading) {
            Text(
                "\(count) column\(count == 1 ? "" : "s") keep\(count == 1 ? "s" : "") a meaning or unit set in an "
                    + "earlier version, which wins over the attribute mapping."
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Clear Column Settings") {
                editor.updateInput(input.id, name: "Clear Column Settings") {
                    guard case .data(var new) = $0.kind else { return }
                    new.roleOverrides = [:]
                    new.unitOverrides = [:]
                    $0.kind = .data(new)
                }
            }
            .help("Let the attribute mapping decide what these columns mean and are read in")
            .accessibilityIdentifier("data.clearColumnSettings")
        }
    }

    /// The column the importer matched to each attribute, so a row that pins only a unit still
    /// says where its numbers come from (#196).
    private var detectedSources: [String: String] {
        guard let session else { return [:] }
        return session.channels.reduce(into: [:]) { sources, entry in
            sources[entry.key.identifier] = entry.value.name
        }
    }

    private func summary(of role: ChannelRole) -> String {
        let resolved = mappings.resolved(role.identifier)
        var parts: [String] = []
        if let source = resolved.source ?? detectedSources[role.identifier] { parts.append(source) }
        if role.kind == .state {
            parts.append(resolved.threshold.map { "on at \($0)" } ?? "on automatically")
        } else if let unit = resolved.sourceUnit {
            parts.append(resolved.displayUnit.map { "\(unit) → \($0)" } ?? unit)
        } else if let display = resolved.displayUnit {
            parts.append("shown in \(display)")
        }
        return parts.isEmpty ? "Automatic" : parts.joined(separator: " · ")
    }
}
