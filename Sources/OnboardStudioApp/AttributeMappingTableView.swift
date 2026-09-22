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
            OpenAttributeWindowButton()
        } header: {
            Text("Attributes")
        } footer: {
            Text(
                "Where each attribute comes from, the unit its numbers are read in, and the unit "
                    + "objects show it in."
            )
            .font(.caption).foregroundStyle(.secondary)
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
