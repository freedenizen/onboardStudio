import ProjectModel
import SwiftUI

/// The Preferences window.
struct SettingsView: View {
    @Environment(UpdaterModel.self) private var updater
    @AppStorage("defaultExportPreset") private var defaultExportPreset = "project"
    @AppStorage("ffmpegPath") private var ffmpegPath = ""
    @AppStorage("nudgeStepPercent") private var nudgeStep = 1.0
    @AppStorage("youtubeClientID") private var youtubeClientID = ""
    @AppStorage("youtubeClientSecret") private var youtubeClientSecret = ""
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
                    Text("0.5 %").tag(0.5)
                    Text("1 %").tag(1.0)
                    Text("2 %").tag(2.0)
                }
                Text("Hold ⇧ for five times the step.").font(.caption).foregroundStyle(.secondary)
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
