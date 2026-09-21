import ProjectModel
import SwiftUI

/// The Preferences window.
struct SettingsView: View {
    @Environment(UpdaterModel.self) private var updater
    @AppStorage(Preferences.defaultExportPreset.key) private var defaultExportPreset = Preferences
        .defaultExportPreset.unset
    @AppStorage(Preferences.ffmpegPath.key) private var ffmpegPath = Preferences.ffmpegPath.unset
    @AppStorage(Preferences.nudgeStepPixels.key) private var nudgeStep = Preferences.nudgeStepPixels.unset
    @AppStorage(Preferences.youTubeClientID.key) private var youtubeClientID = Preferences.youTubeClientID.unset
    @AppStorage(Preferences.youTubeClientSecret.key) private var youtubeClientSecret = Preferences
        .youTubeClientSecret.unset
    @Environment(YouTubeModel.self) private var youtube

    var body: some View {
        Form {
            Section("Export") {
                Picker("Default preset", selection: $defaultExportPreset) {
                    Text("Project size").tag("project")
                    ForEach(ExportSettings.namedPresets, id: \.key) { Text($0.name).tag($0.key) }
                }
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
