import ProjectModel
import SwiftUI

@main
struct OverlayGenApp: App {
    @State private var updater = UpdaterModel()

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environment(updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
