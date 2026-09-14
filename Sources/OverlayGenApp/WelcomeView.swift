import ProjectModel
import SwiftUI

struct WelcomeView: View {
    @Environment(UpdaterModel.self) private var updater

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("OverlayGen")
                .font(.largeTitle.weight(.semibold))
            Text("Version \(OverlayGenVersion.marketing) (\(buildNumber))")
                .foregroundStyle(.secondary)
            Text(
                updater.canCheckForUpdates
                    ? "Automatic updates enabled."
                    : "Automatic updates unavailable in this build."
            )
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 300)
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }
}
