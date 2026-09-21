import Foundation
import Testing

@testable import ProjectModel

/// #137: every preference declared once, and resolving to exactly what it resolved to before.
@Suite("Preferences")
struct PreferencesTests {
    /// A throwaway domain so a test never reads or writes the developer's own settings.
    func scratch() -> UserDefaults {
        let name = "onboard-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Unset reads the declared default, which is what it used to read")
    func unsetValuesAreUnchanged() {
        let defaults = scratch()
        // Each of these was a literal at one or more use sites before; these are the literals.
        #expect(defaults.value(for: Preferences.defaultExportPreset) == "project")
        #expect(defaults.value(for: Preferences.ffmpegPath).isEmpty)
        #expect(defaults.value(for: Preferences.youTubeClientID).isEmpty)
        #expect(defaults.value(for: Preferences.youTubeClientSecret).isEmpty)
        #expect(defaults.value(for: Preferences.nudgeStepPixels) == 1.0)
        #expect(defaults.value(for: Preferences.showLauncherAtLaunch) == true)
        #expect(defaults.value(for: Preferences.tourSeen) == false)
        #expect(defaults.value(for: Preferences.showGettingStarted) == true)
    }

    @Test("Setting, reading back, and resetting to follow the default again")
    func roundTrips() {
        let defaults = scratch()
        #expect(!defaults.isSet(Preferences.defaultExportPreset))
        defaults.set("4k", for: Preferences.defaultExportPreset)
        #expect(defaults.isSet(Preferences.defaultExportPreset))
        #expect(defaults.value(for: Preferences.defaultExportPreset) == "4k")
        defaults.reset(Preferences.defaultExportPreset)
        #expect(!defaults.isSet(Preferences.defaultExportPreset))
        #expect(defaults.value(for: Preferences.defaultExportPreset) == "project")
    }

    @Test("Unset is told apart from a stored value that happens to be the type's zero")
    func distinguishesUnsetFromZero() {
        // The reason this protocol exists. `double(forKey:)` returns 0 for unset, so the nudge
        // step needed a "treat zero as unset" guard at one of its two read sites and not at the
        // other — the two readers could disagree about what an unset key meant.
        let defaults = scratch()
        #expect(!defaults.isSet(Preferences.nudgeStepPixels))
        #expect(defaults.value(for: Preferences.nudgeStepPixels) == 1.0)
        defaults.set(0.0, for: Preferences.nudgeStepPixels)
        #expect(defaults.isSet(Preferences.nudgeStepPixels))
        #expect(defaults.value(for: Preferences.nudgeStepPixels) == 0.0)

        // And false is a choice, not an absence — which is what the launcher key always needed.
        #expect(defaults.value(for: Preferences.showLauncherAtLaunch) == true)
        defaults.set(false, for: Preferences.showLauncherAtLaunch)
        #expect(defaults.value(for: Preferences.showLauncherAtLaunch) == false)
        defaults.reset(Preferences.showLauncherAtLaunch)
        #expect(defaults.value(for: Preferences.showLauncherAtLaunch) == true)
    }

    @Test("A launch argument's NO still reads as false")
    func understandsLaunchArgumentBooleans() {
        // The UI tests pass `-tourSeen YES` and `-SUEnableAutomaticChecks NO`, which arrive as
        // strings. `bool(forKey:)` understands them; `object(forKey:) as? Bool` does not, which is
        // recorded in `.claude/rules/uitests.md` as a trap.
        let defaults = scratch()
        defaults.set("NO", forKey: Preferences.showLauncherAtLaunch.key)
        #expect(defaults.value(for: Preferences.showLauncherAtLaunch) == false)
        defaults.set("YES", forKey: Preferences.tourSeen.key)
        #expect(defaults.value(for: Preferences.tourSeen) == true)
    }

    @Test("No two preferences share a key")
    func keysAreUnique() {
        #expect(Set(Preferences.allKeys).count == Preferences.allKeys.count)
        // Empty keys would silently collide in `UserDefaults`.
        #expect(Preferences.allKeys.allSatisfy { !$0.isEmpty })
    }

    @Test("The keys are the ones already on disk, so nobody's settings are forgotten")
    func keepsTheExistingKeyNames() {
        // Renaming a key would quietly reset that setting for every existing install. These are
        // the strings the scattered `@AppStorage` declarations used.
        #expect(Preferences.defaultExportPreset.key == "defaultExportPreset")
        #expect(Preferences.ffmpegPath.key == "ffmpegPath")
        #expect(Preferences.nudgeStepPixels.key == "nudgeStepPixels")
        #expect(Preferences.youTubeClientID.key == "youtubeClientID")
        #expect(Preferences.youTubeClientSecret.key == "youtubeClientSecret")
        #expect(Preferences.showLauncherAtLaunch.key == "showLauncherAtLaunch")
        #expect(Preferences.tourSeen.key == "tourSeen")
        #expect(Preferences.showGettingStarted.key == "showGettingStarted")
    }
}
