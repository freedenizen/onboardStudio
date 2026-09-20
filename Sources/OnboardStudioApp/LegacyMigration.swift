import Foundation

/// Carries a v0.19.0-or-earlier install across the rename from OverlayGen to Onboard Studio.
///
/// The rename changed the bundle identifier, which is the UserDefaults domain, and the Application
/// Support folder name. Without this the app would start with default settings and no saved
/// templates even though the user's files are still on disk. Runs once and records that it did, so
/// a later deliberate reset is not undone on the next launch.
enum LegacyMigration {
    static let bundleIdentifier = "com.freedenizen.overlaygen"
    static let supportDirectoryName = "OverlayGen"
    /// Set in the *new* domain once the migration has run.
    static let completedKey = "didMigrateFromOverlayGen"

    /// Settings worth carrying over. Deliberately explicit: copying a whole domain drags along
    /// window frames and other bundle-identifier-scoped state that no longer applies.
    static let settingKeys = [
        "ffmpegPath", "youtubeClientID", "youtubeClientSecret", "nudgeStepPercent",
        "showGettingStarted", "showLauncher", "NSShowAppCentricOpenPanelInsteadOfUntitledFile",
    ]

    static func run(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: completedKey) else { return }
        defaults.set(true, forKey: completedKey)
        migrateSettings(into: defaults)
        migrateSupportDirectory(using: fileManager)
    }

    private static func migrateSettings(into defaults: UserDefaults) {
        guard let old = UserDefaults(suiteName: bundleIdentifier) else { return }
        for key in settingKeys where defaults.object(forKey: key) == nil {
            guard let value = old.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
    }

    /// Moves `Application Support/OverlayGen` to `.../OnboardStudio`, which brings the user's saved
    /// templates and YouTube token with it. Copies rather than moves so a downgrade still works.
    private static func migrateSupportDirectory(using fileManager: FileManager) {
        guard
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let old = base.appending(path: supportDirectoryName)
        let new = base.appending(path: "OnboardStudio")
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path)
        else { return }
        try? fileManager.copyItem(at: old, to: new)
    }
}
