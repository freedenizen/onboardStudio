import Foundation
import Observation

#if canImport(Sparkle)
    import Sparkle
#endif

/// Wraps Sparkle when it is linked (Xcode app target). Under plain `swift run` Sparkle is not
/// available and the model reports that updates are unavailable.
@Observable
final class UpdaterModel {
    private(set) var canCheckForUpdates = false

    #if canImport(Sparkle)
        private let controller: SPUStandardUpdaterController

        init() {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            canCheckForUpdates = controller.updater.canCheckForUpdates
            observeCanCheck()
        }

        private func observeCanCheck() {
            // Sparkle exposes canCheckForUpdates as KVO-compliant; poll cheaply on the main loop.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
                }
            }
        }

        func checkForUpdates() {
            controller.checkForUpdates(nil)
        }

        var automaticallyChecksForUpdates: Bool {
            get { controller.updater.automaticallyChecksForUpdates }
            set { controller.updater.automaticallyChecksForUpdates = newValue }
        }
    #else
        init() {}
        func checkForUpdates() {}
        var automaticallyChecksForUpdates = false
    #endif
}
