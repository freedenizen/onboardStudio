import Foundation

/// One app-wide setting: its key and the value to use when nobody has chosen one.
///
/// The point is that both halves are written **once**. A bare `@AppStorage("key") var x = default`
/// at each use site repeats the default as a separate literal every time, and two of them can
/// disagree without anything noticing.
public struct Preference<Value: PreferenceValue>: Sendable {
    public let key: String
    /// What the value is before anyone has set it. Not a fallback for a bad value: a stored value
    /// of the right type is honoured even when it is one the UI would not offer.
    public let unset: Value

    public init(key: String, unset: Value) {
        self.key = key
        self.unset = unset
    }
}

/// A type that can be stored in `UserDefaults` and told apart from "nothing stored".
///
/// Reading has to distinguish unset from zero. `double(forKey:)` returns `0` for both, which is
/// why the nudge step needed a "treat zero as unset" guard at one of its two read sites and not
/// at the other.
public protocol PreferenceValue: Sendable {
    static func read(from defaults: UserDefaults, key: String) -> Self?
    func write(to defaults: UserDefaults, key: String)
}

extension String: PreferenceValue {
    public static func read(from defaults: UserDefaults, key: String) -> String? { defaults.string(forKey: key) }
    public func write(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Bool: PreferenceValue {
    // An optional Bool is the whole point here: it is how "nobody has chosen" is told apart from
    // "chosen false", which is the distinction this protocol exists for.
    // swiftlint:disable:next discouraged_optional_boolean
    public static func read(from defaults: UserDefaults, key: String) -> Bool? {
        // `object(forKey:)` to tell unset from false; `bool(forKey:)` to read it, because that is
        // what understands the "NO" a launch argument arrives as.
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }
    public func write(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Double: PreferenceValue {
    public static func read(from defaults: UserDefaults, key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }
    public func write(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

extension Int: PreferenceValue {
    public static func read(from defaults: UserDefaults, key: String) -> Int? {
        defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
    }
    public func write(to defaults: UserDefaults, key: String) { defaults.set(self, forKey: key) }
}

/// Every app-wide setting, declared once.
///
/// Lives in `ProjectModel` rather than the app because two of these are read from other modules —
/// `ffmpegPath` from `MediaKit`, the YouTube credentials from the upload flow — and because the
/// global level of #75's inheritance chain has to sit beside `ProjectSettings` for a project to be
/// able to override it.
public enum Preferences {
    // MARK: - Export

    /// `"project"` means "whatever size this project is set to" rather than a named preset.
    public static let defaultExportPreset = Preference(key: "defaultExportPreset", unset: "project")

    /// App-wide speed unit (#75). `automatic` means "whatever the data was recorded in"; anything
    /// else pins it for every project and object that has not pinned its own.
    public static let speedUnit = Preference(key: "speedUnit", unset: SpeedUnitSetting.automatic.rawValue)

    /// The global attribute mapping (#111): where each attribute comes from, what the file's
    /// numbers are in, and what objects show it in. The level a project and then an input deviate
    /// from — set once, applied to every later import.
    ///
    /// Stored as JSON text because `@AppStorage` carries property-list values and a table of rows
    /// is not one. `AttributeMappingTable(json:)` reads it.
    public static let attributeMappings = Preference(key: "attributeMappings", unset: "")

    // MARK: - Editing

    /// How far one arrow-key press moves the selected object, in pixels of the exported frame.
    public static let nudgeStepPixels = Preference(key: "nudgeStepPixels", unset: 1.0)

    // MARK: - Tools

    /// Empty means search the usual Homebrew locations.
    public static let ffmpegPath = Preference(key: "ffmpegPath", unset: "")

    // MARK: - YouTube

    public static let youTubeClientID = Preference(key: "youtubeClientID", unset: "")
    public static let youTubeClientSecret = Preference(key: "youtubeClientSecret", unset: "")

    // MARK: - First run and the welcome window

    public static let showLauncherAtLaunch = Preference(key: "showLauncherAtLaunch", unset: true)
    public static let tourSeen = Preference(key: "tourSeen", unset: false)
    public static let showGettingStarted = Preference(key: "showGettingStarted", unset: true)

    /// All of them, for the test that no two share a key.
    public static let allKeys: [String] = [
        defaultExportPreset.key, speedUnit.key, attributeMappings.key, nudgeStepPixels.key, ffmpegPath.key,
        youTubeClientID.key,
        youTubeClientSecret.key, showLauncherAtLaunch.key, tourSeen.key, showGettingStarted.key,
    ]
}

extension UserDefaults {
    /// The stored value, or the preference's own `unset` value.
    public func value<Value>(for preference: Preference<Value>) -> Value {
        Value.read(from: self, key: preference.key) ?? preference.unset
    }

    /// Whether anyone has chosen a value, as distinct from it happening to equal the default.
    public func isSet<Value>(_ preference: Preference<Value>) -> Bool {
        object(forKey: preference.key) != nil
    }

    public func set<Value>(_ value: Value, for preference: Preference<Value>) {
        value.write(to: self, key: preference.key)
    }

    /// Back to following the default.
    public func reset<Value>(_ preference: Preference<Value>) {
        removeObject(forKey: preference.key)
    }
}
