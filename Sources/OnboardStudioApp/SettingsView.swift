import ProjectModel
import SwiftUI
import TelemetryKit

/// The Preferences window.
struct SettingsView: View {
    @Environment(UpdaterModel.self) private var updater
    @AppStorage(Preferences.defaultExportPreset.key) private var defaultExportPreset = Preferences
        .defaultExportPreset.unset
    @AppStorage(Preferences.ffmpegPath.key) private var ffmpegPath = Preferences.ffmpegPath.unset
    @AppStorage(Preferences.speedUnit.key) private var speedUnit = Preferences.speedUnit.unset
    @AppStorage(Preferences.attributeMappings.key) private var attributeMappings = Preferences
        .attributeMappings.unset
    @AppStorage(Preferences.nudgeStepPixels.key) private var nudgeStep = Preferences.nudgeStepPixels.unset
    @AppStorage(Preferences.youTubeClientID.key) private var youtubeClientID = Preferences.youTubeClientID.unset
    @AppStorage(Preferences.youTubeClientSecret.key) private var youtubeClientSecret = Preferences
        .youTubeClientSecret.unset
    @Environment(YouTubeModel.self) private var youtube

    private var globalMappings: AttributeMappingTable { AttributeMappingTable(json: attributeMappings) }

    /// No file is open here, so the rows are the standard attributes plus any the user has already
    /// mapped — including channels their logger names itself, which are not standard roles.
    private var globalAttributes: [ChannelRole] {
        let mapped = globalMappings.rows.keys.compactMap(ChannelRole.init(identifier:))
        var seen = Set<ChannelRole>()
        return (ChannelRole.mappableAttributes + mapped).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section("Export") {
                Picker("Default preset", selection: $defaultExportPreset) {
                    Text("Project size").tag("project")
                    ForEach(ExportSettings.namedPresets, id: \.key) { Text($0.name).tag($0.key) }
                }
            }
            Section("Units") {
                Picker("Speed", selection: $speedUnit) {
                    ForEach(SpeedUnitSetting.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                .accessibilityIdentifier("settings.speedUnit")
                Text(
                    "Automatic shows speed in whatever unit the data file recorded it in. A project, "
                        + "and any single object, can still choose its own."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                AttributeMappingTableView(
                    level: .global, resolver: AttributeMappingResolver(global: globalMappings),
                    attributes: globalAttributes, interesting: Set(globalAttributes),
                    write: { role, mapping in
                        var table = globalMappings
                        table[role.identifier] = mapping
                        attributeMappings = table.json
                    })
            } header: {
                Text("Attributes")
            } footer: {
                Text(
                    "Set once here and every later import follows: which column of your files "
                        + "supplies each attribute, the unit its numbers are in, and the unit every "
                        + "object shows it in. A project, an input or a single object can still differ."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Editing") {
                Picker("Arrow keys move objects by", selection: $nudgeStep) {
                    Text("1 px").tag(1.0)
                    Text("2 px").tag(2.0)
                    Text("5 px").tag(5.0)
                }
                Text(
                    "Pixels of the exported frame, so the step is the same in a 1080p and a 4K "
                        + "project. Hold ⇧ for ten times the step. With nothing selected, the "
                        + "arrows step the playhead; , and . always do."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tools") {
                TextField("ffmpeg path", text: $ffmpegPath, prompt: Text("auto-detect (Homebrew)"))
                Text(
                    "Used to convert MTS, MKV and other containers macOS cannot open. "
                        + "Leave blank to search the usual Homebrew locations."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("YouTube") {
                TextField("OAuth client ID", text: $youtubeClientID)
                SecureField("OAuth client secret", text: $youtubeClientSecret)
                HStack {
                    Text(youtube.isSignedIn ? "Signed in." : "Not signed in.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign Out") { youtube.signOut() }.disabled(!youtube.isSignedIn)
                }
                Text(
                    "Create a Google Cloud OAuth client of type “TVs and Limited Input devices” with the "
                        + "YouTube Data API enabled; see docs/youtube.md."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: automaticUpdates)
                Button("Check Now") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }

    var automaticUpdates: Binding<Bool> {
        Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.automaticallyChecksForUpdates = $0 })
    }
}
